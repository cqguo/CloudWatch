# 桌面 EAPI 迁移记录

日期：2026-09-14。依据：本机网易云音乐 macOS 3.1.7 的 Proxyman 抓包，并使用 Swift URLSession 对真实服务器验证。

## 接口映射

全部请求使用 HTTPS POST，主机 `interface.music.163.com`，表单外层为 EAPI `params`。

| 功能 | 实际客户端路径 | watch 处理 |
|---|---|---|
| 获取二维码 key | `/eapi/login/qrcode/unikey` | `type=4`，取 `unikey` |
| 扫码轮询 | `/eapi/login/qrcode/client/login` | 800 过期、801 等待扫码、802 等待确认、803 成功 |
| 当前账号 | `/eapi/w/nuser/account/get` | 读取 `profile.userId` 和昵称 |
| 会话续期 | `/eapi/login/token/refresh` | 使用 Cookie 会话；不再使用 OpenAPI refreshToken |
| 每日推荐 | `/eapi/v3/discovery/recommend/songs` | `data.dailySongs` |
| 创建/收藏/喜欢歌单 | `/eapi/user/playlist` | 按所有者拆分；`specialType=5` 标识喜欢的音乐 |
| 歌单歌曲 ID | `/eapi/v6/playlist/detail` | `playlist.trackIds`，`n=0` |
| 批量歌曲详情 | `/eapi/v3/song/detail` | 以 `c` 批量请求，恢复歌单原有顺序 |
| 单曲搜索 | `/eapi/search/song/list/page` | `data.resources[].baseInfo.simpleSongData` |
| 播放音源 | `/eapi/song/enhance/player/url/v1` | 根据 `data[].url` 和 `freeTrialInfo` 判断播放/试听 |

抓包中还出现搜索综合页、热搜、置顶歌单及会员展示请求；watch 没有对应功能，因此不新增这些请求。

## 二维码地址

取得 key 后本地生成 `https://music.163.com/login?codekey=<unikey>` 的二维码，无需获取二维码图片接口。这个拼接方式由 [API 实现源码](https://raw.githubusercontent.com/NeteaseCloudMusicApiEnhanced/api-enhanced/master/module/login_qr_create.js) 核对；客户端抓包确认 key 和轮询接口、type=4。二维码矩阵继续由 watch 内置 Swift 编码器生成，不将 key 发给外部二维码服务。

## 会话与请求

移除 appId、RSA 私钥、accessToken、refreshToken、bizContent 和公网 IP 查询。EAPI 封装包含协议规定的 MD5 摘要、AES-128-ECB/PKCS7；HTTPS 证书校验保持开启。设备 ID 由每个安装独立生成，不硬编码电脑设备信息。

响应可能为 JSON 或加密数据，解密后兼容 gzip。URLSession 管理 Cookie，保留名称、值、Domain、Path、Secure 与过期时间，成功登录后存入本机钥匙串 `desktop-eapi` 项。旧 `openapi` 项不会被当作新会话读取。

身份由服务端设置的 `MUSIC_U` 等 Cookie 表达。手机确认后必须再成功读取账号资料才能进入资料库。源码和测试只包含虚构会话；真实验证会话临时存放在项目外的私有目录，不打包。

不复制客户端的动态 checkToken、verifyId 或 clientSign；当前已验证的功能在独立设备 ID 和有效登录 Cookie 下可正常调用。未来服务端风控变化需要重新验证。

## 数据与界面

歌曲 ID 改为桌面数值 ID 的字符串表示。时长从毫秒转换为秒。列表不根据旧 OpenAPI playFlag 禁止点击；实际播放请求无 URL 时显示权限错误，试听资源显示“试听片段”。标准/极高音质对应 `standard`/`exhigh`，实际码率由服务端决定。

首次启动直接显示扫码登录入口，删除开发者 RSA 配置界面。个人开发版标记保留。

## 验证

- 10 项单元测试通过：二维码状态、Cookie 作用域和有效期、错误处理、加密响应、搜索结构、大 ID、歌单分页与排序、音源试听/拒绝、队列和二维码容量。
- Swift 真实调用成功：账号、每日推荐、创建/收藏歌单、喜欢歌单、歌单歌曲、搜索、音源 URL；CDN HTTP 206，读取4096字节。
- 原先5首问题歌曲在新 Swift 请求中均返回音源且非试听，见 脱敏结果（本地文件 `build/eapi-five-song-validation.json`，不随仓库发布）。
- 用户已使用手机扫描 watch 自己生成的二维码并确认：803 后进入资料库，重启应用保持登录，加载31首每日推荐。二维码地址、Cookie 接收和钥匙串保存已端到端验证。
- watchOS 26.5 模拟器内，原先5首问题歌曲与控制曲《踊り子》均非试听，AVPlayer 播放进度超过3秒；见 模拟器播放结果（本地文件 `build/eapi-watch-playback-verification.json`，不随仓库发布）。
- `scripts/check.sh` 的10项测试、watchOS 模拟器构建和设备 Release 构建全部通过。
- 普通播放器路径通过：搜索《蓝莲花》、获取音源并播放超过3秒，见 播放器验证（本地文件 `build/eapi-watch-player-verification.json`，不随仓库发布）。
- 脱敏请求字段清单见 10个接口抓包摘要（本地文件 `build/desktop-api-capture.json`，不随仓库发布）。
- 真机蜂窝、锁屏后台与蓝牙输出未以模拟器结果代替。
