import Foundation

public struct WeChatRecentRecord: Codable, Sendable {
    public let id: String
    public let title: String
    public let last_activity: Double
}

public struct WeChatRecentListing: Codable, Sendable {
    public let version: Int
    public let source: String
    public let account_scope: String
    public let generated_at: Double
    public let hidden_filtered: Bool
    public let native_root_verified: Bool
    public let metadata_only: Bool
    public let limit: Int
    public let sessions: [WeChatRecentRecord]
}

public enum WeChatRecentSource {
    public static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/the-vibekey/wechat-source.json")
    }
    public struct Config: Codable, Sendable {
        public let endpoint: String
        public let tokenFile: String
        public let feedFile: String
        public let accountScope: String
    }
    public struct Failure: Error, LocalizedError {
        public let errorDescription: String?
        public init(_ text: String) { errorDescription = text }
    }
    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    public static func validated(_ data: Data, expectedScope: String, requestedAt: Double,
                                 now: Double = Date().timeIntervalSince1970) throws -> WeChatRecentListing {
        guard data.count <= 1_048_576 else { throw Failure("微信会话元数据过大。") }
        let value = try JSONDecoder().decode(WeChatRecentListing.self, from: data)
        guard value.version == 1, value.source == "macOS.WeChat.SessionTable", value.limit == 50,
              value.hidden_filtered, value.native_root_verified, value.metadata_only else {
            throw Failure("尚未确认本机当前聊天列表，未导入历史联系人。")
        }
        guard expectedScope.count == 64, expectedScope.allSatisfy({ $0.isHexDigit }), value.account_scope == expectedScope else {
            throw Failure("微信账号来源不匹配，未混入其他账号会话。")
        }
        guard value.generated_at.isFinite, value.generated_at >= requestedAt - 1,
              value.generated_at <= now + 10 else { throw Failure("微信会话列表未完成本次刷新。") }
        guard value.sessions.count <= 50 else { throw Failure("微信会话数量超过50条。") }
        var ids = Set<String>(), previous = Double.infinity
        for item in value.sessions {
            guard UUID(uuidString: item.id) != nil, ids.insert(item.id).inserted,
                  !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.title.count <= 512, !item.title.contains("\n"), !item.title.contains("\r"),
                  item.last_activity.isFinite, item.last_activity > 0,
                  item.last_activity <= now + 300, item.last_activity <= previous else {
                throw Failure("微信会话标识或最近联系顺序不完整。")
            }
            previous = item.last_activity
        }
        return value
    }
    public static func fetch(configURL: URL) async throws -> WeChatRecentListing {
        let raw = try Data(contentsOf: configURL)
        guard raw.count < 16_384 else { throw Failure("微信本机来源配置无效。") }
        let config = try JSONDecoder().decode(Config.self, from: raw)
        guard var parts = URLComponents(string: config.endpoint), parts.scheme == "http",
              parts.host == "127.0.0.1", parts.port != nil, parts.user == nil, parts.password == nil,
              parts.path == "/api/v1/sessions", config.tokenFile.hasPrefix("/"), config.feedFile.hasPrefix("/") else {
            throw Failure("微信来源必须是已有的本机只读接口。")
        }
        parts.queryItems = [URLQueryItem(name: "limit", value: "1")]
        let tokenData = try Data(contentsOf: URL(fileURLWithPath: config.tokenFile))
        guard tokenData.count <= 8192, let token = String(data: tokenData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty, !token.contains("\n"), !token.contains("\r") else { throw Failure("微信本机接口凭据不可用。") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: parts.url!, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let start = Date().timeIntervalSince1970
        // Existing backend refreshes the metadata-only sidecar. The response also
        // contains metadata only; no message, search, mark-read or send API is used.
        let (body, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              body.count <= 65_536,
              (try JSONSerialization.jsonObject(with: body) as? [String: Any])?["success"] as? Bool == true else {
            throw Failure("本机微信只读服务未就绪，未更新会话列表。")
        }
        try Task.checkCancellation()
        return try validated(Data(contentsOf: URL(fileURLWithPath: config.feedFile)), expectedScope: config.accountScope, requestedAt: start)
    }
}
