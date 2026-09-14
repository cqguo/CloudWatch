#if DEBUG
import Foundation
import SwiftUI
import AVFoundation

/// Diagnostic only: bypass both list and detail flags without changing normal playback policy.
@MainActor private func verifyFlaggedAudio(api: DesktopAPI) async {
    let output = URL.documentsDirectory.appending(path: "flagged-audio-verification.json")
    var report: [String: Any] = ["complete": false, "environment": "watchOS simulator"]
    var results: [[String: Any]] = []
    func save() {
        report["results"] = results
        try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
    }
    save()
    do {
        let songs = try await api.daily()
        let selectedIDs: Set<String> = ["3388509025", "187672", "2686502900", "2141412509", "3433814098"]
        let flagged = Array(songs.filter { selectedIDs.contains($0.id) })
        report["dailyCount"] = songs.count
        report["flaggedCount"] = songs.filter { $0.playFlag == false }.count
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            audio.activate(options: []) { ok, error in
                if let error { c.resume(throwing: error) }
                else if ok { c.resume() }
                else { c.resume(throwing: MusicError.message("Audio route activation failed")) }
            }
        }
        // Include one normally playable control using the same audio route and network.
        for song in flagged + Array(songs.filter { $0.name == "踊り子" }.prefix(1)) {
            var row: [String: Any] = ["song": song.name, "artist": song.artist, "listPlayFlag": song.playFlag as Any? ?? NSNull(), "passed": false]
            let player = AVPlayer()
            player.isMuted = true
            do {
                let resource = try await api.audio(song)
                row["detailPlayFlag"] = resource.playFlag as Any? ?? NSNull()
                row["freeTrailFlag"] = resource.freeTrailFlag as Any? ?? NSNull()
                row["hasURL"] = !(resource.playUrl ?? "").isEmpty
                guard let text = resource.playUrl, let url = URL(string: text), ["http", "https"].contains(url.scheme ?? "") else {
                    throw MusicError.message("No audio URL returned")
                }
                let item = AVPlayerItem(url: url)
                player.replaceCurrentItem(with: item)
                player.play()
                let deadline = Date().addingTimeInterval(30)
                while Date() < deadline {
                    try await Task.sleep(for: .milliseconds(500))
                    if item.status == .failed {
                        let e = item.error as NSError?
                        throw MusicError.message("AVPlayer failed: \(e?.domain ?? "unknown") / \(e?.code ?? 0)")
                    }
                    let position = player.currentTime().seconds
                    if player.timeControlStatus == .playing && position.isFinite && position >= 3 {
                        row["passed"] = true
                        row["position"] = position
                        if item.duration.seconds.isFinite { row["duration"] = item.duration.seconds }
                        break
                    }
                }
                if row["passed"] as? Bool != true { row["error"] = "No advancing playback within 30 seconds" }
            } catch {
                row["error"] = error.localizedDescription
            }
            player.pause()
            player.replaceCurrentItem(with: nil)
            results.append(row)
            save()
        }
    } catch { report["error"] = error.localizedDescription }
    report["complete"] = true
    save()
}
extension AudioPlayer {
    /// Explicit launch-argument smoke test, never active in Release.
    func verifyOnSimulator(api: DesktopAPI) async {
        var report: [String:Any] = [:]
        do {
            let page = try await api.search("许巍 蓝莲花")
            guard let song = page.records.first(where:\.playable) else { throw MusicError.message("No playable test song") }
            report["song"] = song.name
            start([song],selected:song,api:api)
            let deadline = Date().addingTimeInterval(45)
            while Date() < deadline {
                try await Task.sleep(for:.seconds(1))
                if let error { throw MusicError.message(error) }
                if playing && position >= 3 { report["passed"] = true; report["position"] = position; report["duration"] = duration; break }
            }
            if report["passed"] == nil { report["passed"] = false; report["error"] = "No advancing audio within 45 seconds; simulator audio route may be unavailable." }
        } catch { report["passed"] = false; report["error"] = error.localizedDescription }
        stop()
        let destination = URL.documentsDirectory.appending(path:"audio-verification.json")
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:destination)
    }
}
struct DebugScreenModifier: ViewModifier {
    @EnvironmentObject var store: MusicStore
    @EnvironmentObject var player: AudioPlayer
    @State private var performed = false
    func body(content: Content) -> some View {
        content.task {
            guard !performed, CommandLine.arguments.contains("--verify-audio") || CommandLine.arguments.contains("--verify-flagged-audio") || CommandLine.arguments.contains("--verify-session") else { return }
            performed = true
            guard let api = store.api else { return }
            if CommandLine.arguments.contains("--verify-session") {
                var result: [String:Any] = ["keychainSession":KeychainStore.load()?.loggedIn == true,"passed":false]
                do {
                    let profile = try await api.profile()
                    result["profileLoaded"] = profile.nickname != nil
                    result["dailyCount"] = try await api.daily().count
                    result["passed"] = true
                } catch { result["error"] = error.localizedDescription }
                result["temporaryImportRemoved"] = !FileManager.default.fileExists(atPath:URL.documentsDirectory.appending(path:"provisioning.json").path)
                try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:URL.documentsDirectory.appending(path:"session-verification.json"))
            }
            else if CommandLine.arguments.contains("--verify-flagged-audio") { await verifyFlaggedAudio(api: api) }
            else { await player.verifyOnSimulator(api:api) }
        }
    }
}
#endif
