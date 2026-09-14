import Foundation

public struct Artist: Codable, Hashable, Sendable { public let name: String }
public struct Song: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let originalId: Int64?
    public let name: String
    public let artists: [Artist]?
    public let coverImgUrl: String?
    public let duration: Double?
    public let playFlag: Bool?
    public let freeTrailFlag: Bool?
    public var artist: String { artists?.map(\.name).joined(separator: " / ") ?? "未知歌手" }
    public var artwork: URL? { secureArtwork(coverImgUrl) }
    public var playable: Bool { playFlag != false }
}
public struct Playlist: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let coverImgUrl: String?
    public let trackCount: Int?
    public var artwork: URL? { secureArtwork(coverImgUrl) }
}
public func secureArtwork(_ value: String?) -> URL? {
    guard let value, var c = URLComponents(string: value) else { return nil }
    if c.scheme == "http", c.host?.hasSuffix(".126.net") == true { c.scheme = "https" }
    return c.url
}
public struct Page<T: Codable & Sendable>: Codable, Sendable {
    public let records: [T]
    public let recordCount: Int?
    public var nextOffset: Int? = nil
}
public enum MusicError: LocalizedError {
    case message(String), unauthorized, unconfigured
    public var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .unauthorized: return "登录已失效，请重新扫码登录。"
        case .unconfigured: return "请先配置应用凭据。"
        }
    }
}
public struct PlayQueue: Sendable {
    public private(set) var songs: [Song] = []
    public private(set) var index = 0
    public var current: Song? { songs.indices.contains(index) ? songs[index] : nil }
    public mutating func replace(_ songs: [Song], startingAt id: String) {
        self.songs = songs.filter(\.playable); index = self.songs.firstIndex { $0.id == id } ?? 0
    }
    @discardableResult public mutating func advance(repeatAll: Bool = false) -> Bool {
        guard !songs.isEmpty else { return false }
        if index + 1 < songs.count { index += 1; return true }
        if repeatAll { index = 0; return true }; return false
    }
    @discardableResult public mutating func previous() -> Bool { guard index > 0 else { return false }; index -= 1; return true }
    public mutating func select(_ id: String) { if let i = songs.firstIndex(where: { $0.id == id }) { index = i } }
}
