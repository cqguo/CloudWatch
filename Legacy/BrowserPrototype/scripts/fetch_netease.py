#!/usr/bin/env python3
"""抓取网易云公开网页及可选静态资源；仅使用 Python 3 标准库。"""

import argparse
from collections import deque
from datetime import datetime, timezone
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urldefrag, urljoin, urlsplit, urlunsplit
from urllib.request import Request, urlopen


def normalize_url(value):
    """将网易云的 /#/playlist?id=... 转换为服务器可访问的路径。"""
    parts = urlsplit(value)
    if parts.scheme not in ("http", "https") or not parts.hostname:
        raise ValueError("URL 必须是完整的 http(s) 链接")
    if parts.hostname == "music.163.com" and parts.fragment.startswith("/"):
        return urljoin("https://music.163.com/", parts.fragment)
    return urlunsplit(parts._replace(fragment=""))


class PageParser(HTMLParser):
    def __init__(self, url):
        super().__init__(convert_charrefs=True)
        self.url = url
        self.base = url
        self.has_base = False
        self.hidden = 0
        self.in_title = False
        self.title = []
        self.text = []
        self.links = []
        self.resources = []

    def resolve(self, value):
        if any(marker in value for marker in ("${", "{{", "<%")):
            return None
        value = urldefrag(urljoin(self.base, value))[0]
        return value if urlsplit(value).scheme in ("http", "https") else None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in ("script", "style", "noscript"):
            self.hidden += 1
        if tag == "title":
            self.in_title = True
        if tag == "base" and attrs.get("href") and not self.has_base:
            self.base = self.resolve(attrs["href"]) or self.base
            self.has_base = True
        if tag == "a" and attrs.get("href"):
            link = self.resolve(attrs["href"])
            if link:
                self.links.append(link)
        field = {"script": "src", "img": "src", "iframe": "src", "frame": "src"}.get(tag)
        if tag == "link" and "stylesheet" in attrs.get("rel", "").lower().split():
            field = "href"
        if field and attrs.get(field):
            link = self.resolve(attrs[field])
            if link:
                self.resources.append(link)

    def handle_endtag(self, tag):
        if tag in ("script", "style", "noscript"):
            self.hidden = max(0, self.hidden - 1)
        if tag == "title":
            self.in_title = False

    def handle_data(self, data):
        if self.in_title:
            self.title.append(data)
        if not self.hidden and data.strip():
            self.text.append(data.strip())


