import XCTest
import CoreImage
@testable import CloudWatchCore

final class EmbeddedBrowserTests: XCTestCase {
    @MainActor func testPageClickExecutesJavaScriptFetchAndGeneratesDecodableCanvas() throws {
        let browser = EmbeddedBrowser()
        try browser.load(.fixture())
        let before = try browser.snapshot()
        XCTAssertFalse(before.contains { $0.kind == "canvas" })
        let button = try XCTUnwrap(before.first { $0.kind == "button" })
        try browser.click(button.id)
        let after = try browser.snapshot()
        XCTAssertTrue(after.contains { $0.text == "页面脚本已生成测试二维码" })
        let canvas = try XCTUnwrap(after.first { $0.kind == "canvas" })
        XCTAssertEqual(browser.executedScripts,2)
        XCTAssertEqual(browser.resourceReads,2)
        // Decode the page-generated canvas independently; the app's QR encoder is not used.
        let scale = 4, border = 16, dimension = 144
        let size = (dimension + border * 2) * scale
        var pixels = [UInt8](repeating:255,count:size*size)
        for p in canvas.commands ?? [] where p.kind == "fill" {
            let value: UInt8 = p.color.lowercased() == "#000000" ? 0 : 255
            let x0=max(0,Int(((p.x+Double(border))*Double(scale)).rounded()))
            let y0=max(0,Int(((p.y+Double(border))*Double(scale)).rounded()))
            let x1=min(size,Int(((p.x+p.w+Double(border))*Double(scale)).rounded()))
            let y1=min(size,Int(((p.y+p.h+Double(border))*Double(scale)).rounded()))
            if x1>x0 && y1>y0 { for y in y0..<y1 { for x in x0..<x1 { pixels[y*size+x]=value } } }
        }
        let image=CIImage(bitmapData:Data(pixels),bytesPerRow:size,size:CGSize(width:size,height:size),format:.L8,colorSpace:CGColorSpaceCreateDeviceGray())
        let detector=CIDetector(ofType:CIDetectorTypeQRCode,context:CIContext(),options:[CIDetectorAccuracy:CIDetectorAccuracyHigh])!
        XCTAssertEqual(detector.features(in:image).compactMap { ($0 as? CIQRCodeFeature)?.messageString },["cloudwatch-offline-engine-test"])
    }

    @MainActor func testRuntimeInterruptsInfiniteLoopsAndCanRecover() throws {
        let runtime = try BrowserScriptRuntime()
        let start = Date()
        XCTAssertThrowsError(try runtime.evaluate("while(true) {}"))
        XCTAssertLessThan(Date().timeIntervalSince(start),2)
        XCTAssertEqual(try runtime.evaluate("6*7"),"42")
    }

    @MainActor func testUnhandledAsyncErrorsAreReported() throws {
        let runtime=try BrowserScriptRuntime()
        XCTAssertThrowsError(try runtime.evaluate("(async()=>{throw Error('unsupported web API')})()")) { error in
            XCTAssertTrue(error.localizedDescription.contains("unsupported web API"))
        }
        XCTAssertNoThrow(try runtime.evaluate("Promise.reject(Error('handled')).catch(()=>42)"))
    }

    @MainActor func testMissingExternalScriptNeverFallsBackToNetwork() throws {
        let browser=EmbeddedBrowser()
        XCTAssertThrowsError(try browser.load(BrowserArchive(pageURL:URL(string:"https://offline.invalid/")!,html:"<script src='missing.js'></script>",resources:[:]))) { error in
            XCTAssertTrue(error.localizedDescription.contains("缺少脚本"))
        }
    }

    @MainActor func testHTMLFragmentsEventsAndTimersUpdateNativeSnapshot() throws {
        let html="""
        <body><div id="target"><p>old</p></div><button id="b">replace</button><script>
        document.getElementById('b').onclick=function(){
          document.getElementById('target').innerHTML='<p class="result">A &amp; B</p>';
          setTimeout(()=>document.querySelector('.result').textContent='timer fired',10);
        };
        </script></body>
        """
        let browser=EmbeddedBrowser()
        try browser.load(BrowserArchive(pageURL:URL(string:"https://offline.invalid/")!,html:html,resources:[:]))
        try browser.click(XCTUnwrap(try browser.snapshot().first {$0.kind=="button"}).id)
        XCTAssertTrue(try browser.snapshot().contains {$0.text=="A & B"})
        try browser.advance(milliseconds:10)
        XCTAssertTrue(try browser.snapshot().contains {$0.text=="timer fired"})
    }

    @MainActor func testSavedWebsiteCompatibilityProbe() throws {
        guard let path=ProcessInfo.processInfo.environment["CLOUDWATCH_OFFLINE_ARCHIVE"] else {
            throw XCTSkip("Optional local saved-website compatibility probe")
        }
        let folder=URL(fileURLWithPath:path)
        let html=try String(contentsOf:folder.appendingPathComponent("home.html"),encoding:.utf8)
        // The prior archive only contains these two external scripts. No live fetch is attempted.
        let core=try String(contentsOf:folder.appendingPathComponent("site-0.js"),encoding:.utf8)
        let frame=try String(contentsOf:folder.appendingPathComponent("site-1.js"),encoding:.utf8)
        let pattern="(?:https?:)?//s3\\.music\\.126\\.net[^\\\"'\\s]+\\.js"
        let re=try NSRegularExpression(pattern:pattern)
        var resources:[URL:String]=[:]
        for match in re.matches(in:html,range:NSRange(html.startIndex...,in:html)) {
            guard let range=Range(match.range,in:html) else {continue}
            let src=String(html[range]);let url=URL(string:src.hasPrefix("//") ? "https:"+src : src)!
            if src.contains("/core_"){resources[url]=core}
            if src.contains("/pt_frame_index_"){resources[url]=frame}
        }
        let browser=EmbeddedBrowser()
        do {
            try browser.load(BrowserArchive(pageURL:URL(string:"https://music.163.com/")!,html:html,resources:resources))
            print("OFFLINE SITE PROBE: loaded \(browser.executedScripts) scripts; login still unverified")
        } catch {
            print("OFFLINE SITE PROBE: \(error.localizedDescription)")
        }
    }
}
