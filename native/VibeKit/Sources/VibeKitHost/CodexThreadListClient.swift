import Foundation
import Darwin

public struct CodexThreadSummary: Codable, Equatable, Sendable {
    public let session: CodexSession
    public let project: String
    public let updatedAt: Int64
    public init(session: CodexSession, project: String, updatedAt: Int64) {
        self.session = session; self.project = project; self.updatedAt = updatedAt
    }
}
public struct CodexThreadListing: Sendable {
    public let threads: [CodexThreadSummary]
    public let hasMore: Bool
    public let pages: Int
    public let rejected: Int
}
public enum CodexThreadListFailure: Error, LocalizedError {
    case executableMissing, launchFailed, timeout, malformedReply, responseTooLarge, serverRejected, cancelled, paginationLoop
    public var errorDescription: String? {
        switch self {
        case .executableMissing: return "未找到当前 Codex 应用的命令行组件。"
        case .timeout: return "读取会话列表超时。"
        case .cancelled: return "会话读取已取消。"
        case .serverRejected: return "Codex 暂时无法提供本机会话列表。"
        case .paginationLoop: return "会话分页返回了重复游标，已停止读取。"
        case .responseTooLarge: return "会话列表响应超出读取上限。"
        default: return "无法读取本机会话列表，请稍后刷新。"
        }
    }
}

public enum CodexSessionCatalog {
    /// Server names take precedence; manually pinned IDs remain first and never duplicate recent chats.
    public static func merge(pinned: [CodexSession], recent: [CodexThreadSummary]) -> [CodexSession] {
        var byID: [String: CodexSession] = [:]
        for item in recent where item.session.isValid { if byID[item.session.id] == nil { byID[item.session.id] = item.session } }
        var seen = Set<String>(), result: [CodexSession] = []
        for pin in pinned where pin.isValid && seen.insert(pin.id).inserted { result.append(byID[pin.id] ?? pin) }
        for item in recent where item.session.isValid && seen.insert(item.session.id).inserted { result.append(item.session) }
        return result
    }
    public static func filter(_ sessions: [CodexSession], query: String, projects: [String: String]) -> [CodexSession] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return sessions }
        return sessions.filter { ($0.title + " " + $0.id + " " + (projects[$0.id] ?? "")).localizedCaseInsensitiveContains(term) }
    }
}

