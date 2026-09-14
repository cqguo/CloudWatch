import XCTest
@testable import CloudWatchCore
import Security

final class CoreTests: XCTestCase {
    private func song(_ id: String, playable: Bool = true) throws -> Song {
        try JSONDecoder().decode(Song.self,from:Data("{\"id\":\"\(id)\",\"name\":\"歌曲\",\"artists\":[{\"name\":\"歌手\"}],\"playFlag\":\(playable)}".utf8))
    }
    func testQueueSkipsUnavailableAndDoesNotWrapUnlessEnabled() throws {
        var q = PlayQueue(); let a = try song("a"), b = try song("b",playable:false), c = try song("c")
        q.replace([a,b,c],startingAt:"a"); XCTAssertEqual(q.songs.count,2)
        XCTAssertTrue(q.advance()); XCTAssertEqual(q.current?.id,"c")
        XCTAssertFalse(q.advance()); XCTAssertEqual(q.current?.id,"c")
        XCTAssertTrue(q.advance(repeatAll:true)); XCTAssertEqual(q.current?.id,"a")
        XCTAssertFalse(q.previous())
        q.replace([],startingAt:"missing"); XCTAssertNil(q.current); XCTAssertFalse(q.advance(repeatAll:true))
    }
    func testPaginationAndLargeIDs() throws {
        let data = Data("{\"recordCount\":100,\"records\":[{\"id\":\"ENC\",\"originalId\":7856572369,\"name\":\"歌单歌曲\",\"coverImgUrl\":null}]}".utf8)
        let p = try JSONDecoder().decode(Page<Song>.self,from:data)
        XCTAssertEqual(p.records[0].originalId,7856572369); XCTAssertNil(p.records[0].artwork)
        XCTAssertEqual(secureArtwork("http://p1.music.126.net/image.jpg")?.scheme,"https")
    }
    func testQRCodeStructureAndCapacity() {
        let q = LoginQRCode.matrix("https://163cn.tv/example")!
        XCTAssertEqual(q.count,37); XCTAssertTrue(q.allSatisfy { $0.count == 37 })
        XCTAssertTrue(q[0][0]); XCTAssertFalse(q[1][1]); XCTAssertTrue(q[3][3]); XCTAssertFalse(q[7][7])
        XCTAssertNil(LoginQRCode.matrix(String(repeating:"x",count:107)))
    }
}
