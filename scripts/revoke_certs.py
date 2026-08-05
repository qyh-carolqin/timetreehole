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
    # 需要清理的证书类型（iOS Development + Apple Development）
    cert_types = ["IOS_DEVELOPMENT", "DEVELOPMENT"]

    all_certs = []
    for ct in cert_types:
        print(f"🔍 查询 {ct} 证书...")
        data = api_request("GET", f"/certificates?filter[certificateType]={ct}&limit=200")
        if data is None:
            print(f"  ⚠️ 无法查询 {ct} 列表，跳过")
            continue
        certs = data.get("data", [])
        print(f"  找到 {len(certs)} 个")
        all_certs.extend(certs)

    if len(all_certs) == 0:
        print("  ✅ 无需清理证书")
    else:
        for cert in all_certs:
            cert_id = cert["id"]
            name = cert["attributes"]["name"]
            print(f"  ❌ 删除: {name} ({cert_id})")
            api_request("DELETE", f"/certificates/{cert_id}")

    print(f"\n🔍 查询所有描述文件...")
    data = api_request("GET", "/profiles?limit=200")
    if data is None:
        print("⚠️ 无法查询描述文件列表，跳过")
        return

    profiles = data.get("data", [])
    print(f"  找到 {len(profiles)} 个描述文件")

    auto_prefixes = ("iOS Team", "XC iOS", "match Development", "match AppStore")
    for p in profiles:
        pid = p["id"]
        name = p["attributes"]["name"]
        ptype = p["attributes"].get("profileType", "")
        # 删除 Xcode/Codemagic 自动生成的描述文件
        if any(name.startswith(prefix) for prefix in auto_prefixes) or ptype == "IOS_APP_DEVELOPMENT":
            print(f"  ❌ 删除: {name} ({pid})")
            api_request("DELETE", f"/profiles/{pid}")

    print("\n✅ 证书清理完成")

if __name__ == "__main__":
    main()
