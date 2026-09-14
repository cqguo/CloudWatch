# CloudWatch · 云音乐 Apple Watch 客户端

原生 SwiftUI / watchOS 音乐应用，直接使用网易云音乐桌面客户端 EAPI。个人开发项目，非网易官方客户端。

> **仅提供源代码，不提供 GitHub Release 或预编译安装包。需要自行使用 Xcode 编译、签名并安装。**

## 功能与接口优势

- 手机网易云音乐 App 扫码登录，会话保存在手表 Keychain，无需 appId、RSA 私钥或手动复制 Cookie。
- 浏览每日推荐、已创建/已收藏歌单及「我喜欢的音乐」，支持歌曲搜索和分页加载。
- 手表直接请求客户端接口与音频 CDN，无需自建 API 服务或常驻电脑中转。
- 原生播放器支持播放队列、随机播放、列表循环、进度调整与系统媒体控制，无第三方 Swift 包依赖。

音源权限、试听状态和实际音质由服务器决定，不绕过会员、版权或地区限制。客户端接口变化可能影响可用性。队列仅包含已加载歌曲，暂不支持离线下载和歌词。

## 编译安装

需要 macOS、Xcode 和 watchOS SDK，部署目标为 watchOS 10+；核心测试需要 Swift 5.9+。已在 Xcode 26.5 验证构建。

1. 克隆仓库并打开工程：

   ```sh
   git clone https://github.com/cqguo/CloudWatch.git
   cd CloudWatch
   open CloudWatch.xcodeproj
   ```

2. 选择 `CloudWatch` Target，在 **Signing & Capabilities** 中选择自己的 **Team**，修改 **Bundle Identifier** 为自己的唯一标识。
3. 选择自己的 Apple Watch 运行目标，按 Xcode 提示完成配对和开发者配置，点击 **Run** 编译安装。
4. 在手表上点击「登录网易云音乐」，用手机 App 扫码确认，再选择歌曲和音频输出。

签名有效期与安装限制取决于自己的开发账号。真机蜂窝、锁屏后台播放和蓝牙输出需在自己的手表上验证。

## 代码与检查

- `CloudWatch/App/`：界面、登录状态与播放器。
- `CloudWatch/Core/`：EAPI 请求、Cookie 会话、Keychain、二维码与数据模型。
- `Tests/`：使用模拟响应的核心测试。
- `scripts/`：工程生成与构建检查。

`DesktopAPI` 的调用顺序：`beginLogin()` 获取二维码 → `pollLogin(key:)` 等待授权 → `daily()` / `playlists(collected:offset:)` / `search(_:offset:)` 获取歌曲 → `audio(_:bitrate:)` 获取音源交给播放器。请求使用 HTTPS，EAPI 封装由 `EAPITransport.swift` 处理。

```sh
swift test                       # 核心测试，无需登录
sh scripts/check.sh              # 测试 + 模拟器构建 + 真机无签名构建
python3 scripts/generate_project.py  # 新增源码后重新生成工程（需要 Python 3）
```

重新生成工程会覆盖手动设置的 Team 和 Bundle Identifier，需要重新配置。检查脚本的 `Release` 仅指编译配置，产物未签名，不是可直接安装的发行包。
