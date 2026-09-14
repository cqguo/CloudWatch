# 手表内嵌网页引擎：个人设备原型

## 当前交付边界

此版本验证开源解释器、HTML 解析器能够编译进 watchOS App，并由页面脚本驱动原生重排界面。它**尚不是能运行网易云官网的完整浏览器**，没有完成官网二维码登录。

应用只保留“网页二维码”页面，直接打开本地 HTML 验证内容；旧播放器、搜索、歌单、账号管理、原生接口扫码、对应测试和构建缓存均已移除。没有真实账号读取或恢复逻辑。

## 实现

- QuickJS 2026-06-04：随包编译 C 解释器，没有 JIT，也没有引入 quickjs-libc 的文件、进程和网络接口。
- SwiftSoup 2.6.0：HTML 解析和 HTML 实体处理，转换为 JavaScript 可操作的节点树。
- dom.js：DOM 子集、元素创建、innerHTML 写入、属性、基础选择器、事件冒泡、显式推进的定时器、Promise/fetch 桥接和 Canvas 矩形绘图。
- EmbeddedBrowser：按文档顺序执行已有的经典 script；所有外部脚本和 fetch 响应必须由 BrowserArchive 提供。缺失即报错，没有 URLSession/其他联网回退。
- SwiftUI：按页面节点顺序重排文字、按钮与 Canvas；点击按钮回到页面事件处理器。并非完整 CSS 排版。
- 脚本限制：64 MiB JS 堆、512 KiB JS 栈、单次执行约 500 ms、微任务及定时器数量上限；异步未处理异常可见。HTML 限 2 MB/深度 128/节点 10000，单脚本限 4 MB。

## 验证页

`fixture.html` 的按钮运行内联网页脚本，通过 fetch 读取本地 fixture-response.json，再调用未修改的开源 qrcode.js 创建 Canvas。SwiftUI 只显示页面 Canvas 绘图结果。二维码编码内容为 `cloudwatch-offline-engine-test`，没有网易账号意义。

测试将 Canvas fillRect 绘制结果交给 Apple CIDetector，独立解码成功。另验证 HTML 实体、innerHTML、点击事件、定时器、无限循环中断、异步异常和缺失资源失败。

模拟器离线验收启动参数：`--browser-lab-click`。它直接触发本地页面按钮事件，不会连接网易云。该参数不等同于验证了真实手指点击。

## 官网存档探测

运行：

```sh
CLOUDWATCH_OFFLINE_ARCHIVE=/tmp/cloudwatch-web swift test --filter testSavedWebsiteCompatibilityProbe
```

只读取既有 home.html、site-0.js、site-1.js。当前最早失败：`inline-1.js:7:26`，对应首页动态插入脚本的 `s.parentNode.insertBefore(hm, s)`。这不是登录失败原因证明，只是当前解释器兼容性缺口。该探测会打印结果，不把“测试命令通过”作为官网兼容通过。

## 尚缺

动态脚本/iframe 文档加载、完整 DOM/选择器和 CSSOM、XMLHttpRequest、真实 Cookie/存储生命周期、URL/导航、更多 Canvas/图片 API、浏览器事件循环、媒体接口及真实网络会话。不能通过修改 User-Agent 宣称已经具备这些能力。

本机存档不足以复原整个站点。真实官网工具访问仍被 site-safety policy 拦截，本轮没有使用新引擎或其他通道重新访问该站点。后续在允许的环境中需要真实页面验证；本原型不保证消除 8821。

## 上游与本地修改

- QuickJS：https://www.bellard.org/quickjs/quickjs-2026-06-04.tar.xz
  SHA-256：b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a
  原始 LICENSE 在 CloudWatch/BrowserJS/LICENSE；quickjs.c 仅增加 CONFIG_VERSION 宏。BrowserJS.c 和 include/BrowserJS.h 是本地桥接实现。
- SwiftSoup：https://github.com/scinfu/SwiftSoup，tag 2.6.0，commit 0e96a20ffd37a515c5c963952d4335c89bed50a6
  LICENSE 在 CloudWatch/HTMLParser/LICENSE。本地修改 SwiftSoup.swift 两处模块限定调用，以及 XmlTreeBuilder.swift 一处解析调用，以支持同源码加入 Xcode App 模块。
- QRCode.js：https://github.com/davidshimjs/qrcodejs
  qrcode.js SHA-256：3ee72de9f69c668f9567363a9358df955960bae9000d9ebd66414670f88e8735
  完整授权在 docs/licenses/qrcodejs-LICENSE，脚本版权头保留。只用于离线验证页。
