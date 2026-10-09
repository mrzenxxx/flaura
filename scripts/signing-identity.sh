#!/bin/zsh
# Prints the code-signing identity to use for Aura.app.
#
# macOS remembers privacy permissions (Input Monitoring) per code identity. An ad-hoc signature
# changes with every build, so the permission would silently stop working after each update.
# A local self-signed certificate keeps the identity stable across rebuilds.
#
#   scripts/signing-identity.sh           print the identity, creating it on first use
#   scripts/signing-identity.sh --adhoc   always print "-" (ad-hoc)
set -euo pipefail

NAME="Aura Local Signing"

if [[ "${1:-}" == "--adhoc" ]]; then
  echo "-"
  exit 0
fi

# Self-signed certificates are not trusted, so they only show up without -v.
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
  echo "$NAME"
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

if ! openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.conf" \
     -keyout "$WORK/key.pem" -out "$WORK/cert.pem" >/dev/null 2>&1; then
  echo "-"; exit 0
fi

# Older PBE algorithms: `security import` cannot read OpenSSL 3's default PKCS#12 encryption.
PASS=aura-local
if ! openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
     -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
     -out "$WORK/identity.p12" -passout "pass:$PASS" >/dev/null 2>&1; then
  echo "-"; exit 0
fi

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null 2>&1 \
   && security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
  echo "$NAME"
else
  echo "-"
fi
