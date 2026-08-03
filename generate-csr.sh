#!/usr/bin/env bash
# ============================================================
#  在 Windows/Linux 上生成 Apple 发布证书 (无需 Mac)
#  前提: 已安装 OpenSSL (Windows 可用 Git Bash 自带的 openssl)
#
#  用法:
#    bash generate-csr.sh your-email@example.com "Your Name"
#
#  产出:
#    1. ios_distribution.key        — 私钥 (保密!)
#    2. CertificateSigningRequest.certSigningRequest — CSR
#
#  后续步骤:
#    1. 登录 https://developer.apple.com → Certificates, IDs & Profiles
#    2. 点 + → 选 "Apple Distribution" → 上传 CSR 文件
#    3. 下载生成的 .cer 文件
#    4. 运行本脚本第二部分 (见下方注释) 合成 .p12
# ============================================================

set -e

EMAIL="${1:?用法: bash generate-csr.sh your-email@example.com \"Your Name\"}"
NAME="${2:?请提供你的姓名}"

echo "=========================================="
echo "  步骤 1/2: 生成密钥和 CSR"
echo "=========================================="

# 生成 RSA 2048 私钥 + CSR
openssl req -new -newkey rsa:2048 -nodes \
    -keyout ios_distribution.key \
    -out CertificateSigningRequest.certSigningRequest \
    -subj "/emailAddress=${EMAIL}/CN=${NAME}/C=CN"

echo ""
echo "✅ 已生成:"
echo "   - ios_distribution.key (私钥，保密!)"
echo "   - CertificateSigningRequest.certSigningRequest (CSR)"
echo ""
echo "=========================================="
echo "  接下来手动操作:"
echo "=========================================="
echo ""
echo "  1. 登录 https://developer.apple.com/account/resources/certificates/list"
echo "  2. 点 '+' → 选 'Apple Distribution' → Continue"
echo "  3. 上传 CertificateSigningRequest.certSigningRequest"
echo "  4. 下载 .cer 文件，重命名为 ios_distribution.cer"
echo "  5. 把 .cer 和 .key 放在同一目录"
echo "  6. 运行: bash generate-csr.sh --p12"
echo ""

# ============================================================
#  步骤 2: 合成 .p12 (下载 .cer 后运行)
# ============================================================
if [ "$1" = "--p12" ]; then
    echo "=========================================="
    echo "  步骤 2/2: 合成 .p12 证书"
    echo "=========================================="

    if [ ! -f "ios_distribution.cer" ]; then
        echo "❌ 找不到 ios_distribution.cer"
        echo "   请先从 Apple Developer 下载证书文件"
        exit 1
    fi

    if [ ! -f "ios_distribution.key" ]; then
        echo "❌ 找不到 ios_distribution.key"
        exit 1
    fi

    # .cer → .pem
    openssl x509 -in ios_distribution.cer -inform DER -out ios_distribution.pem -outform PEM

    # .pem + .key → .p12
    echo "请输入 .p12 密码 (记住这个密码，后面要用):"
    openssl pkcs12 -export \
        -inkey ios_distribution.key \
        -in ios_distribution.pem \
        -out ios_distribution.p12

    echo ""
    echo "✅ 已生成 ios_distribution.p12"
    echo ""
    echo "=========================================="
    echo "  转为 Base64 (用于 CI/CD Secrets):"
    echo "=========================================="
    echo ""

    if command -v base64 &> /dev/null; then
        echo "GitHub Actions Secret 值 (BUILD_CERTIFICATE_BASE64):"
        base64 -i ios_distribution.p12 | tr -d '\n'
        echo ""
        echo ""
        echo "本地验证: 已生成 ios_distribution.p12"
    else
        echo "手动运行: certutil -encode ios_distribution.p12 encoded.txt (Windows)"
        echo "然后复制 encoded.txt 中间部分 (去掉头尾标记)"
    fi
fi