/// Official JSONL stdio protocol. This client only initializes and reads non-archived metadata.
/// No thread/start, resume, turns, messages, raw history scanning, database access or shared-daemon management.
public struct CodexThreadListClient: Sendable {
    public let executable: URL
    public let arguments: [String]
    public init(executable: URL, arguments: [String] = ["app-server", "--listen", "stdio://"]) {
        self.executable = executable; self.arguments = arguments
    }
    public static func parsePage(_ object: [String: Any]) throws -> (threads: [CodexThreadSummary], cursor: String?, rejected: Int) {
        guard let data = object["data"] as? [[String: Any]] else { throw CodexThreadListFailure.malformedReply }
        if let cursor = object["nextCursor"], !(cursor is NSNull), !(cursor is String) { throw CodexThreadListFailure.malformedReply }
        var threads: [CodexThreadSummary] = [], rejected = 0
        for row in data {
            guard let id = row["id"] as? String, let uuid = UUID(uuidString: id) else { rejected += 1; continue }
            // preview is the first user message, not the user-facing chat name: deliberately do not use it.
            let name = (row["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = name?.isEmpty == false ? name! : "未命名会话 · " + String(uuid.uuidString.suffix(8)).lowercased()
            guard let session = CodexSession(reference: id, title: label, maximumTitleLength: 4096) else { rejected += 1; continue }
            let cwd = row["cwd"] as? String ?? ""
            threads.append(.init(session: session, project: cwd.isEmpty ? "" : URL(fileURLWithPath: cwd).lastPathComponent,
                                 updatedAt: (row["updatedAt"] as? NSNumber)?.int64Value ?? 0))
        }
        let cursor = object["nextCursor"] as? String
        return (threads, cursor?.isEmpty == false ? cursor : nil, rejected)
    }
    public func fetch(pageSize: Int = 100, maximumPages: Int = 20, timeout: TimeInterval = 12,
                      cancelled: () -> Bool = { false }) throws -> CodexThreadListing {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw CodexThreadListFailure.executableMissing }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = executable; process.arguments = arguments
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { throw CodexThreadListFailure.launchFailed }
        defer {
            try? input.fileHandleForWriting.close()
            if exited.wait(timeout: .now() + 0.5) == .timedOut {
                if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGTERM) }
                if exited.wait(timeout: .now() + 0.5) == .timedOut, process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
            }
            try? output.fileHandleForReading.close()
        }
        _ = Darwin.fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var buffer = Data()
        func checkDeadline() throws {
            if cancelled() { throw CodexThreadListFailure.cancelled }
            if ProcessInfo.processInfo.systemUptime >= deadline { throw CodexThreadListFailure.timeout }
        }
        func send(id: Int? = nil, method: String, params: [String: Any]? = nil) throws {
            guard ["initialize", "initialized", "thread/list"].contains(method) else { throw CodexThreadListFailure.serverRejected }
            try checkDeadline()
            var request: [String: Any] = ["method": method]
            if let id { request["id"] = id }; if let params { request["params"] = params }
            let data = try JSONSerialization.data(withJSONObject: request) + Data([10])
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        func response(id: Int) throws -> [String: Any] {
            while true {
                try checkDeadline()
                if let newline = buffer.firstIndex(of: 10) {
                    let line = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline)
                    guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { throw CodexThreadListFailure.malformedReply }
                    guard (message["id"] as? NSNumber)?.intValue == id else { continue }
                    if message["error"] != nil { throw CodexThreadListFailure.serverRejected }
                    guard let result = message["result"] as? [String: Any] else { throw CodexThreadListFailure.malformedReply }
                    return result
                }
                var fd = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
                let polled = Darwin.poll(&fd, 1, 100)
                if polled < 0 { if errno == EINTR { continue }; throw CodexThreadListFailure.malformedReply }
                if polled == 0 { continue }
                var chunk = [UInt8](repeating: 0, count: 65_536)
                let count = Darwin.read(fd.fd, &chunk, chunk.count)
                guard count > 0 else { throw CodexThreadListFailure.malformedReply }
                buffer.append(contentsOf: chunk.prefix(count))
                guard buffer.count <= 16 * 1024 * 1024 else { throw CodexThreadListFailure.responseTooLarge }
            }
        }
        try send(id: 1, method: "initialize", params: ["clientInfo": ["name": "vibekey_navigation", "version": "0.1.6-lr.4"],
                                                     "capabilities": ["experimentalApi": false]])
        _ = try response(id: 1)
        try send(method: "initialized")
        var cursor: String?, seenCursors = Set<String>(), seenIDs = Set<String>(), threads: [CodexThreadSummary] = []
        var pages = 0, rejected = 0
        while pages < max(1, maximumPages) {
            var params: [String: Any] = ["limit": max(1, min(100, pageSize)), "archived": false, "modelProviders": [String](),
                "sortKey": "updated_at", "sortDirection": "desc", "useStateDbOnly": true]
            if let cursor { params["cursor"] = cursor }
            try send(id: 2 + pages, method: "thread/list", params: params)
            let page = try Self.parsePage(response(id: 2 + pages)); pages += 1; rejected += page.rejected
            for item in page.threads where seenIDs.insert(item.session.id).inserted { threads.append(item) }
            cursor = page.cursor
            guard let cursor else { break }
            guard seenCursors.insert(cursor).inserted else { throw CodexThreadListFailure.paginationLoop }
        }
        return .init(threads: threads, hasMore: cursor != nil, pages: pages, rejected: rejected)
    }
}
