# CloudWatch · 云音乐 Apple Watch 客户端

使用 SwiftUI 构建的独立 watchOS 音乐应用，直接调用网易云音乐桌面客户端 EAPI，在手表上扫码登录、浏览资料库、搜索并播放音乐。个人开发项目，非网易官方客户端。

> **本仓库仅提供源代码，不提供 GitHub Releases，也不提供预编译安装包。需要自行使用 Xcode 编译、签名并安装到 Apple Watch。**

## 功能

- 使用手机网易云音乐 App 扫描手表二维码并确认登录，会话保存在本机 Keychain。
- 浏览每日推荐、已创建的歌单、已收藏的歌单和「我喜欢的音乐」。
- 歌单歌曲与搜索结果分页加载，支持单曲搜索。
- 直接从网易音频 CDN 串流播放，支持暂停、切歌、进度调整、随机播放和列表循环。
- 接入系统 Now Playing 和媒体控制，可选择标准或较高音质、是否允许蜂窝音频播放。

随机播放和队列只包含当前已加载的歌曲；目前没有离线下载、歌词、创建歌单或收藏编辑功能。

## 为什么使用客户端接口

当前实现使用网易云音乐电脑客户端的 **EAPI**，请求由手表上的 `URLSession` 发往 `interface.music.163.com`，音频由 `AVPlayer` 从 CDN 读取。

相对于项目早期的 OpenAPI / 网页原型，这种实现的优势是：

| 方面 | 当前实现的优势 |
| --- | --- |
| 登录配置 | 直接扫码授权，无需申请或填写 OpenAPI appId、RSA 私钥，也无需复制电脑登录 Cookie。 |
| 部署成本 | 无需自建 API 代理、签名服务器或常驻电脑进程；手机用于首次扫码授权，音频请求由手表发起。 |
| 原生交互 | SwiftUI 展示列表与播放器，无需嵌入网页、执行网页脚本或解析网页 DOM。 |
| 数据与播放 | 对接客户端的推荐、歌单、搜索及音源接口，点播时获取最新音源；根据实际音源响应判断可播与试听状态。 |
| 会话管理 | 每次安装生成独立设备 ID，保留 Cookie 的作用域和有效期，使用本机 Keychain 保存会话。二维码在本地生成。 |
| 构建依赖 | 当前 App 和核心库没有第三方 Swift Package 依赖，使用系统网络、音频及安全框架。 |

EAPI 是客户端使用的接口，并非本项目获得授权的稳定公共 API。服务端调整可能导致登录或播放失效。**客户端接口不会解除会员、版权或地区限制**；是否提供音源、是否仅可试听、实际音质和码率均由服务器决定，试听资源会在界面标记。

## 自行编译与安装

### 环境

- macOS 和 Xcode，安装 watchOS SDK；部署目标为 watchOS 10.0 及以上。
- Swift 5.9 或更高版本；重新生成工程时需要 Python 3。
- 真机安装需要在 Xcode 配置自己的 Apple 开发签名账号，并连接可用于开发的 Apple Watch。

本项目本地构建验证环境为 Xcode 26.5。仓库包含 Xcode 工程，可直接打开。

### 安装到手表

1. 克隆或下载本仓库，在项目根目录执行：

   ```sh
   open CloudWatch.xcodeproj
   ```

2. 选择 `CloudWatch` Target，在 **Signing & Capabilities** 中选择自己的 **Team**，将 **Bundle Identifier** 改为自己的唯一标识，使用自动签名。
3. 选择 `CloudWatch` Scheme 和自己的 Apple Watch 运行目标，完成 Xcode 提示的配对、开发者模式及签名配置。
4. 点击 **Run**，由 Xcode 编译并安装。
5. 在手表上点击「登录网易云音乐」，使用手机网易云音乐 App 扫码确认；进入资料库后选择歌曲播放，并按系统提示选择音频输出。

签名有效期与安装限制取决于自己的开发账号。仓库不包含作者的开发 Team、证书或描述文件。

### 本地检查

```sh
# 仅运行核心库测试，不需要登录网易账号
swift test

# 完整检查：核心测试 + watchOS 模拟器构建 + 真机目标无签名构建
sh scripts/check.sh
```

