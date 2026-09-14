import SwiftUI
import WatchKit

private let accent = Color(red:1,green:0.22,blue:0.34)
struct RootView: View {
    @EnvironmentObject var store: MusicStore
    @EnvironmentObject var player: AudioPlayer
    var body: some View {
        NavigationStack {
            Group {
                #if DEBUG
                if CommandLine.arguments.contains("--show-login") && !store.ready { LoginView() }
                else if store.ready { LibraryView() } else { WelcomeView() }
                #else
                if store.ready { LibraryView() } else { WelcomeView() }
                #endif
            }
            .navigationDestination(isPresented:$player.showPlayer) { PlayerView() }
            .alert("暂时无法完成", isPresented:Binding(get:{ store.error != nil },set:{ if !$0 { store.error = nil } })) { Button("知道了") { store.error = nil } } message: { Text(store.error ?? "") }
        }
    }
}
struct Artwork: View {
    let url: URL?; var size: CGFloat = 42; var symbol = "music.note"
    var body: some View {
        AsyncImage(url:url) { image in image.resizable().scaledToFill() } placeholder: {
            ZStack { LinearGradient(colors:[accent.opacity(0.7),Color(red:0.25,green:0.12,blue:0.2)],startPoint:.topLeading,endPoint:.bottomTrailing); Image(systemName:symbol).font(.system(size:size*0.35,weight:.medium)).foregroundStyle(.white.opacity(0.8)) }
        }.frame(width:size,height:size).clipShape(RoundedRectangle(cornerRadius:size*0.16)).accessibilityHidden(true)
    }
}
struct LibraryView: View {
    @EnvironmentObject var store: MusicStore
    @EnvironmentObject var player: AudioPlayer
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:12) {
                HStack { Text("现在就听").font(.system(size:23,weight:.bold)); Spacer(); Image(systemName:store.network == "蜂窝网络" ? "antenna.radiowaves.left.and.right" : "wifi").font(.caption2).foregroundStyle(.secondary).accessibilityLabel(store.network) }
                NavigationLink { SongListView(title:"每日推荐", source:.daily) } label: {
                    ZStack(alignment:.bottomLeading) {
                        LinearGradient(colors:[Color(red:0.86,green:0.1,blue:0.27),Color(red:0.38,green:0.04,blue:0.14)],startPoint:.topLeading,endPoint:.bottomTrailing)
                        HStack { Spacer(); Image(systemName:"sun.max.fill").font(.system(size:68)).foregroundStyle(.white.opacity(0.15)).offset(x:10,y:-15) }
                        VStack(alignment:.leading,spacing:5) {
                            Text(Date(),format:.dateTime.day()).font(.system(size:30,weight:.bold,design:.rounded))
                            Text("每日推荐").font(.headline)
                            Text(store.loading && store.daily.isEmpty ? "正在为你加载" : "为你精选 · \(store.daily.count) 首").font(.caption2).opacity(0.8)
                        }.padding(13)
                    }.frame(height:118).clipShape(RoundedRectangle(cornerRadius:18))
                }.buttonStyle(.plain)
                if let favorite = store.favorite {
                    NavigationLink { SongListView(title:"我喜欢的音乐", source:.playlist(favorite)) } label: { FeatureRow(title:"我喜欢的音乐", subtitle:"\(favorite.trackCount ?? 0) 首歌曲", symbol:"heart.fill", color:.pink) }.buttonStyle(.plain)
                }
                NavigationLink { PlaylistsView() } label: { FeatureRow(title:"我的歌单", subtitle:"创建与收藏", symbol:"music.note.list", color:.orange) }.buttonStyle(.plain)
                NavigationLink { SearchView() } label: { FeatureRow(title:"搜索", subtitle:"歌曲与歌手", symbol:"magnifyingglass", color:.purple) }.buttonStyle(.plain)
                if player.song != nil {
                    Button { player.showPlayer = true } label: { FeatureRow(title:"正在播放", subtitle:player.song?.name ?? "", symbol:"waveform", color:.pink) }.buttonStyle(.plain)
                }
                if !store.libraryErrors.isEmpty {
                    ForEach(store.libraryErrors,id:\.self) { Text($0).font(.caption2).foregroundStyle(.orange) }
                }
                Button { Task { await store.refreshLibrary() } } label: { Label(store.loading ? "加载中…" : "刷新资料库",systemImage:"arrow.clockwise") }.disabled(store.loading)
                NavigationLink { SettingsView() } label: { Label("设置",systemImage:"gearshape") }
            }.padding(.horizontal,5)
        }.navigationTitle("云音乐").navigationBarTitleDisplayMode(.inline)
    }
}
struct FeatureRow: View {
    let title: String; let subtitle: String; let symbol: String; let color: Color
    var body: some View { HStack(spacing:10) { Image(systemName:symbol).font(.title3).foregroundStyle(color).frame(width:28); VStack(alignment:.leading,spacing:3) { Text(title).font(.system(size:15,weight:.semibold)); Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }; Spacer(minLength:0); Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.tertiary) }.padding(11).background(.white.opacity(0.075),in:RoundedRectangle(cornerRadius:15)) }
}
struct PlaylistsView: View {
    @EnvironmentObject var store: MusicStore
    @State private var collected = false
    var lists: [Playlist] { collected ? store.collected : store.created }
    var body: some View {
        List {
            Picker("歌单", selection:$collected) { Text("我创建的").tag(false); Text("我收藏的").tag(true) }.pickerStyle(.navigationLink)
            if lists.isEmpty { Text(store.loading ? "正在加载…" : "还没有歌单").foregroundStyle(.secondary) }
            ForEach(lists) { p in NavigationLink { SongListView(title:p.name,source:.playlist(p)) } label: { HStack { Artwork(url:p.artwork); VStack(alignment:.leading,spacing:3) { Text(p.name).font(.system(size:14,weight:.medium)).lineLimit(2); Text("\(p.trackCount ?? 0) 首歌曲").font(.caption2).foregroundStyle(.secondary) } }.padding(.vertical,3) } }
            if collected ? store.collectedMore : store.createdMore { Button("加载更多") { Task { await store.morePlaylists(collected:collected) } }.disabled(store.loading) }
        }.navigationTitle("我的歌单")
    }
}
enum SongSource { case daily, playlist(Playlist) }
struct SongListView: View {
    let title: String; let source: SongSource
    @EnvironmentObject var store: MusicStore
    @EnvironmentObject var player: AudioPlayer
    @State private var tracks: [Song] = []
    @State private var nextOffset = 0
    @State private var total = 0
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        List {
            if let first = tracks.first(where:\.playable) {
                HStack {
                    Button { player.start(tracks,selected:first,api:store.api) } label: { Label("播放",systemImage:"play.fill").font(.caption) }
                    Button { player.start(tracks,selected:first,api:store.api,shuffle:true) } label: { Image(systemName:"shuffle") }.accessibilityLabel("随机播放")
                }.listRowBackground(Color.clear)
                Text("\(tracks.count)\(total > tracks.count ? " / \(total)" : "") 首 · 播放已加载歌曲").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(tracks) { song in Button { player.start(tracks,selected:song,api:store.api) } label: { SongRow(song:song,current:player.song?.id == song.id) }.buttonStyle(.plain).disabled(!song.playable) }
            if busy { HStack { Spacer(); ProgressView(); Spacer() } }
            if let message { Text(message).font(.caption2).foregroundStyle(.orange); Button("重试") { Task { await load(reset:tracks.isEmpty) } } }
            if !busy && tracks.isEmpty && message == nil { Text("这里还没有歌曲").foregroundStyle(.secondary) }
            if nextOffset < total && !busy { Button("加载更多歌曲") { Task { await load() } } }
        }.navigationTitle(title).task { if tracks.isEmpty { await load(reset:true) } }
    }
    func load(reset: Bool = false) async {
        guard let api = store.api, !busy else { return }; busy = true; message = nil; defer { busy = false }
        do {
            switch source {
            case .daily: tracks = store.daily.isEmpty ? try await api.daily() : store.daily; total = tracks.count; nextOffset = total
            case .playlist(let p):
                let page = try await api.tracks(p.id,offset:reset ? 0 : nextOffset)
                if reset { tracks = [] }
                tracks += page.records.filter { song in !tracks.contains { $0.id == song.id } }
                nextOffset = page.nextOffset ?? (nextOffset + page.records.count)
                total = page.recordCount ?? nextOffset
            }
        } catch { message = error.localizedDescription }
    }
}
struct SongRow: View {
    let song: Song; var current = false
    var body: some View { HStack(spacing:9) { Artwork(url:song.artwork,size:38); VStack(alignment:.leading,spacing:3) { Text(song.name).font(.system(size:14,weight:.medium)).foregroundStyle(current ? accent : .white).lineLimit(2); Text(song.playable ? song.artist : "暂不可播放 · \(song.artist)").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }; Spacer(minLength:0); if current { Image(systemName:"waveform").foregroundStyle(accent).font(.caption) } }.opacity(song.playable ? 1 : 0.5).padding(.vertical,4).frame(minHeight:44) }
}
struct SearchView: View {
    @EnvironmentObject var store: MusicStore
    @EnvironmentObject var player: AudioPlayer
    @State private var query = ""
    @State private var searched = ""
    @State private var results: [Song] = []
    @State private var total = 0
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        List {
            TextField("歌曲或歌手",text:$query).submitLabel(.search).onSubmit { Task { await search(reset:true) } }
            Button("搜索") { Task { await search(reset:true) } }.disabled(busy || query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            if busy { ProgressView() }
            if let message { Text(message).font(.caption2).foregroundStyle(.orange) }
            ForEach(results) { song in Button { player.start(results,selected:song,api:store.api) } label: { SongRow(song:song) }.buttonStyle(.plain).disabled(!song.playable) }
            if !busy && results.isEmpty && !searched.isEmpty && message == nil { Text("没有找到相关歌曲").foregroundStyle(.secondary) }
            if results.count < total { Button("加载更多") { Task { await search(reset:false) } }.disabled(busy) }
        }.navigationTitle("搜索")
    }
    func search(reset: Bool) async {
        guard let api = store.api, !busy else { return }; busy = true; message = nil; defer { busy = false }
        if reset { searched = query.trimmingCharacters(in:.whitespacesAndNewlines); results = [] }
        do { let page = try await api.search(searched,offset:results.count); results += page.records.filter { song in !results.contains { $0.id == song.id } }; total = page.records.isEmpty ? results.count : (page.recordCount ?? results.count) } catch { message = error.localizedDescription }
    }
}
struct PlayerView: View {
    @EnvironmentObject var player: AudioPlayer
    @State private var seekValue = 0.0
    @State private var editing = false
    var body: some View {
        TabView {
            ScrollView {
                VStack(spacing:7) {
                    Artwork(url:player.song?.artwork,size:72)
                    Text(player.song?.name ?? "尚未播放").font(.system(size:16,weight:.semibold)).lineLimit(1).multilineTextAlignment(.center)
                    Text(player.song?.artist ?? "选择喜欢的歌曲").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    if player.isTrial { Text("试听片段").font(.caption2).foregroundStyle(.orange) }
                    if let error = player.error { Text(error).font(.caption2).foregroundStyle(.orange); Button("重试播放") { player.retry() } }
                    HStack(spacing:19) {
                        Button { player.previous() } label: { Image(systemName:"backward.end.fill").font(.title3) }.accessibilityLabel("上一首")
                        Button { player.toggle() } label: { ZStack { Circle().fill(.white).frame(width:47,height:47); if player.buffering { ProgressView().tint(.black) } else { Image(systemName:player.playing ? "pause.fill" : "play.fill").font(.title2).foregroundStyle(.black) } } }.accessibilityLabel(player.playing ? "暂停" : "播放")
                        Button { player.next() } label: { Image(systemName:"forward.end.fill").font(.title3) }.accessibilityLabel("下一首")
                    }.buttonStyle(.plain).frame(minHeight:48).disabled(player.song == nil)
                    if player.duration > 0 {
                        Slider(value:Binding(get:{ editing ? seekValue : player.position },set:{ seekValue = $0 }),in:0...max(1,player.duration),onEditingChanged:{ editing = $0; if !$0 { player.seek(seekValue) } }).tint(accent).accessibilityLabel("播放进度")
                        HStack { Text(time(player.position)); Spacer(); Text(time(player.duration)) }.font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button { player.repeatAll.toggle() } label: { Image(systemName:"repeat").foregroundStyle(player.repeatAll ? accent : .secondary) }.accessibilityLabel(player.repeatAll ? "关闭列表循环" : "列表循环")
                        Spacer()
                        Text("左滑查看队列").font(.system(size:9)).foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }.padding(.horizontal,5)
            }.tag(0)
            List { Section("待播清单") { ForEach(player.queue.songs) { song in Button { player.select(song) } label: { SongRow(song:song,current:player.song?.id == song.id) }.buttonStyle(.plain) } }; Button("停止播放",role:.destructive) { player.stop() } }.tag(1)
        }.tabViewStyle(.page).navigationTitle("正在播放").navigationBarTitleDisplayMode(.inline)
    }
    private func time(_ t: Double) -> String { let value = t.isFinite ? max(0,Int(t)) : 0; return "\(value/60):" + String(format:"%02d",value%60) }
}
struct WelcomeView: View {
    @EnvironmentObject var store: MusicStore
    var body: some View {
        ScrollView { VStack(spacing:14) {
            Image(systemName:"music.note").font(.system(size:42,weight:.bold)).foregroundStyle(accent)
            Text("音乐，随腕而行").font(.title3.bold())
            Text("每日推荐、你的歌单\n直接在 Apple Watch 聆听").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if store.api != nil { NavigationLink("登录网易云音乐") { LoginView() }.buttonStyle(.borderedProminent) }
            NavigationLink("设置") { SettingsView() }
            Text("个人开发版 · 非官方客户端").font(.system(size:10)).foregroundStyle(.tertiary)
        }.padding(.top,12) }.navigationTitle("云音乐")
    }
}
struct LoginView: View {
    @EnvironmentObject var store: MusicStore
    var body: some View {
        ScrollView { VStack(spacing:10) {
            if let code = store.qr, let matrix = LoginQRCode.matrix(code.qrCodeUrl) {
                Canvas { context,size in
                    let count = matrix.count+8, cell = min(size.width,size.height)/CGFloat(count)
                    context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(.white))
                    for y in matrix.indices { for x in matrix[y].indices where matrix[y][x] { context.fill(Path(CGRect(x:CGFloat(x+4)*cell,y:CGFloat(y+4)*cell,width:cell+0.1,height:cell+0.1)),with:.color(.black)) } }
                }.frame(width:155,height:155).accessibilityLabel("网易云音乐登录二维码")
            } else { Image(systemName:"qrcode").font(.system(size:55)).foregroundStyle(accent) }
            Text(store.loginMessage).font(.caption).multilineTextAlignment(.center)
            Button("重新生成") { store.login() }
        } }.navigationTitle("扫码登录").task { store.login() }.onDisappear { store.cancelLogin() }
    }
}
struct SettingsView: View {
    @EnvironmentObject var store: MusicStore
    @EnvironmentObject var player: AudioPlayer
    @State private var confirmLogout = false
    var body: some View {
        Form {
            Section("播放") {
                Toggle("允许蜂窝网络",isOn:$player.cellularPlayback)
                Toggle("较高音质",isOn:$player.highQuality)
                Text("默认使用标准音质，较高音质请求极高音质。实际格式与码率取决于账号权限及服务器返回。设置从下一首歌曲生效。").font(.caption2).foregroundStyle(.secondary)
            }
            Section("账号") {
                Text(store.nickname).font(.caption)
                if store.api != nil { NavigationLink("重新扫码登录") { LoginView() } }
                if store.ready { Button("退出登录",role:.destructive) { confirmLogout = true } }
            }
            Section { Text("云音乐 · Watch\n个人开发版 1.0\n非网易官方应用").font(.caption2).foregroundStyle(.secondary) }
        }.navigationTitle("设置").confirmationDialog("退出并清除本机凭据？",isPresented:$confirmLogout,titleVisibility:.visible) { Button("退出登录",role:.destructive) { player.stop(); store.logout() } }
    }
}
