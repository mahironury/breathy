#!/bin/bash
# Breathy için yerel kod imzalama sertifikası oluşturur. Bir kez çalıştırman yeter.
#
# Neden: Geçici (ad-hoc) imza her derlemede değişir, macOS da Tam Disk Erişimi
# iznini unutur. Sabit bir sertifikayla imzalayınca izin kalıcı olur.
# Sertifika sadece bu Mac'teki giriş anahtar zincirine eklenir, hiçbir yere gönderilmez.
set -euo pipefail

NAME="Breathy Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "✓ Sertifika zaten var: $NAME"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage         = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null

PASS="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" pkcs12 -export -name "$NAME" \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/identity.p12" -passout "pass:$PASS"

security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "✓ Oluşturuldu: $NAME"
