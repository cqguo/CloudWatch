# OpenAPI 历史实现与验证记录

> 归档：下文描述已停用的 OpenAPI 实现，不适用于当前版本。当前实现见 [EAPI 迁移记录](../../docs/desktop-api-migration.md)。

日期：2026-09-14。目标：watchOS 10+，独立 Watch App。

## 数据链路

SwiftUI → OpenAPI actor → RSA SHA256 签名 → `https://openncm.music.163.com`。

播放器另行获取歌曲详情中的 `playUrl` → AVURLAsset/AVPlayer → 网易音频 CDN。不使用 Orpheus URL Scheme，不依赖 `ncm-cli` 或手机进程。音频不先经电脑下载再转发。

公共参数包括 appId、signType、timestamp（毫秒）、device、bizContent、accessToken。将不含 sign 的参数按名字排序，以 `key=value&...` 拼接，用 PKCS#1 v1.5 SHA256 签名，签名以 Base64 传输。PKCS#8 私钥先解析为系统 Security 接受的 PKCS#1；所有钥匙串项使用 AfterFirstUnlockThisDeviceOnly。

源码不含用户应用密钥。个人开发配置可在应用设置导入；模拟器 Debug 专用一次性沙盒导入在成功写入 Keychain 后删除原文件。

## 已验证接口

所有路径均位于 `/openapi/music/basic/` 下。

|用途|方法|路径|data 类型|
|---|---|---|---|
|每日推荐|GET|recommend/songlist/get/v2|歌曲数组|
|创建的歌单|GET|playlist/created/get/v2|records + recordCount|
|收藏的歌单|GET|playlist/subed/get/v2|records + recordCount|
|红心歌单|POST|playlist/star/get/v2|歌单对象|
|歌单歌曲|GET|playlist/song/list/get/v3|歌曲数组（不是 Page 对象）|
|歌曲搜索|GET|search/song/get/v3|records + recordCount|
|音源|GET|song/detail/get/v2|带 playUrl 的歌曲对象|
|用户资料|GET|user/profile/get/v2|用户对象|
|二维码|GET|user/oauth2/qrcodekey/get/v2|qrCodeUrl + uniKey|
|扫码轮询|GET|oauth2/device/login/qrcode/get|授权状态/Token|
|续期|POST|user/oauth2/token/refresh/v2|accessToken、refreshToken、expiresTime|

音源业务参数：songId（加密 ID）、withUrl=true、bitrate=128/320、trialScene=cli。权限受应用与账号共同约束；缺少音源/无播放权限不能通过替换歌曲数字 ID 绕开。每次开始播放重新解析音源，不缓存为永久直链。

查询的 created/collected 接口每页 30 条，歌曲每页 30 首。歌单接口总数取歌单 trackCount；实际短页也会终止分页。播放/随机起播仅作用于当前已加载歌曲，界面明确说明，避免将部分列表冒充完整歌单。

expiresTime 已实测为 86400（有效秒数），不是毫秒绝对时间。兼容绝对秒/毫秒时间戳。临近到期或认证失败自动续期一次，续期失败引导扫码，不无限重试。

服务器对错误响应可能返回 data:[]。先检查业务状态，再按成功模型解码，确保不会把权限错误显示为 JSON 类型错误。

## 网络与音频

- URLSession 允许蜂窝/昂贵网络。AVURLAsset 的蜂窝与昂贵网络开关来自用户设置。
- clientIp 为必填参数。与官方 CLI 相同使用 HTTPS ipify / ip.sb 查询出口 IP；不附带应用密钥或用户 Token。网络变化后失效缓存，避免一直发送开发机的 IP。
- 音频会话使用 playback + longFormAudio，异步激活输出路由；Info.plist 声明 WKBackgroundModes/audio。
- 音频链接当前是 HTTP MP3；ATS 仅允许 music.126.net 及子域 HTTP，不关闭全局 ATS。封面优先升级 HTTPS。
- 系统 Now Playing 显示曲名/歌手/进度，远程命令支持播放暂停、切歌和定位。
- 监听 item.status、timeControlStatus、播放结束、播放失败和音频中断。不以发起 play() 本身作为成功证据。
- 网络失败保留错误与重试按钮；重试重新获取音源。尚未实现下载缓存、离线播放、歌词、后台无限重试。

## 测试

`sh scripts/check.sh`：7 个 Swift 测试覆盖签名验证、URL 编码、官方数组响应、业务错误、认证失败、不可播放歌曲过滤、队列边界、分页模型、大 ID、二维码尺寸及容量；模拟器和 watchOS Release 构建。

`swift run NativeProbe /private/provisioning.json`：真实登录资料、每日推荐、两类歌单、红心歌单、歌单歌曲、搜索和音源。音频首段返回 HTTP 206 / 4096 bytes。程序不打印 Token、签名、完整音源 URL。

Debug 启动参数 `--verify-audio`：在模拟器中搜索一个可播放版本，原生播放至至少 3 秒，然后自动停止，将状态写入应用 Documents/audio-verification.json。实测通过，duration=502.256 秒，position=3.000 秒。

登录二维码由本地 Swift QR Model 2 实现生成（version 5-L, mask 0），用独立 jsQR 解码器核对 URL 一致。

模拟器界面截图已检查首页和播放页面。当前 UI 自动化服务无法向模拟器窗口发送点击，因此未宣称已完成所有按钮的自动化交互测试。

## 真机验收与尚未解决的外部条件

1. 在 Xcode 选择用户自己的 Team，签名并安装到蜂窝 Apple Watch。
2. 使用获批的手表应用配置；当前“云音乐-CLI版”只验证了其原约定设备描述，直接填 watchOS 被服务器拒绝。需要平台确认手表授权条件，不能以原生请求成功推断分发许可。
3. 连接蓝牙耳机，在手表离开手机且关闭 Wi-Fi 后，确认显示蜂窝网络，播放、切歌、锁屏持续播放。
4. 验证来电/耳机断开/网络切换后的暂停和手动恢复，以及关闭蜂窝播放后的音频限制。
5. 对多用户发行改用受控服务端签名或网易正式设备认证流程，不能把同一应用 RSA 私钥嵌入公开安装包。

官方参考：
- [网易官方 CLI 与 Skills](https://github.com/NetEase/skills)
- [网易云音乐开放平台](https://developer.music.163.com/)
- [Apple：Playing Background Audio](https://developer.apple.com/documentation/watchkit/playing-background-audio)
- [Apple：Streaming Audio on watchOS 6](https://developer.apple.com/videos/play/wwdc2019/716/)