def fetch(url, timeout, max_bytes, referer):
    request = Request(url, headers={
        "User-Agent": "Mozilla/5.0 (compatible; NetEasePageArchiver/1.0)",
        "Accept": "*/*",
        "Accept-Encoding": "identity",
        "Referer": referer,
    })
    with urlopen(request, timeout=timeout) as response:
        body = response.read(max_bytes + 1)
        if len(body) > max_bytes:
            raise ValueError(f"响应超过单文件限制 {max_bytes} 字节")
        return body, response.geturl(), response.headers.get_content_type(), response.headers.get_content_charset() or "utf-8", response.status


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def positive_int(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("必须大于 0")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", nargs="?", default="https://music.163.com/")
    parser.add_argument("-o", "--output", type=Path, help="输出目录（须不存在或为空）")
    parser.add_argument("--assets", action="store_true", help="下载 HTML 中的脚本、样式、图片、iframe 及 CSS url() 资源")
    parser.add_argument("--max-resources", type=positive_int, default=60)
    parser.add_argument("--max-bytes", type=positive_int, default=10_000_000, help="单文件最大字节数")
    parser.add_argument("--timeout", type=positive_int, default=25, help="每次请求超时秒数")
    parser.add_argument("--delay", type=float, default=0.5, help="资源请求间隔秒数，至少 0.2")
    args = parser.parse_args()
    if not 0.2 <= args.delay <= 60:
        parser.error("--delay 必须在 0.2 至 60 之间")
    try:
        url = normalize_url(args.url)
    except ValueError as exc:
        parser.error(str(exc))
    output = args.output or Path("build/captures") / datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        parser.error(f"输出目录非空或不是目录：{output}")
    output.mkdir(parents=True, exist_ok=True)
    manifest = {"requested_url": args.url, "url": url, "captured_at": datetime.now(timezone.utc).isoformat(), "resources": [], "errors": [], "skipped": []}
    try:
        body, final_url, mime, charset, status = fetch(url, args.timeout, args.max_bytes, url)
        if mime not in ("text/html", "application/xhtml+xml"):
            raise ValueError(f"入口返回 {mime}，不是 HTML 页面")
        html = body.decode(charset, errors="replace")
        page = PageParser(final_url)
        page.feed(html)
        (output / "page.html").write_bytes(body)
        (output / "text.txt").write_text("\n".join(page.text) + "\n", encoding="utf-8")
        write_json(output / "links.json", list(dict.fromkeys(page.links)))
        manifest.update(final_url=final_url, title="".join(page.title).strip(), status=status, content_type=mime, charset=charset, html="page.html")
        print(f"已保存页面：{manifest['title']} ({len(body)} 字节)")
    except (OSError, URLError, ValueError, LookupError) as exc:
        manifest["errors"].append({"url": url, "error": str(exc)})
        write_json(output / "manifest.json", manifest)
        print(f"抓取失败：{exc}", file=sys.stderr)
        return 1

    ordered = sorted(page.resources, key=lambda item: 0 if urlsplit(item).path.endswith((".js", ".css")) else 1)
    queue = deque((resource, final_url) for resource in ordered) if args.assets else deque()
    seen = {url, final_url}
    attempts = 0
    while queue and attempts < args.max_resources:
        resource, referer = queue.popleft()
        if resource in seen:
            continue
        seen.add(resource)
        attempts += 1
        time.sleep(args.delay)
        try:
            data, actual_url, kind, encoding, code = fetch(resource, args.timeout, args.max_bytes, referer)
            suffix = Path(urlsplit(actual_url).path).suffix
            if not re.fullmatch(r"\.[a-zA-Z0-9]{1,8}", suffix):
                suffix = {"text/html": ".html", "text/css": ".css", "application/javascript": ".js", "text/javascript": ".js"}.get(kind, ".bin")
            relative = "resources/" + hashlib.sha256(resource.encode()).hexdigest() + suffix
            target = output / relative
            target.parent.mkdir(exist_ok=True)
            target.write_bytes(data)
            manifest["resources"].append({"url": resource, "final_url": actual_url, "file": relative, "content_type": kind, "status": code, "bytes": len(data)})
            discovered = []
            if kind in ("text/html", "application/xhtml+xml"):
                nested = PageParser(actual_url)
                nested.feed(data.decode(encoding, errors="replace"))
                discovered = nested.resources
            elif kind == "text/css":
                css = data.decode(encoding, errors="replace")
                matches = re.findall(r"url\(\s*['\"]?([^'\"\)]+?)['\"]?\s*\)", css)
                matches += re.findall(r"@import\s+['\"]([^'\"]+)['\"]", css)
                discovered = [urldefrag(urljoin(actual_url, item.strip()))[0] for item in matches]
            queue.extend((item, actual_url) for item in discovered if urlsplit(item).scheme in ("http", "https") and item not in seen)
            print(f"[{attempts}/{args.max_resources}] {kind}: {resource}")
        except (OSError, URLError, ValueError, LookupError) as exc:
            manifest["errors"].append({"url": resource, "error": str(exc)})
            print(f"资源失败：{resource}: {exc}", file=sys.stderr)
            # 访问受限时停止继续发出资源请求。
            if isinstance(exc, HTTPError) and exc.code in (401, 403, 429):
                manifest["stopped_reason"] = f"HTTP {exc.code}"
                break
    manifest["skipped"] = list(dict.fromkeys(item for item, _ in queue if item not in seen))
    write_json(output / "manifest.json", manifest)
    print(f"结果目录：{output.resolve()}")
    print(f"资源成功 {len(manifest['resources'])}，失败 {len(manifest['errors'])}，未下载 {len(manifest['skipped'])}")
    return 2 if manifest["errors"] or manifest["skipped"] else 0


if __name__ == "__main__":
    sys.exit(main())
