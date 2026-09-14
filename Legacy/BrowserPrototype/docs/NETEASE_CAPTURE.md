# 网易云网页抓取脚本

使用 Python 3 标准库，无需安装依赖。在项目根目录运行：

```sh
# 官网首页：HTML、文本、链接
python3 scripts/fetch_netease.py

# 同时保存静态资源，优先下载脚本和样式
python3 scripts/fetch_netease.py --assets

# “发现音乐”页面。带 # 的客户端路由会自动转换为服务器路径。
python3 scripts/fetch_netease.py 'https://music.163.com/#/discover'

# 指定公开歌单链接与输出目录（请替换歌单 ID）
python3 scripts/fetch_netease.py 'https://music.163.com/#/playlist?id=你的歌单ID' -o build/my-playlist

# 调整资源数量限制、间隔和请求超时
python3 scripts/fetch_netease.py --assets --max-resources 100 --delay 1 --timeout 30
```

默认输出到 `build/captures/时间戳/`，也可用 `-o` 指定空目录。脚本拒绝覆盖非空目录。

| 文件 | 内容 |
| --- | --- |
| `page.html` | 服务器返回的 HTML 原始字节 |
| `text.txt` | 从 HTML 提取的文本，排除 script/style/noscript；不等同于浏览器可见正文 |
| `links.json` | 去重后的绝对链接列表，不会逐个爬取这些链接 |
| `resources/` | 启用 `--assets` 时保存的脚本、样式、图片和 iframe 页面资源 |
| `manifest.json` | 页面信息、编码、资源原始 URL 与本地文件映射、错误及未下载列表 |

资源模式继续解析下载的 HTML 和 CSS 中的资源引用，默认最多请求 60 个资源，每次间隔 0.5 秒，单文件最多 10 MB。资源文件名使用 URL 的 SHA-256，以避免同名文件覆盖。模板占位地址会被跳过。遇到资源 HTTP 401、403、429 时停止后续资源请求。

退出码：`0` 表示本次范围内下载完成；`1` 表示入口页面失败；`2` 表示资源有失败或达到限制后还有待下载项。详情查看 `manifest.json`。

网易云首页包含由 JavaScript 控制的 iframe，初始地址可以是 `about:blank`。脚本不执行 JavaScript，因此首页快照不等于浏览器运行后的完整页面；需要发现页或歌单时请直接提供对应链接。脚本不处理登录、验证码、动态接口、音频下载、JS 动态导入或所有图片 srcset。HTTP 成功也不保证返回所需业务内容，应检查保存的页面。

HTML 和 CSS 保留原始资源地址，输出供分析使用，不是可直接离线运行的网站镜像。未自动接入当前 watchOS 原型的 BrowserArchive。
