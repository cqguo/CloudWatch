import SwiftUI
import AVFoundation
import MediaPlayer

@MainActor final class AudioPlayer: ObservableObject {
    @Published var queue = PlayQueue()
    @Published var playing = false
    @Published var buffering = false
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var error: String?
    @Published var isTrial = false
    @Published var repeatAll = false
    @Published var shuffled = false
    @Published var showPlayer = false
    @AppStorage("cellularPlayback") var cellularPlayback = true
    @AppStorage("highQuality") var highQuality = false
    private let player = AVPlayer()
    private var periodic: Any?
    private var status: NSKeyValueObservation?
    private var control: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var interruption: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?
    private var api: DesktopAPI?
    private var generation = UUID()
    var song: Song? { queue.current }
    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        periodic = player.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.5, preferredTimescale:600), queue:.main) { [weak self] t in
            Task { @MainActor in guard let self else { return }; self.position = max(0,t.seconds.isFinite ? t.seconds : 0); let d = self.player.currentItem?.duration.seconds ?? 0; self.duration = d.isFinite ? d : 0; self.updateNowPlaying() }
        }
        control = player.observe(\.timeControlStatus, options:[.new]) { [weak self] p, _ in
            let state = p.timeControlStatus
            Task { @MainActor in self?.playing = state == .playing; self?.buffering = state == .waitingToPlayAtSpecifiedRate }
        }
        endObserver = NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime, object:nil, queue:.main) { [weak self] n in
            Task { @MainActor in guard let self, let item = n.object as? AVPlayerItem, item === self.player.currentItem else { return }; self.next(automatic:true) }
        }
        failObserver = NotificationCenter.default.addObserver(forName:.AVPlayerItemFailedToPlayToEndTime, object:nil, queue:.main) { [weak self] n in
            Task { @MainActor in guard let self, let item = n.object as? AVPlayerItem, item === self.player.currentItem else { return }; self.error = "播放中断，请检查网络后重试。"; self.playing = false; self.buffering = false }
        }
        interruption = NotificationCenter.default.addObserver(forName:AVAudioSession.interruptionNotification, object:nil, queue:.main) { [weak self] _ in Task { @MainActor in self?.playing = false } }
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(e.positionTime) }; return .success
        }
    }
    func start(_ songs: [Song], selected: Song, api: DesktopAPI?, shuffle: Bool = false) {
        guard selected.playable else { error = "该歌曲当前没有播放权限。"; return }
        self.api = api; shuffled = shuffle
        let list = shuffle ? songs.shuffled() : songs
        queue.replace(list, startingAt:shuffle ? (list.first(where: \.playable)?.id ?? selected.id) : selected.id)
        showPlayer = true; loadCurrent()
    }
    private func loadCurrent() {
        guard let api, let song else { error = "请先登录并选择歌曲。"; return }
        loadTask?.cancel(); generation = UUID(); let id = generation
        player.pause(); player.replaceCurrentItem(with:nil); buffering = true; error = nil; position = 0; duration = 0; isTrial = false
        loadTask = Task {
            do {
                let audio = AVAudioSession.sharedInstance()
                try audio.setCategory(.playback, mode:.default, policy:.longFormAudio)
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                    audio.activate(options:[]) { ok, error in if let error { c.resume(throwing:error) } else if ok { c.resume() } else { c.resume(throwing:MusicError.message("请连接蓝牙耳机或选择音频输出。")) } }
                }
                let resource = try await api.audio(song, bitrate:highQuality ? 320 : 128)
                try Task.checkCancellation(); guard id == generation else { return }
                guard resource.playFlag != false, let string = resource.playUrl, let url = URL(string:string), ["https","http"].contains(url.scheme ?? "") else { throw MusicError.message("该歌曲暂无可用音源，请试试其他歌曲。") }
                isTrial = resource.freeTrailFlag == true
                let asset = AVURLAsset(url:url, options:[AVURLAssetAllowsCellularAccessKey:cellularPlayback, AVURLAssetAllowsExpensiveNetworkAccessKey:cellularPlayback, AVURLAssetAllowsConstrainedNetworkAccessKey:true])
                let item = AVPlayerItem(asset:asset); item.preferredForwardBufferDuration = 8
                status = item.observe(\.status, options:[.new]) { [weak self] item, _ in
                    let failed = item.status == .failed
                    Task { @MainActor in guard let self, id == self.generation, failed else { return }; self.error = "音频加载失败，请检查网络、播放权限和耳机连接后重试。"; self.buffering = false; self.playing = false }
                }
                player.replaceCurrentItem(with:item); player.play(); updateNowPlaying()
            } catch is CancellationError { } catch { if id == generation { self.error = error.localizedDescription; buffering = false; playing = false } }
        }
    }
    func retry() { loadCurrent() }
    func toggle() { if playing || buffering { pause() } else { resume() } }
    func pause() { if player.currentItem == nil { generation = UUID(); loadTask?.cancel() }; player.pause(); playing = false; buffering = false; updateNowPlaying() }
    func resume() { if player.currentItem == nil || player.currentItem?.status == .failed { loadCurrent() } else { player.play() } }
    func next(automatic: Bool = false) { if queue.advance(repeatAll:repeatAll) { loadCurrent() } else if automatic { pause(); position = duration } }
    func previous() { if position > 3 { seek(0) } else if queue.previous() { loadCurrent() } }
    func select(_ song: Song) { queue.select(song.id); loadCurrent() }
    func seek(_ seconds: Double) { player.seek(to:CMTime(seconds:max(0,min(seconds,duration)), preferredTimescale:600)) }
    func stop() { showPlayer = false; generation = UUID(); loadTask?.cancel(); player.pause(); player.replaceCurrentItem(with:nil); queue = PlayQueue(); playing = false; buffering = false; position = 0; duration = 0; MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
    private func updateNowPlaying() {
        guard let song else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle:song.name, MPMediaItemPropertyArtist:song.artist, MPMediaItemPropertyPlaybackDuration:duration, MPNowPlayingInfoPropertyElapsedPlaybackTime:position, MPNowPlayingInfoPropertyPlaybackRate:playing ? 1.0 : 0.0]
    }
}
