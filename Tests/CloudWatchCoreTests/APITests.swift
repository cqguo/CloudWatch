import XCTest
@testable import CloudWatchCore
import CommonCrypto

private final class MockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> [String: Any])!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try JSONSerialization.data(withJSONObject: Self.handler(request))
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self,didFailWithError:error) }
    }
    override func stopLoading() {}
}
final class APITests: XCTestCase {
    private func api(authenticated: Bool = true) -> DesktopAPI {
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [MockProtocol.self]
        var config = AccountConfiguration()
        if authenticated { config.cookies = [SessionCookie(HTTPCookie(properties:[.name:"MUSIC_U",.value:"test-session",.domain:".music.163.com",.path:"/",.secure:"TRUE"])!)] }
        return DesktopAPI(configuration:config,session:URLSession(configuration:c),persist:false)
    }
    override func tearDown() { MockProtocol.handler = nil }
    func testDesktopSearchMappingAndLargeID() async throws {
        MockProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod,"POST")
            XCTAssertEqual(req.url?.path,"/eapi/search/song/list/page")
            XCTAssertEqual(req.url?.host,"interface.music.163.com")
            XCTAssertTrue(req.value(forHTTPHeaderField:"Cookie")?.contains("MUSIC_U=test-session") == true)
            return ["code":200,"data":["totalCount":50,"resources":[["baseInfo":["simpleSongData":["id":7856572369,"name":"Track","ar":[["name":"Artist"]],"al":["picUrl":"https://p1.music.126.net/test"],"dt":205531]]]]]]
        }
        let p = try await api().search("test")
        XCTAssertEqual(p.records.first?.id,"7856572369"); XCTAssertEqual(p.records.first?.artist,"Artist")
        XCTAssertEqual(p.records.first?.duration,205.531); XCTAssertEqual(p.recordCount,50)
    }
    func testQRStateMachineAndURL() async throws {
        var state = 801
        MockProtocol.handler = { req in
            if req.url?.path == "/eapi/login/qrcode/unikey" { return ["code":200,"unikey":"test-key"] }
            return ["code":state]
        }
        let service = api(authenticated:false)
        let qr = try await service.beginLogin()
        XCTAssertEqual(qr.qrCodeUrl,"https://music.163.com/login?codekey=test-key")
        XCTAssertNotNil(LoginQRCode.matrix(qr.qrCodeUrl))
        let waiting = try await service.pollLogin(key:qr.uniKey); if case .waiting = waiting {} else { XCTFail() }
        state = 802
        let scanned = try await service.pollLogin(key:qr.uniKey); if case .scanned = scanned {} else { XCTFail() }
        state = 800
        let expired = try await service.pollLogin(key:qr.uniKey); if case .expired = expired {} else { XCTFail() }
    }
    func testUnauthorizedDoesNotPretendToBeEmptyLibrary() async throws {
        MockProtocol.handler = { _ in ["code":301] }
        do { _ = try await api().daily(); XCTFail() } catch { XCTAssertTrue(error.localizedDescription.contains("登录已失效")) }
    }
    func testAudioTrialAndDenial() async throws {
        let song = try DesktopAPI.song(["id":187672,"name":"Track"])
        MockProtocol.handler = { req in
            XCTAssertEqual(req.url?.path,"/eapi/song/enhance/player/url/v1")
            return ["code":200,"data":[["id":187672,"code":200,"url":"https://m701.music.126.net/test.m4a","br":96000,"freeTrialInfo":["start":0,"end":30]]]]
        }
        let r = try await api().audio(song); XCTAssertEqual(r.freeTrailFlag,true)
        MockProtocol.handler = { _ in ["code":200,"data":[["id":187672,"code":404,"url":NSNull()]]] }
        do { _ = try await api().audio(song); XCTFail() } catch { XCTAssertTrue(error.localizedDescription.contains("可用音源")) }
    }
    func testPlaylistTrackOrderAndPagination() async throws {
        MockProtocol.handler = { req in
            if req.url?.path == "/eapi/v6/playlist/detail" { return ["code":200,"playlist":["trackIds":(1...32).map { ["id":$0] }]] }
            return ["code":200,"songs":[["id":32,"name":"last"],["id":31,"name":"first"]]]
        }
        let p = try await api().tracks("123",offset:30)
        XCTAssertEqual(p.recordCount,32); XCTAssertEqual(p.records.map(\.id),["31","32"])
    }
    func testCookiesRoundTripPreservesScopeAndExpiration() throws {
        let c = HTTPCookie(properties:[.name:"MUSIC_U",.value:"test",.domain:".music.163.com",.path:"/eapi",.secure:"TRUE",.expires:Date(timeIntervalSince1970:2000000000)])!
        let saved = try JSONDecoder().decode(SessionCookie.self,from:JSONEncoder().encode(SessionCookie(c)))
        XCTAssertEqual(saved.cookie?.domain,c.domain); XCTAssertEqual(saved.cookie?.path,c.path)
        XCTAssertEqual(saved.cookie?.expiresDate,c.expiresDate); XCTAssertEqual(saved.cookie?.isSecure,true)
    }
    func testEncryptedResponseAndInvalidCiphertext() throws {
        let original = Data("{\"code\":200,\"data\":{\"ok\":true}}".utf8)
        let encrypted = try EAPICodec.crypt(original,operation:CCOperation(kCCEncrypt))
        XCTAssertEqual(try EAPICodec.decode(encrypted)["code"] as? Int,200)
        XCTAssertThrowsError(try EAPICodec.decode(Data([0,1,2])))
    }
}
