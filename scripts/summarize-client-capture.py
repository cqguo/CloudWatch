#!/usr/bin/env python3
"""Read a local Proxyman HAR and export only safe playback diagnostics.

Never replays requests or exports cookies, device IDs, or full media URLs.
EAPI envelope decoding follows the publicly documented AES-128-ECB format.
"""
import base64
import gzip
import json
import subprocess
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlsplit


def decrypt(raw):
    result = subprocess.run(
        ["openssl", "enc", "-d", "-aes-128-ecb", "-K", b"e82ckenh8dichen8".hex()],
        input=raw, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
    )
    return result.stdout


def response(entry):
    content = entry["response"].get("content", {})
    raw = content.get("text", "").encode()
    if content.get("encoding") == "base64":
        raw = base64.b64decode(raw)
    try:
        return json.loads(raw)
    except (ValueError, UnicodeError):
        raw = decrypt(raw)
        if raw.startswith(b"\x1f\x8b"):
            raw = gzip.decompress(raw)
        return json.loads(raw)


def request(entry):
    body = entry["request"].get("postData", {})
    params = {x["name"]: x["value"] for x in body.get("params", [])}
    if not params:
        params = {k: v[0] for k, v in parse_qs(body.get("text", "")).items()}
    plain = decrypt(bytes.fromhex(params["params"])).decode()
    return json.loads(plain.split("-36cd479b6b5-")[1])


def main():
    entries = json.loads(Path(sys.argv[1]).read_text())["log"]["entries"]
    names = {}
    for entry in entries:
        if urlsplit(entry["request"]["url"]).path != "/eapi/v3/discovery/recommend/songs":
            continue
        for song in response(entry).get("data", {}).get("dailySongs", []):
            names[str(song["id"])] = song["name"]
    results = []
    for entry in entries:
        url = urlsplit(entry["request"]["url"])
        if url.path != "/eapi/song/enhance/player/url/v1":
            continue
        req, res = request(entry), response(entry)
        for song in res.get("data", []):
            results.append({
                "song": names.get(str(song.get("id")), "unknown"),
                "songId": song.get("id"),
                "time": entry.get("startedDateTime"),
                "endpoint": f"{url.scheme}://{url.netloc}{url.path}",
                "method": entry["request"]["method"],
                "httpStatus": entry["response"]["status"],
                "requestFields": sorted(req),
                "request": {k: req[k] for k in ("ids", "level", "encodeType", "immerseType", "e_r", "os", "trialMode") if k in req},
                "cookieHeaderPresent": any(h["name"].lower() == "cookie" for h in entry["request"].get("headers", [])),
                "response": {k: song[k] for k in ("code", "br", "fee", "size", "type", "level", "freeTrialInfo", "time") if k in song},
                "hasAudioURL": bool(song.get("url")),
                "audioHost": urlsplit(song.get("url") or "").hostname,
            })
    Path(sys.argv[2]).write_text(json.dumps({"client": "NeteaseMusic 3.1.7", "results": results}, ensure_ascii=False, indent=2))
    print(f"Exported {len(results)} sanitized audio responses.")


if __name__ == "__main__":
    main()
