import Foundation
import CommonCrypto
import CryptoKit
import zlib

/// The desktop client's wire format; these constants are protocol constants, not account secrets.
public enum EAPICodec {
    private static let key = Data("e82ckenh8dichen8".utf8)
    static func crypt(_ data: Data, operation: CCOperation) throws -> Data {
        var output = Data(count: data.count + kCCBlockSizeAES128)
        let capacity = output.count
        var written = 0
        let status = output.withUnsafeMutableBytes { out in data.withUnsafeBytes { bytes in key.withUnsafeBytes { key in
            CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding), key.baseAddress, kCCKeySizeAES128, nil, bytes.baseAddress, data.count, out.baseAddress, capacity, &written)
        } } }
        guard status == kCCSuccess else { throw MusicError.message("无法解析客户端接口响应。") }
        output.count = written
        return output
    }
    static func json(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }
    static func encode(path: String, parameters: [String: Any]) throws -> Data {
        let text = try json(parameters)
        let signedPath = "/api/" + path.dropFirst("/eapi/".count)
        let message = Data("nobody\(signedPath)use\(text)md5forencrypt".utf8)
        let digest = Insecure.MD5.hash(data: message).map { String(format: "%02x", $0) }.joined()
        let plain = Data("\(signedPath)-36cd479b6b5-\(text)-36cd479b6b5-\(digest)".utf8)
        let hex = try crypt(plain, operation: CCOperation(kCCEncrypt)).map { String(format: "%02X", $0) }.joined()
        return Data("params=\(hex)".utf8)
    }
    static func decode(_ data: Data) throws -> [String: Any] {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return json }
        var plain = try crypt(data, operation: CCOperation(kCCDecrypt))
        if plain.starts(with: [0x1f, 0x8b]) { plain = try gunzip(plain) }
        guard let json = try JSONSerialization.jsonObject(with: plain) as? [String: Any] else { throw MusicError.message("接口返回格式不正确。") }
        return json
    }
    private static func gunzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw MusicError.message("无法解压响应。") }
        defer { inflateEnd(&stream) }
        return try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = uInt(data.count)
            var result = Data()
            var status: Int32 = Z_OK
            repeat {
                var chunk = [UInt8](repeating: 0, count: 32768)
                status = chunk.withUnsafeMutableBytes { out in
                    stream.next_out = out.bindMemory(to: UInt8.self).baseAddress
                    stream.avail_out = uInt(out.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                guard status == Z_OK || status == Z_STREAM_END else { throw MusicError.message("响应解压失败。") }
                result.append(contentsOf: chunk.prefix(32768 - Int(stream.avail_out)))
                guard result.count <= 32 * 1024 * 1024 else { throw MusicError.message("接口响应过大。") }
            } while status != Z_STREAM_END
            return result
        }
    }
}

public struct SessionCookie: Codable, Sendable {
    public var name: String
    public var value: String
    public var domain: String
    public var path: String
    public var secure: Bool
    public var expiresAt: Double?
    init(_ cookie: HTTPCookie) {
        name = cookie.name; value = cookie.value; domain = cookie.domain; path = cookie.path
        secure = cookie.isSecure; expiresAt = cookie.expiresDate?.timeIntervalSince1970
    }
    var cookie: HTTPCookie? {
        var p: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path, .secure: secure ? "TRUE" : "FALSE"]
        if let expiresAt { p[.expires] = Date(timeIntervalSince1970: expiresAt) }
        return HTTPCookie(properties: p)
    }
}
public struct AccountConfiguration: Codable, Sendable {
    public var deviceId: String
    public var cookies: [SessionCookie]
    public var userId: String?
    public init(deviceId: String = UUID().uuidString, cookies: [SessionCookie] = [], userId: String? = nil) {
        self.deviceId = deviceId; self.cookies = cookies; self.userId = userId
    }
    public var loggedIn: Bool { cookies.contains { $0.name == "MUSIC_U" && !$0.value.isEmpty && ($0.expiresAt == nil || $0.expiresAt! > Date().timeIntervalSince1970) } }
}
