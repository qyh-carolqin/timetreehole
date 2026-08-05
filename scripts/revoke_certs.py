#!/usr/bin/env python3
"""
每次 CI 构建前，清除所有 iOS 证书和描述文件。
解决 Codemagic 虚拟机每次重建导致旧证书私钥丢失的问题。

环境变量:
  APP_STORE_CONNECT_KEY_IDENTIFIER — Key ID
  APP_STORE_CONNECT_ISSUER_ID      — Issuer ID
  APP_STORE_CONNECT_KEY            — .p8 私钥内容
"""

import os, sys, time, json, jwt, urllib.request, urllib.error

KEY_ID    = os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"]
ISSUER_ID  = os.environ["APP_STORE_CONNECT_ISSUER_ID"]
PRIVATE_KEY = os.environ["APP_STORE_CONNECT_KEY"]

API_BASE = "https://api.appstoreconnect.apple.com/v1"

def make_jwt():
    payload = {
        "iss": ISSUER_ID,
        "iat": int(time.time()),
        "exp": int(time.time()) + 600,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, PRIVATE_KEY, algorithm="ES256")

def api_request(method, path):
    token = make_jwt()
    url = f"{API_BASE}{path}"
    req = urllib.request.Request(url, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read().decode()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        body = e.read().decode() if e.fp else ""
        print(f"  !! API 错误 {e.code}: {body}")
        return None

def main():
    print("=== 证书清理工具 (Key ID: {}) ===\n".format(KEY_ID))

    # ---------- 1. 删除所有 iOS 证书 ----------
    all_cert_types = [
        "IOS_DEVELOPMENT",
        "IOS_DISTRIBUTION",
        "DEVELOPMENT",
        "DISTRIBUTION",
    ]

    total_deleted = 0
    for ct in all_cert_types:
        print(f"查询 {ct} ...")
        data = api_request("GET", f"/certificates?filter[certificateType]={ct}&limit=200")
        if data is None:
            print(f"  (跳过 - API 调用失败)\n")
            continue
        certs = data.get("data", [])
        if not certs:
            print(f"  0 个，跳过\n")
            continue
        print(f"  找到 {len(certs)} 个:")
        for c in certs:
            cid = c["id"]
            name = c["attributes"].get("name", "?")
            serial = c["attributes"].get("serialNumber", "?")
            print(f"    删除: {name} (serial={serial})")
            api_request("DELETE", f"/certificates/{cid}")
            total_deleted += 1
        print()

    print(f"共删除 {total_deleted} 个证书\n")

    # ---------- 2. 删除所有描述文件 ----------
    print("查询所有描述文件...")
    data = api_request("GET", "/profiles?limit=200")
    if data is None:
        print("(跳过 - API 调用失败)\n")
    else:
        profiles = data.get("data", [])
        print(f"找到 {len(profiles)} 个")
        deleted_count = 0
        for p in profiles:
            pid = p["id"]
            name = p["attributes"].get("name", "?")
            ptype = p["attributes"].get("profileType", "?")
            state = p["attributes"].get("profileState", "?")
            print(f"    删除: {name} [{ptype}, {state}]")
            api_request("DELETE", f"/profiles/{pid}")
            deleted_count += 1
        print(f"共删除 {deleted_count} 个描述文件\n")

    print("=== 清理完成 ===")

if __name__ == "__main__":
    main()
