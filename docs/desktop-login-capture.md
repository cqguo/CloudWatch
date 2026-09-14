# 电脑客户端登录抓包记录

记录日期：2026-09-14。客户端：网易云音乐 macOS 3.1.7。工具：Proxyman 6.17.0。

## 已确认的登录流程

| 阶段 | POST 路径 | 业务响应 |
|---|---|---|
| 获取二维码 key | `/eapi/login/qrcode/unikey` | `200`，返回 `unikey` |
| 等待扫码 | `/eapi/login/qrcode/client/login` | `801` |
| 手机已扫码、等待确认 | 同上 | `802`，还返回昵称和头像字段 |
| 手机确认授权成功 | 同上 | `803`，通过 HTTP `Set-Cookie` 返回登录会话 |
| 获取当前账号 | `/eapi/w/nuser/account/get` | `200`，返回 `account` 与 `profile` |

以上请求的服务器是 `https://interface.music.163.com`。HTTP 状态均为 200；801/802/803 是响应体内的业务状态，不能按 HTTP 错误处理。第一次显示二维码发生在清理会话附近，初始 key 请求未保留；本次抓包保留了后续一次成功的 key 请求，以及完整的等待、扫码、授权成功和账号读取响应。脱敏 JSON 保留事件实际时间，不将它们重排为单个 key 的流程。

## 参数与身份信息

二维码 key 请求字段：`deviceId`、`e_r`、`header`、`os`、`type`、`verifyId`。
轮询另有：`key`、`secureCaptcha`。本次 `type="4"`、`os="OSX"`、`e_r=true`。

外层请求体是表单 `params`，内容采用 EAPI 封装。响应也可能采用 EAPI 加密。抓包解析仅在本机离线进行。

播放请求中的 `header` 是 JSON 字符串，包含 `appver`、`clientSign`、`deviceId`、`os`、`osver`、`requestId`。设备字段不能直接等同于用户身份。

登录前请求出现 `MUSIC_A` 等 Cookie；授权成功响应设置了 `MUSIC_U`、`__csrf`、`MUSIC_A_T`、`MUSIC_R_T`、`MUSIC_R_U` 等 Cookie。随后账号接口请求携带 `MUSIC_U`。因此迁移必须保留服务端会话 Cookie，不能仅将 OpenAPI 的 accessToken 改名使用。不同 Domain/Path 的同名 Cookie 不能简单按名称覆盖。

没有在本报告或脱敏 JSON 中保存 Cookie 值、二维码 key、用户 ID、昵称、头像、设备 ID 或客户端签名。

## 对 watch 迁移的约束

1. 用 EAPI 请求封装与响应解码替换原先的 appId + RSA + bizContent 协议。
2. 用扫码 Cookie 会话替换 accessToken/refreshToken；在钥匙串保存会话并处理退出登录和失效。
3. 二维码状态机区分等待扫码、已扫码、成功、过期；803 时先接收会话，再拉取账号确认登录。
4. 后续已核对并实测二维码地址 `https://music.163.com/login?codekey=<unikey>`；用户已在 watch 扫码授权成功。
5. 日推、歌单、歌曲详情、搜索和音源需逐项适配数据结构。客户端数值歌曲 ID 与原 OpenAPI 加密 ID 不可混用。
6. 实测播放接口为 `/eapi/song/enhance/player/url/v1`，前面5首歌均返回音源 URL、完整时长，`freeTrialInfo=null`。此结果不代表其他账号也具有同样权限。

## 当前进度

登录过程已记录并验证成功。watch 的所有现有 API 调用已迁移，独立扫码、重启恢复与播放已验证，详见 [迁移记录](desktop-api-migration.md)。未将电脑会话硬编码进应用。

脱敏事件：desktop-login-capture.json（本地文件 `build/desktop-login-capture.json`，不随仓库发布）
播放验证：desktop-playback-capture.json（本地文件 `build/desktop-playback-capture.json`，不随仓库发布）
