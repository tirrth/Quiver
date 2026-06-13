#!/bin/zsh
# Creates a self-signed local code-signing certificate ("Quiver Local Signing") in the login
# keychain, so every Quiver build is signed with the SAME identity. macOS ties the Accessibility
# grant to the signature, so a stable identity means you grant access once and it sticks across
# rebuilds (ad-hoc signing changes every build, which is why the prompt kept coming back).
#
# Run once:  ./scripts/setup-stable-signing.sh
set -euo pipefail

CN="Quiver Local Signing"

if security find-certificate -c "$CN" >/dev/null 2>&1; then
  echo "Signing identity \"$CN\" already exists."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cfg" <<EOF
[req]
distinguished_name=dn
x509_extensions=v3
prompt=no
[dn]
CN=$CN
[v3]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -config "$TMP/cfg" 2>/dev/null

# -legacy emits a PKCS12 that macOS `security import` accepts (OpenSSL 3 default is rejected).
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout pass:quiver 2>/dev/null

# -A lets codesign use the private key without a keychain prompt.
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P quiver -A

echo "Created signing identity \"$CN\". Rebuilds will now reuse it."
echo "Note: the first build after this changes the signature once more, so grant Accessibility one"
echo "last time — after that it persists."
