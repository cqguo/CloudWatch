import Foundation
#if canImport(CBrowserJS)
import CBrowserJS
#endif
#if canImport(SwiftSoup)
import SwiftSoup
#endif

struct BrowserFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private enum BrowserHTML {
    static func tree(_ node: Node, depth: Int = 0, count: inout Int) throws -> [String:Any] {
        count += 1
        guard depth < 128, count <= 10000 else { throw BrowserFailure(message:"HTML DOM limit exceeded") }
        if let text = node as? TextNode { return ["tag":"#text", "text":text.getWholeText()] }
        if let text = node as? DataNode { return ["tag":"#text", "text":text.getWholeData()] }
        var attributes: [String:String] = [:]
        for a in node.getAttributes()?.asList() ?? [] { attributes[a.getKey()] = a.getValue() }
        return ["tag":node.nodeName(), "attributes":attributes,
                "children":try node.getChildNodes().filter { $0 is Element || $0 is TextNode || $0 is DataNode }
                    .map { try tree($0,depth:depth+1,count:&count) }]
    }
    static func fragment(_ html: String) throws -> String {
        let document = try Parser.parse(html, "")
        guard let body = document.body() else { throw BrowserFailure(message:"Missing body") }
        var count = 0
        return String(decoding:try JSONSerialization.data(withJSONObject:tree(body,count:&count)),as:UTF8.self)
    }
}

private func parseBrowserFragment(_ pointer: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    guard let pointer else { return nil }
    do { return strdup(try BrowserHTML.fragment(String(cString:pointer))) }
    catch { return strdup("{\"error\":\"HTML fragment parsing failed\"}") }
}

@MainActor final class BrowserScriptRuntime {
    private let engine: OpaquePointer
    init(memoryLimit: Int = 64 * 1024 * 1024) throws {
        guard let engine = cwjs_create(memoryLimit, parseBrowserFragment) else {
            throw BrowserFailure(message:"无法创建脚本解释器")
        }
        self.engine = engine
    }
    deinit { cwjs_destroy(engine) }
    @discardableResult func evaluate(_ script: String, name: String = "page.js") throws -> String {
        guard script.utf8.count <= 4_000_000 else { throw BrowserFailure(message:"Script exceeds 4 MB") }
        var failed: Int32 = 0
        guard let text = cwjs_eval(engine, script, name, &failed) else { throw BrowserFailure(message:"脚本解释器内存不足") }
        defer { cwjs_free_string(text) }
        let result = String(cString:text)
        guard failed == 0 else { throw BrowserFailure(message:"\(name): \(result)") }
        return result
    }
}

struct BrowserPaint: Decodable {
    let kind: String
    let x: Double, y: Double, w: Double, h: Double
    let color: String
    let lineWidth: Double?
}
struct BrowserElement: Decodable, Identifiable {
    let id: Int
    let kind: String
    let text: String
    let disabled: Bool?
    let width: Double?, height: Double?
    let commands: [BrowserPaint]?
}

// This archive accepts bytes supplied by the caller. It has no network fallback.
struct BrowserArchive {
    let pageURL: URL
    let html: String
    let resources: [URL:String]
    static func fixture() throws -> BrowserArchive {
        let base = URL(string:"https://offline.invalid/fixture.html")!
        return BrowserArchive(pageURL:base,html:try BrowserAssets.read("fixture",extension:"html"),resources:[
            URL(string:"qrcode.js",relativeTo:base)!.absoluteURL:try BrowserAssets.read("qrcode",extension:"js"),
            URL(string:"fixture-response.json",relativeTo:base)!.absoluteURL:try BrowserAssets.read("fixture-response",extension:"json")
        ])
    }
}
enum BrowserAssets {
    static func read(_ name: String, extension ext: String) throws -> String {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource:name,withExtension:ext,subdirectory:"BrowserResources") ?? bundle.url(forResource:name,withExtension:ext) else {
            throw BrowserFailure(message:"缺少网页实验资源：\(name).\(ext)")
        }
        return try String(contentsOf:url,encoding:.utf8)
    }
}

@MainActor final class EmbeddedBrowser {
    private var runtime: BrowserScriptRuntime?
    private var archive: BrowserArchive?
    private(set) var executedScripts = 0
    private(set) var resourceReads = 0
    static func json(_ value: Any) throws -> String {
        String(decoding:try JSONSerialization.data(withJSONObject:value,options:[.fragmentsAllowed,.sortedKeys]),as:UTF8.self)
    }
    func load(_ archive: BrowserArchive) throws {
        self.runtime = nil; self.archive = nil; executedScripts = 0; resourceReads = 0
        guard archive.html.utf8.count <= 2_000_000 else { throw BrowserFailure(message:"HTML exceeds 2 MB") }
        let runtime = try BrowserScriptRuntime()
        self.runtime = runtime; self.archive = archive
        try runtime.evaluate(BrowserAssets.read("dom",extension:"js"),name:"dom.js")
        let document = try Parser.parse(archive.html,archive.pageURL.absoluteString)
        guard let html = document.children().first() else { throw BrowserFailure(message:"Missing HTML element") }
        var count = 0
        try runtime.evaluate("__load(\(try Self.json(BrowserHTML.tree(html,count:&count))),\(try Self.json(archive.pageURL.absoluteString)))")
        for script in try document.select("script").array() {
            let type = try script.attr("type").lowercased()
            if !type.isEmpty && !["text/javascript","application/javascript"].contains(type) {
                if type == "module" { throw BrowserFailure(message:"ES module loading is not implemented") }
                continue
            }
            let src = try script.attr("src")
            let source: String
            if src.isEmpty { source = script.data() }
            else {
                guard let url = URL(string:src,relativeTo:archive.pageURL)?.absoluteURL,let bytes = archive.resources[url] else {
                    throw BrowserFailure(message:"离线页面缺少脚本：\(src)")
                }
                source = bytes; resourceReads += 1
            }
            // Stop on the first compatibility failure, rather than showing a false login success.
            try runtime.evaluate(source,name:src.isEmpty ? "inline-\(executedScripts).js" : src)
            executedScripts += 1
        }
        try runtime.evaluate("__ready()")
        try drain()
    }
    func click(_ id: Int) throws {
        guard let runtime else { throw BrowserFailure(message:"Page not loaded") }
        try runtime.evaluate("__click(\(id))")
        try drain()
    }
    func advance(milliseconds: Int) throws {
        guard let runtime else { throw BrowserFailure(message:"Page not loaded") }
        try runtime.evaluate("__advance(\(max(0,min(milliseconds,10000))))")
        try drain()
    }
    private func drain() throws {
        guard let runtime,let archive else { return }
        struct Request: Decodable { let id: Int; let url: String; let method: String }
        for _ in 0..<20 {
            let json = try runtime.evaluate("JSON.stringify(__requests())")
            let requests = try JSONDecoder().decode([Request].self,from:Data(json.utf8))
            if requests.isEmpty { return }
            for request in requests {
                guard request.method.uppercased()=="GET",let url = URL(string:request.url,relativeTo:archive.pageURL)?.absoluteURL,let bytes = archive.resources[url] else {
                    throw BrowserFailure(message:"离线请求未提供响应：\(request.method) \(request.url)")
                }
                resourceReads += 1
                try runtime.evaluate("__respond(\(request.id),200,\(try Self.json(bytes)))")
            }
        }
        throw BrowserFailure(message:"页面请求循环超过限制")
    }
    func snapshot() throws -> [BrowserElement] {
        guard let runtime else { return [] }
        return try JSONDecoder().decode([BrowserElement].self,from:Data(runtime.evaluate("__snapshot()").utf8))
    }
}
