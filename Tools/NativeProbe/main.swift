import Foundation
import CloudWatchCore

@main struct NativeProbe {
    static func main() async {
        do { try await run() } catch { print("FAILED: \(error)"); exit(1) }
    }
    static func run() async throws {
        if CommandLine.arguments.contains("--login") {
            let api = DesktopAPI(persist:false)
            let qr = try await api.beginLogin()
            guard let matrix = LoginQRCode.matrix(qr.qrCodeUrl) else { throw MusicError.message("QR exceeds capacity") }
            let size = matrix.count + 8
            var svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(size) \(size)\" width=\"360\" height=\"360\"><rect width=\"100%\" height=\"100%\" fill=\"white\"/>"
            for y in matrix.indices { for x in matrix[y].indices where matrix[y][x] { svg += "<rect x=\"\(x+4)\" y=\"\(y+4)\" width=\"1\" height=\"1\"/>" } }
            svg += "</svg>"
            try svg.write(toFile:"/tmp/cloudwatch-proxyman-private/watch-login.svg",atomically:true,encoding:.utf8)
            print("QR_READY", terminator:"\n"); fflush(stdout)
            for _ in 0..<100 {
                try await Task.sleep(for:.seconds(3))
                let state = try await api.pollLogin(key:qr.uniKey)
                switch state {
                case .waiting: continue
                case .scanned: print("SCANNED"); fflush(stdout)
                case .expired: throw MusicError.message("QR expired")
                case .authorized:
                    try JSONEncoder().encode(await api.configuration).write(to:URL(fileURLWithPath:"/tmp/cloudwatch-proxyman-private/watch-session.json"),options:.atomic)
                    print("LOGIN_OK"); return
                }
            }
            throw MusicError.message("Login timed out")
        }
        guard CommandLine.arguments.count > 1 else { fatalError("Usage: NativeProbe /private/path/provisioning.json") }
        let url = URL(fileURLWithPath:CommandLine.arguments[1])
        let config = try JSONDecoder().decode(AccountConfiguration.self,from:Data(contentsOf:url))
        let api = DesktopAPI(configuration:config,persist:false)
        try await api.refresh(); print("session refresh: OK")
        let profile = try await api.profile(); print("profile: OK (name present: \(profile.nickname != nil))")
        let daily = try await api.daily(); print("daily: \(daily.count) songs")
        let created = try await api.playlists(collected:false); print("created: \(created.records.count) playlists")
        let collected = try await api.playlists(collected:true); print("collected: \(collected.records.count) playlists")
        let favorite = try await api.favorite(); print("favorite: OK")
        let tracks = try await api.tracks(favorite.id); print("favorite tracks: \(tracks.records.count) of \(tracks.recordCount ?? 0)")
        let nextTracks = try await api.tracks(favorite.id,offset:tracks.nextOffset ?? tracks.records.count)
        print("favorite page 2: \(nextTracks.records.count) songs")
        let search = try await api.search("许巍 蓝莲花"); print("search: \(search.records.count) songs")
        guard let song = search.records.first(where: \.playable) else { throw MusicError.message("No playable test song") }
        let resource = try await api.audio(song)
        guard let text = resource.playUrl, let audioURL = URL(string:text) else { throw MusicError.message("No audio URL") }
        var r = URLRequest(url:audioURL); r.setValue("bytes=0-4095",forHTTPHeaderField:"Range")
        let (bytes,response) = try await URLSession.shared.data(for:r)
        guard let http = response as? HTTPURLResponse, [200,206].contains(http.statusCode), !bytes.isEmpty else { throw MusicError.message("Audio unreachable") }
        print("audio: HTTP \(http.statusCode), \(bytes.count) bytes, host \(audioURL.host ?? "")")
        var results: [[String:Any]] = []
        for (id,name) in [("3388509025","12.31"),("187672","烦恼歌"),("2686502900","おしんこ"),("2141412509","Dear Alcohol (Mega Remix)"),("3433814098","オリオン (PSYQUI Remix)")] {
            let data = try JSONSerialization.data(withJSONObject:["id":id,"name":name])
            let song = try JSONDecoder().decode(Song.self,from:data)
            let resource = try await api.audio(song)
            results.append(["song":name,"hasAudioURL":resource.playUrl != nil,"isTrial":resource.freeTrailFlag == true,"bitrate":resource.br ?? 0])
        }
        try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:"build/eapi-five-song-validation.json"))
        print("Five original songs: audio URLs returned. All native desktop API checks passed.")
    }
}
