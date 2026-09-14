import SwiftUI

struct EmbeddedBrowserView: View {
    @State private var browser: EmbeddedBrowser?
    @State private var elements: [BrowserElement] = []
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:10) {
                if let canvas=elements.first(where:{$0.kind=="canvas"}) {
                    Text("本地测试二维码").font(.caption2).foregroundStyle(.orange)
                    BrowserCanvasView(element:canvas)
                } else {
                    Text("本地页面 · 不用于账号登录").font(.caption2).foregroundStyle(.orange)
                }
                if loading { ProgressView("加载页面") }
                ForEach(elements.filter {$0.kind != "canvas"}) { element in
                    switch element.kind {
                    case "button":
                        Button(element.text) { interact(element.id) }
                            .disabled(element.disabled ?? false)
                            .accessibilityIdentifier("browser.element.\(element.id)")
                    case "canvas": BrowserCanvasView(element:element)
                    default: Text(element.text).font(.caption2)
                    }
                }
                if let error { Text(error).font(.caption2).foregroundStyle(.orange) }
                Button("重新加载本地页面") { load() }
            }
        }
        .navigationTitle("网页二维码")
        .task { load() }
    }
    private func load() {
        loading=true;error=nil;elements=[]
        do {
            let instance=EmbeddedBrowser()
            try instance.load(.fixture());browser=instance
            elements=try instance.snapshot()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--browser-lab-click"),let button=elements.first(where:{$0.kind=="button"}) {
                interact(button.id)
            }
            #endif
        } catch { self.error=error.localizedDescription }
        loading=false
    }
    private func interact(_ id: Int) {
        do { try browser?.click(id);elements=try browser?.snapshot() ?? [];error=nil }
        catch { self.error=error.localizedDescription }
    }
}

struct BrowserCanvasView: View {
    let element: BrowserElement
    var body: some View {
        Canvas { context,size in
            let width=max(1,min(element.width ?? 144,2048))
            let height=max(1,min(element.height ?? 144,2048))
            let padding=12.0
            let scale=min(size.width/(width+padding*2),size.height/(height+padding*2))
            context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(.white))
            context.translateBy(x:padding*scale,y:padding*scale)
            context.scaleBy(x:scale,y:scale)
            context.clip(to:Path(CGRect(x:0,y:0,width:width,height:height)))
            for command in element.commands ?? [] {
                let rect=Path(CGRect(x:command.x,y:command.y,width:command.w,height:command.h))
                let color=Self.color(command.color)
                if command.kind=="stroke" { context.stroke(rect,with:.color(color),lineWidth:command.lineWidth ?? 1) }
                else { context.fill(rect,with:.color(color),style:FillStyle(antialiased:false)) }
            }
        }
        .frame(width:140,height:140)
        .accessibilityLabel("网页脚本绘制的测试二维码")
    }
    private static func color(_ value:String)->Color {
        if value.lowercased()=="white" {return .white}
        let hex=value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard hex.count==6,let number=UInt32(hex,radix:16) else {return .black}
        return Color(red:Double((number>>16)&255)/255,green:Double((number>>8)&255)/255,blue:Double(number&255)/255)
    }
}
