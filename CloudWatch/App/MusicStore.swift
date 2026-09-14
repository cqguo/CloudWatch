import SwiftUI
import Network

@MainActor final class MusicStore: ObservableObject {
    @Published var api: DesktopAPI?
    @Published var daily: [Song] = []
    @Published var created: [Playlist] = []
    @Published var collected: [Playlist] = []
    @Published var favorite: Playlist?
    @Published var nickname = "我的音乐"
    @Published var loading = false
    @Published var error: String?
    @Published var libraryErrors: [String] = []
    @Published var qr: QRLogin?
    @Published var loginMessage = "用网易云音乐 App 扫码"
    @Published var network = "正在连接"
    @Published var ready = false
    @Published var createdMore = false
    @Published var collectedMore = false
    private var accountGeneration = UUID()
    private var monitor = NWPathMonitor()
    private var loginTask: Task<Void, Never>?
    private var libraryTask: Task<Void, Never>?
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let label = path.status != .satisfied ? "网络不可用" : path.usesInterfaceType(.cellular) ? "蜂窝网络" : path.usesInterfaceType(.wifi) ? "Wi-Fi" : "已连接"
            Task { @MainActor in self?.network = label; await self?.api?.invalidateNetworkIdentity() }
        }
        monitor.start(queue: DispatchQueue(label:"cloudwatch.network"))
        configure(KeychainStore.load() ?? AccountConfiguration())
        #if DEBUG
        #if targetEnvironment(simulator)
        if CommandLine.arguments.contains("--export-session"), let config = KeychainStore.load() {
            let target = URL.documentsDirectory.appending(path:"session-transfer.json")
            do {
                try JSONEncoder().encode(config).write(to:target,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:target.path)
            } catch { self.error = "无法导出测试会话。" }
        }
        #endif
        let file = URL.documentsDirectory.appending(path: "provisioning.json")
        if let data = try? Data(contentsOf:file), let config = try? JSONDecoder().decode(AccountConfiguration.self, from:data) {
            do { try KeychainStore.save(config); try FileManager.default.removeItem(at:file); configure(config) } catch { self.error = error.localizedDescription }
        }
        #endif
    }
    func configure(_ config: AccountConfiguration) {
        accountGeneration = UUID(); api = DesktopAPI(configuration:config); ready = config.loggedIn
        if ready {
            let service = api; let generation = accountGeneration
            libraryTask?.cancel(); libraryTask = Task {
                do { try await service?.refresh() } catch is CancellationError { return } catch { /* Library requests report a stale session or network error. */ }
                guard generation == accountGeneration else { return }
                await refreshLibrary()
            }
        }
    }
    func refreshLibrary() async {
        guard let api, !loading else { return }; let generation = accountGeneration; loading = true; libraryErrors = []
        defer { if generation == accountGeneration { loading = false } }
        await api.invalidateNetworkIdentity()
        // Independent failures keep other library sections usable.
        do { let result = try await api.daily(); guard generation == accountGeneration else { return }; daily = result } catch { libraryErrors.append("每日推荐：\(error.localizedDescription)") }
        if Task.isCancelled || generation != accountGeneration { return }
        do { let p = try await api.playlists(collected:false); guard generation == accountGeneration else { return }; created = p.records; createdMore = p.records.count < (p.recordCount ?? p.records.count) } catch { libraryErrors.append("创建的歌单：\(error.localizedDescription)") }
        if Task.isCancelled || generation != accountGeneration { return }
        do { let p = try await api.playlists(collected:true); guard generation == accountGeneration else { return }; collected = p.records; collectedMore = p.records.count < (p.recordCount ?? p.records.count) } catch { libraryErrors.append("收藏的歌单：\(error.localizedDescription)") }
        do { let result = try await api.favorite(); guard generation == accountGeneration else { return }; favorite = result } catch { libraryErrors.append("喜欢的音乐：\(error.localizedDescription)") }
        if let profile = try? await api.profile(), generation == accountGeneration { nickname = profile.nickname ?? "我的音乐" }
    }
    func morePlaylists(collected isCollected: Bool) async {
        guard let api, !loading else { return }; loading = true; defer { loading = false }
        do {
            let old = isCollected ? collected : created
            let page = try await api.playlists(collected:isCollected, offset:old.count)
            let all = old + page.records.filter { song in !old.contains { $0.id == song.id } }
            let more = !page.records.isEmpty && all.count < (page.recordCount ?? all.count)
            if isCollected { collected = all; collectedMore = more } else { created = all; createdMore = more }
        } catch { self.error = error.localizedDescription }
    }
    func login() {
        guard let api else { return }
        loginTask?.cancel(); let generation = accountGeneration; qr = nil; loginMessage = "正在生成二维码…"
        loginTask = Task {
            do {
                let code = try await api.beginLogin(); try Task.checkCancellation(); guard generation == accountGeneration else { return }; qr = code; loginMessage = "用网易云音乐 App 扫码"
                let deadline = Date().addingTimeInterval(290)
                while !Task.isCancelled && Date() < deadline {
                    try await Task.sleep(for:.seconds(3))
                    do {
                        let state = try await api.pollLogin(key:code.uniKey)
                        try Task.checkCancellation(); guard generation == accountGeneration else { return }
                        switch state {
                        case .waiting: loginMessage = "用网易云音乐 App 扫码"
                        case .scanned: loginMessage = "已扫码，请在手机上确认"
                        case .expired: loginMessage = "二维码已过期，请重新生成。"; return
                        case .authorized: ready = true; qr = nil; libraryTask?.cancel(); libraryTask = Task { await refreshLibrary() }; return
                        }
                    } catch {
                        let message = error.localizedDescription
                        if message.contains("过期") || message.contains("失效") { throw error }
                        loginMessage = message.contains("扫码") || message.contains("授权") ? message : "等待扫码并确认登录"
                    }
                }
                if !Task.isCancelled { loginMessage = "二维码已过期，请重新生成。" }
            } catch is CancellationError { } catch { loginMessage = error.localizedDescription }
        }
    }
    func cancelLogin() { loginTask?.cancel(); qr = nil }
    func logout() {
        accountGeneration = UUID(); loading = false; loginTask?.cancel(); libraryTask?.cancel(); let old = api; let generation = accountGeneration; Task { await old?.invalidate(); if generation == accountGeneration { KeychainStore.delete() } }; KeychainStore.delete(); api = DesktopAPI(); ready = false
        daily = []; created = []; collected = []; favorite = nil; nickname = "我的音乐"; libraryErrors = []
    }
}
