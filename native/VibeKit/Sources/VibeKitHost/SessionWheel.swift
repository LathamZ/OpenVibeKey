import Foundation

/// Pure paging policy. Rotation wraps inside eight slots; only paging changes the disc.
public enum SessionWheelPaging {
    public static let pageSize = 8
    public static func pageCount(_ count: Int) -> Int { max(0, count) / pageSize + (max(0, count) % pageSize == 0 ? 0 : 1) }
    public static func page(selection: Int, count: Int) -> Int { count > 0 ? min(max(0, selection), count - 1) / pageSize : 0 }
    public static func range(selection: Int, count: Int) -> Range<Int> {
        let start = page(selection: selection, count: count) * pageSize
        return start..<(start + min(pageSize, max(0, count - start)))
    }
    public static func rotated(selection: Int, count: Int, delta: Int) -> Int {
        let range = range(selection: selection, count: count)
        guard !range.isEmpty else { return 0 }
        let offset = min(max(0, selection - range.lowerBound), range.count - 1)
        return range.lowerBound + (offset + delta % range.count + range.count) % range.count
    }
    public static func turned(selection: Int, count: Int, delta: Int) -> Int {
        let pages = pageCount(count)
        guard pages > 0 else { return 0 }
        let current = min(max(0, selection), count - 1)
        let target = (current / pageSize + delta % pages + pages) % pages
        let start = target * pageSize
        return start + min(current % pageSize, count - start - 1)
    }
    public static func ordered(_ sessions: [CodexSession], activity: [String: Double], opened: [String: Double]) -> [CodexSession] {
        func timestamp(_ id: String) -> Double {
            let raw = activity[id] ?? 0
            let server = raw > 10_000_000_000 ? raw / 1000 : raw
            let local = opened[id] ?? 0
            return max(server.isFinite ? max(0, server) : 0, local.isFinite ? max(0, local) : 0)
        }
        return sessions.sorted {
            let a = timestamp($0.id), b = timestamp($1.id)
            if a != b { return a > b }
            return $0.id < $1.id
        }
    }
}

public struct SessionColorLedger: Codable, Equatable, Sendable {
    public static let palette = ["9196FF", "55D5C3", "FFBE77", "F493B5", "C39AF2", "76BFFA", "ADCE77", "E8A57A"]
    public private(set) var colors: [String: String]
    public init(colors: [String: String] = [:]) { self.colors = colors.filter { Self.isValid($0.value) }.mapValues { $0.uppercased() } }
    public static func isValid(_ hex: String) -> Bool { hex.count == 6 && hex.allSatisfy { $0.isHexDigit && $0.isASCII } }
    @discardableResult public mutating func ensure(ids: [String], pick: (Int) -> Int = { Int.random(in: 0..<$0) }) -> Bool {
        var changed = false
        var counts = Self.palette.map { hex in colors.values.filter { $0 == hex }.count }
        for id in ids where colors[id] == nil {
            let least = counts.min() ?? 0
            let choices = Self.palette.enumerated().filter { counts[$0.offset] == least }.map(\.element)
            let color = choices[((pick(choices.count) % choices.count) + choices.count) % choices.count]
            colors[id] = color
            if let index = Self.palette.firstIndex(of: color) { counts[index] += 1 }
            changed = true
        }
        return changed
    }
    @discardableResult public mutating func set(id: String, hex: String) -> Bool {
        guard Self.isValid(hex) else { return false }
        colors[id] = hex.uppercased(); return true
    }
}

/// One page per physical release; context changes cancel intent but retain the held barrier.
public struct WheelPagePress {
    private var held = Set<String>()
    private var stamps: [String: UUID] = [:]
    public var isHeld: Bool { !held.isEmpty }
    public init() {}
    public mutating func press(_ slot: String, generation: UUID) {
        guard slot == "btn1" || slot == "btn2", held.insert(slot).inserted else { return }
        stamps[slot] = generation
    }
    public mutating func release(_ slot: String, generation: UUID, eligible: Bool) -> Int? {
        let wasHeld = held.remove(slot) != nil
        let stamp = stamps.removeValue(forKey: slot)
        guard wasHeld, eligible, stamp == generation else { return nil }
        return slot == "btn1" ? -1 : 1
    }
    public mutating func cancel() { stamps.removeAll() }
    public mutating func reset() { self = Self() }
}


/// Fractional physical detents plus nearest-stop settling. No acceleration or synthetic events.
public struct SessionWheelMotion {
    public private(set) var position = 0.0
    public private(set) var count = 0
    public private(set) var start = 0
    public init() {}
    public static func steps(_ raw: Double) -> Double { raw.isFinite ? min(8, max(1, raw.rounded())) : 3 }
    public mutating func reset(selection: Int, total: Int) {
        let range = SessionWheelPaging.range(selection: selection, count: total)
        start = range.lowerBound; count = range.count
        position = Double(max(0, min(selection - start, count - 1)))
    }
    public mutating func turn(_ delta: Int, stepsPerItem: Double) {
        guard count > 1 else { return }
        position += Double(delta) / Self.steps(stepsPerItem)
        if abs(position) > 1_000_000 { position = position.truncatingRemainder(dividingBy: Double(count)) }
    }
    public var nearest: Int {
        guard count > 0 else { return start }
        let value = position.rounded(.toNearestOrAwayFromZero).truncatingRemainder(dividingBy: Double(count))
        return start + Int((value + Double(count)).truncatingRemainder(dividingBy: Double(count)))
    }
    public mutating func settle() { position = position.rounded(.toNearestOrAwayFromZero) }
}
