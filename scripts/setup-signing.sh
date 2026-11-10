#!/usr/bin/env bash
# Creates a local, self-signed code-signing identity ("Kanpe Local Signing") in your login
# keychain. bundle.sh uses it automatically, so every rebuild keeps the same code identity and
# macOS keeps Kanpe's Accessibility permission (ad-hoc builds lose it on every rebuild).
#
# The certificate is only used to sign Kanpe on this Mac. To remove it later:
#   security delete-identity -c "Kanpe Local Signing" ~/Library/Keychains/login.keychain-db
set -euo pipefail

NAME="Kanpe Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "\"$NAME\" already exists. Nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null

# Throwaway password just for the transfer file; -legacy keeps it readable by `security import`.
PASS="kanpe-$RANDOM$RANDOM"
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/identity.p12" -passout "pass:$PASS" 2>/dev/null \
|| openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/identity.p12" -passout "pass:$PASS"

# -T lets codesign use the key without a keychain prompt on every build.
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "Created \"$NAME\" in your login keychain."
echo "Rebuild with scripts/bundle.sh, then grant Accessibility once more; it will stick from now on."