完整检查的输出位于 `build/Simulator` 和 `build/Watch`。**脚本中的 Release 是编译配置，真机目标产物未签名，不能直接安装；它不代表提供 GitHub Release。** 真机安装仍按上述 Xcode 签名步骤完成。

新增源码文件后可重新生成工程：

```sh
python3 scripts/generate_project.py
```

生成器会重写工程及 Scheme；如已手动设置 Team 或 Bundle Identifier，重新生成后需要再次设置。

## 客户端接口如何使用

`CloudWatch/Core/DesktopAPI.swift` 提供 `actor DesktopAPI`，统一管理 EAPI 请求和 Cookie。App 的 `MusicStore` 管理登录状态，`AudioPlayer` 负责播放。

| 功能 | Swift 入口 | EAPI 路径 |
| --- | --- | --- |
| 获取登录二维码 | `beginLogin()` | `/eapi/login/qrcode/unikey` |
| 轮询扫码状态 | `pollLogin(key:)` | `/eapi/login/qrcode/client/login` |
| 当前账号 / 续期 | `profile()` / `refresh()` | `/eapi/w/nuser/account/get` / `/eapi/login/token/refresh` |
| 每日推荐 | `daily()` | `/eapi/v3/discovery/recommend/songs` |
| 已创建 / 已收藏 / 喜欢歌单 | `playlists(collected:offset:)` / `favorite()` | `/eapi/user/playlist` |
| 歌单分页与歌曲详情 | `tracks(_:offset:)` | `/eapi/v6/playlist/detail` + `/eapi/v3/song/detail` |
| 单曲搜索 | `search(_:offset:)` | `/eapi/search/song/list/page` |
| 获取播放资源 | `audio(_:bitrate:)` | `/eapi/song/enhance/player/url/v1` |

调用流程：

1. `beginLogin()` 返回二维码 URL 和 key，在本地绘制二维码。
2. 以该 key 调用 `pollLogin(key:)`，处理等待扫码、等待确认、过期和成功状态。收到 803 后还会读取账号资料，确认登录有效。
3. 授权成功后调用推荐、歌单或搜索接口；使用歌曲对象调用 `audio` 获取音源，再交给播放器。
4. 音质参数 `128` 对应 `standard`，大于 `128` 对应 `exhigh`，仅表示请求档位，不保证服务器返回固定码率。

`EAPITransport.swift` 负责协议规定的摘要、AES 封装和响应解码；请求通过 HTTPS 发送。不需要额外部署 Node.js API 服务。接口适配依据和历史验证范围见 [桌面 EAPI 迁移记录](docs/desktop-api-migration.md)。

## 目录

```text
CloudWatch/             watchOS App、核心接口、播放器和资源
CloudWatch.xcodeproj/   可直接打开的 Xcode 工程与共享 Scheme
Tests/                 核心逻辑和模拟接口测试
Tools/NativeProbe/     可选的真实接口诊断工具
scripts/               工程生成、本地构建和模拟器辅助工具
docs/                  接口迁移说明与历史验证记录
Legacy/                不参与当前构建的旧网页实验及历史文档
```

真实接口诊断涉及个人登录会话，仅适合本地开发。Debug 构建可导入沙盒 `Documents/provisioning.json`，写入 Keychain 后删除；Release 不包含此入口。不要提交 Cookie、登录二维码、签名材料或原始抓包；仓库忽略本机配置和构建输出。

旧实验的第三方组件及许可证见 [第三方说明](Legacy/BrowserPrototype/docs/THIRD_PARTY_NOTICES.md)，它们不参与当前 App 构建。

## 验证范围

核心测试使用虚构会话与模拟响应，不依赖真实账号。已有本地记录覆盖独立扫码、重启保持登录、推荐/歌单/搜索和模拟器播放；这些记录不等于每个账号、系统版本或网络环境均可用。

真机蜂窝播放、锁屏后台持续播放、蓝牙输出和网络切换仍需在自己的手表上验证。遇到问题时请附 Xcode/watchOS 版本、复现步骤和脱敏错误信息。
