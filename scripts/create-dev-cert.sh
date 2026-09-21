#!/bin/bash
# 一次性操作：创建自签名代码签名证书 "MyKit Dev"，放进专用钥匙串。
# 固定证书签名 → 每次重新编译后，"辅助功能"授权依然有效。
set -euo pipefail

KEYCHAIN="$HOME/Library/Keychains/mykit-dev.keychain-db"
KEYCHAIN_PASSWORD="mykit-dev"
IDENTITY="MyKit Dev"

if [[ -f "$KEYCHAIN" ]]; then
  echo "签名证书已存在：$KEYCHAIN（无需重复创建）"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.conf" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/identity.p12" -name "$IDENTITY" -passout "pass:$KEYCHAIN_PASSWORD"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"   # 不自动上锁
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$KEYCHAIN_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

echo "已创建签名证书 \"$IDENTITY\" → $KEYCHAIN"
