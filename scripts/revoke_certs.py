#!/usr/bin/env python3
"""
每次 CI 构建前，通过 App Store Connect API 删除所有 iOS 开发证书。
解决 Codemagic 虚拟机每次重建导致旧证书私钥丢失的问题。

环境变量:
  APP_STORE_CONNECT_KEY_IDENTIFIER — Key ID
  APP_STORE_CONNECT_ISSUER_ID      — Issuer ID
  APP_STORE_CONNECT_KEY            — .p8 私钥内容
"""

import os, sys, time, json, jwt, urllib.request, urllib.error

KEY_ID   = os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"]
ISSUER_ID = os.environ["APP_STORE_CONNECT_ISSUER_ID"]
PRIVATE_KEY = os.environ["APP_STORE_CONNECT_KEY"]

API_BASE = "https://api.appstoreconnect.apple.com/v1"

def make_jwt():
    payload = {
        "iss": ISSUER_ID,
        "iat": int(time.time()),
        "exp": int(time.time()) + 600,  # 10 分钟有效期
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
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode() if e.fp else ""
        print(f"  API 错误 {e.code}: {body}")
        return None

def main():
    print("🔍 查询所有 iOS 开发证书...")
    data = api_request("GET", "/certificates?filter[certificateType]=IOS_DEVELOPMENT&limit=200")
    if data is None:
        print("⚠️ 无法查询证书列表，跳过")
        return

    certs = data.get("data", [])
    print(f"  找到 {len(certs)} 个 iOS 开发证书")

    for cert in certs:
        cert_id = cert["id"]
        name = cert["attributes"]["name"]
        print(f"  ❌ 删除: {name} ({cert_id})")
        api_request("DELETE", f"/certificates/{cert_id}")

    if len(certs) == 0:
        print("  ✅ 无需清理")

    # 也清理所有描述文件
    print("\n🔍 查询所有描述文件...")
    data = api_request("GET", "/profiles?limit=200")
    if data is None:
        print("⚠️ 无法查询描述文件列表，跳过")
        return

    profiles = data.get("data", [])
    print(f"  找到 {len(profiles)} 个描述文件")

    for p in profiles:
        pid = p["id"]
        name = p["attributes"]["name"]
        # 只清理以 "iOS Team" 开头的（Xcode 自动生成的）
        if name.startswith("iOS Team"):
            print(f"  ❌ 删除: {name} ({pid})")
            api_request("DELETE", f"/profiles/{pid}")

    print("\n✅ 证书清理完成")

if __name__ == "__main__":
    main()
