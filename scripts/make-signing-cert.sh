#!/usr/bin/env bash
# One-time setup: makes a self-signed code-signing identity, "MacIsland Dev", in the login keychain. With it, bundle.sh signs every
# build the same way, so macOS keeps Accessibility and the other permissions across rebuilds instead of tying them to one build's hash.
# The first build runs this itself (sign.sh); running it by hand is only needed to make the identity ahead of time.
set -euo pipefail

NAME="MacIsland Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# macOS's own LibreSSL, not a Homebrew OpenSSL 3 earlier on the PATH: OpenSSL 3 writes PKCS#12 with algorithms `security import`
# can't read.
OPENSSL=/usr/bin/openssl

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
    echo "\"$NAME\" is already in the login keychain"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
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
CNF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
# LibreSSL's default PKCS#12 algorithms are ones `security import` reads; a throwaway password, since it can't take an empty one.
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/identity.p12" -passout pass:macisland
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P macisland -T /usr/bin/codesign >/dev/null

echo "Made \"$NAME\". Builds sign with it from now on: allow each permission once more and it sticks."
echo "macOS may ask once whether codesign may use the key: choose Always Allow."
