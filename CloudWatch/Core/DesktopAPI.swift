import Foundation

public struct AudioResource: Sendable {
    public let playUrl: String?
    public let playUrlExpireTime: Double?
    public let playFlag: Bool?
    public let freeTrailFlag: Bool?
    public let br: Int?
}
public struct QRLogin: Sendable { public let qrCodeUrl: String; public let uniKey: String }
public struct Profile: Sendable { public let nickname: String? }
public enum QRLoginState: Sendable { case waiting, scanned, authorized, expired }

/// Direct desktop EAPI requests. No OpenAPI credentials or desktop relay are required.
public actor DesktopAPI {
    public private(set) var configuration: AccountConfiguration
    private let session: URLSession
    private let cookies: HTTPCookieStorage
    private let persist: Bool
    private var valid = true
    private var playlistsCache: [[String: Any]]?
    private var playlistIDs: [String: [String]] = [:]
    private var activeLoginKey: String?
    private var accountID: String?
    public init(configuration: AccountConfiguration = .init(), session: URLSession? = nil, persist: Bool = true) {
        self.configuration = configuration; self.persist = persist; self.accountID = configuration.userId
        let c = session?.configuration ?? URLSessionConfiguration.ephemeral
        self.cookies = c.httpCookieStorage ?? URLSessionConfiguration.ephemeral.httpCookieStorage!
        cookies.cookieAcceptPolicy = .always
        for cookie in configuration.cookies.compactMap(\.cookie) { cookies.setCookie(cookie) }
        c.httpCookieStorage = cookies
        c.httpShouldSetCookies = true
        c.allowsCellularAccess = true; c.allowsExpensiveNetworkAccess = true; c.allowsConstrainedNetworkAccess = true
        c.timeoutIntervalForRequest = 25; c.timeoutIntervalForResource = 60; c.waitsForConnectivity = true
        self.session = session ?? URLSession(configuration: c)
    }
    private func save() throws {
        guard valid else { throw CancellationError() }
        configuration.cookies = (cookies.cookies ?? []).filter { $0.domain == "music.163.com" || $0.domain.hasSuffix(".music.163.com") }.map(SessionCookie.init)
        configuration.userId = accountID
        if persist { try KeychainStore.save(configuration) }
    }
    public func invalidate() {
        valid = false; session.invalidateAndCancel()
        for cookie in cookies.cookies ?? [] { cookies.deleteCookie(cookie) }
    }
    public func invalidateNetworkIdentity() { playlistsCache = nil; playlistIDs = [:] }
    func request(_ path: String, parameters: [String: Any] = [:], authenticated: Bool = true, allowed: Set<Int> = [200]) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard valid else { throw CancellationError() }
        let url = URL(string: "https://interface.music.163.com" + path)!
        let relevant = cookies.cookies(for: url) ?? []
        if authenticated && !relevant.contains(where: { $0.name == "MUSIC_U" && !$0.value.isEmpty }) { throw MusicError.unauthorized }
        var header: [String: String] = ["os": "OSX", "appver": "3.1.7", "osver": "Version 15.0", "deviceId": configuration.deviceId, "requestId": "\(Int64(Date().timeIntervalSince1970 * 1000))_\(Int.random(in: 0...9999))"]
        if let csrf = relevant.first(where: { $0.name == "__csrf" }) { header["__csrf"] = csrf.value }
        var p = parameters
        p["header"] = try EAPICodec.json(header); p["os"] = "OSX"; p["deviceId"] = configuration.deviceId; p["e_r"] = true
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.httpBody = try EAPICodec.encode(path: path, parameters: p)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("NeteaseMusic/3.1.7 (Mac OS X)", forHTTPHeaderField: "User-Agent")
        var cookieHeader = HTTPCookie.requestHeaderFields(with: relevant)["Cookie"] ?? ""
        for (k,v) in ["os":"OSX", "appver":"3.1.7", "deviceId":configuration.deviceId] where !relevant.contains(where: { $0.name == k }) { cookieHeader += (cookieHeader.isEmpty ? "" : "; ") + "\(k)=\(v)" }
        req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: req)
        try Task.checkCancellation(); guard valid else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw MusicError.message("未收到服务器响应。") }
        guard (200..<300).contains(http.statusCode) else { if http.statusCode == 401 { throw MusicError.unauthorized }; throw MusicError.message("网络服务暂不可用（\(http.statusCode)）。") }
        let value = try EAPICodec.decode(data)
        let code = (value["code"] as? NSNumber)?.intValue ?? -1
        if [301, 401, -460].contains(code) { throw MusicError.unauthorized }
        guard allowed.contains(code) else { throw MusicError.message(value["message"] as? String ?? value["msg"] as? String ?? "请求未完成（\(code)）。") }
        if authenticated { try save() }
        return value
    }
    public static func qrURL(key: String) -> String {
        var url = URLComponents(string: "https://music.163.com/login")!
        url.queryItems = [URLQueryItem(name: "codekey", value: key)]
        return url.url!.absoluteString
    }
    public func beginLogin() async throws -> QRLogin {
        let r = try await request("/eapi/login/qrcode/unikey", parameters: ["type":"4"], authenticated:false)
        guard let key = r["unikey"] as? String, !key.isEmpty else { throw MusicError.message("无法获取登录二维码。") }
        activeLoginKey = key
        return QRLogin(qrCodeUrl: Self.qrURL(key:key), uniKey:key)
    }
    public func pollLogin(key: String) async throws -> QRLoginState {
        guard activeLoginKey == key else { throw CancellationError() }
        let r = try await request("/eapi/login/qrcode/client/login", parameters:["key":key,"type":"4","secureCaptcha":""], authenticated:false, allowed:[800,801,802,803])
        guard activeLoginKey == key else { throw CancellationError() }
        switch (r["code"] as? Int) {
        case 800: return .expired
        case 801: return .waiting
        case 802: return .scanned
        case 803:
            _ = try await profile(); try save(); return .authorized
        default: throw MusicError.message("无法识别二维码状态。")
        }
    }
    public func refresh() async throws {
        _ = try await request("/eapi/login/token/refresh"); try save()
    }
    public func profile() async throws -> Profile {
        let r = try await request("/eapi/w/nuser/account/get")
        guard let p = r["profile"] as? [String:Any], let id = Self.id(p["userId"]) else { throw MusicError.unauthorized }
        accountID = id; try save()
        return Profile(nickname:p["nickname"] as? String)
    }
    public func daily() async throws -> [Song] {
        let r = try await request("/eapi/v3/discovery/recommend/songs", parameters:["limit":"30"])
        guard let d = r["data"] as? [String:Any], let songs = d["dailySongs"] as? [[String:Any]] else { throw MusicError.message("每日推荐数据格式不正确。") }
        return try songs.map(Self.song)
    }
    private func allPlaylists() async throws -> [[String:Any]] {
        if let cache = playlistsCache { return cache }
        if accountID == nil { _ = try await profile() }
        guard let uid = accountID else { throw MusicError.unauthorized }
        var result: [[String:Any]] = []; var offset = 0
        while true {
            let r = try await request("/eapi/user/playlist", parameters:["uid":uid,"limit":"1000","offset":String(offset)])
            guard let page = r["playlist"] as? [[String:Any]] else { throw MusicError.message("歌单数据格式不正确。") }
            result += page; offset += page.count
            if r["more"] as? Bool != true { break }
            guard !page.isEmpty else { throw MusicError.message("歌单分页返回异常，请重试。") }
        }
        playlistsCache = result; return result
    }
    public func playlists(collected: Bool, offset: Int = 0) async throws -> Page<Playlist> {
        let all = try await allPlaylists()
        let filtered = all.filter { item in
            let owner = Self.id(item["userId"]) ?? Self.id((item["creator"] as? [String:Any])?["userId"])
            return collected ? owner != accountID : owner == accountID
        }
        return Page(records:try filtered.dropFirst(max(0,offset)).prefix(30).map(Self.playlist),recordCount:filtered.count)
    }
    public func favorite() async throws -> Playlist {
        let all = try await allPlaylists()
        guard let item = all.first(where:{ ($0["specialType"] as? Int) == 5 && Self.id($0["userId"]) == accountID }) else { throw MusicError.message("未找到我喜欢的音乐歌单。") }
        return try Self.playlist(item)
    }
    public func tracks(_ id: String, offset: Int = 0) async throws -> Page<Song> {
        var ids = playlistIDs[id]
        if ids == nil {
            let r = try await request("/eapi/v6/playlist/detail", parameters:["id":id,"n":"0"])
            guard let p = r["playlist"] as? [String:Any], let list = p["trackIds"] as? [[String:Any]] else { throw MusicError.message("歌单歌曲数据格式不正确。") }
            ids = list.compactMap { Self.id($0["id"]) }; playlistIDs[id] = ids
        }
        let all = ids ?? []; let page = Array(all.dropFirst(max(0,offset)).prefix(30))
        if page.isEmpty { return Page(records:[],recordCount:all.count) }
        let c = try EAPICodec.json(page.map { ["id":$0] })
        let r = try await request("/eapi/v3/song/detail", parameters:["c":c])
        guard let songs = r["songs"] as? [[String:Any]] else { throw MusicError.message("歌曲详情数据格式不正确。") }
        let mapped = try songs.map(Self.song)
        let byID = Dictionary(mapped.map { ($0.id,$0) }, uniquingKeysWith: { a,_ in a })
        return Page(records:page.compactMap { byID[$0] },recordCount:all.count,nextOffset:min(all.count,max(0,offset) + page.count))
    }
    public func search(_ text: String, offset: Int = 0) async throws -> Page<Song> {
        let r = try await request("/eapi/search/song/list/page", parameters:["keyword":text,"needCorrect":"true","channel":"defaultquery","scene":"normal","offset":String(offset),"limit":"30"])
        guard let d = r["data"] as? [String:Any], let resources = d["resources"] as? [[String:Any]] else { throw MusicError.message("搜索结果格式不正确。") }
        let songs = try resources.map { resource -> Song in
            guard let b = resource["baseInfo"] as? [String:Any], let s = b["simpleSongData"] as? [String:Any] else { throw MusicError.message("搜索歌曲格式不正确。") }
            return try Self.song(s)
        }
        return Page(records:songs,recordCount:(d["totalCount"] as? Int) ?? (offset + songs.count + ((d["hasMore"] as? Bool == true) ? 1 : 0)))
    }
    public func audio(_ song: Song, bitrate: Int = 128) async throws -> AudioResource {
        let r = try await request("/eapi/song/enhance/player/url/v1", parameters:["ids":try EAPICodec.json([song.id]),"level":bitrate > 128 ? "exhigh" : "standard","encodeType":"aac","immerseType":"c51","trialMode":"35"])
        guard let rows = r["data"] as? [[String:Any]], let item = rows.first(where:{ Self.id($0["id"]) == song.id }) else { throw MusicError.message("服务器未返回音源信息。") }
        let url = item["url"] as? String
        guard item["code"] as? Int == 200, let url, !url.isEmpty else { throw MusicError.message("该歌曲当前账号没有可用音源，请检查会员或地区权限。") }
        return AudioResource(playUrl:url,playUrlExpireTime:(item["expi"] as? Double).map { Date().timeIntervalSince1970 + $0 },playFlag:true,freeTrailFlag:item["freeTrialInfo"] is [String:Any],br:item["br"] as? Int)
    }
    static func id(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }
    static func song(_ s: [String:Any]) throws -> Song {
        guard let id = id(s["id"]), let name = s["name"] as? String else { throw MusicError.message("歌曲数据不完整。") }
        let album = s["al"] as? [String:Any]
        let artists = (s["ar"] as? [[String:Any]])?.compactMap { ($0["name"] as? String).map(Artist.init) }
        // Listing flags are not an audio authorization result. Resolve the URL when tapped.
        return Song(id:id,originalId:Int64(id),name:name,artists:artists,coverImgUrl:album?["picUrl"] as? String,duration:(s["dt"] as? Double).map { $0 / 1000 },playFlag:nil,freeTrailFlag:nil)
    }
    static func playlist(_ p: [String:Any]) throws -> Playlist {
        guard let id = id(p["id"]), let name = p["name"] as? String else { throw MusicError.message("歌单数据不完整。") }
        return Playlist(id:id,name:name,coverImgUrl:p["coverImgUrl"] as? String,trackCount:p["trackCount"] as? Int)
    }
}
