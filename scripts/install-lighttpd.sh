#!/bin/bash
set -e
BASE="http://deb.debian.org/debian/pool/main"
mkdir -p /tmp/pihole-dl
cd /tmp/pihole-dl

echo "[*] Downloading lighttpd and deps..."

curl -sL "http://deb.debian.org/debian/pool/main/l/lighttpd/lighttpd_1.4.79-2_arm64.deb" -o lighttpd.deb
curl -sL "http://deb.debian.org/debian/pool/main/libx/libxxhash/libxxhash0_0.8.2-1+b1_arm64.deb" -o libxxhash0.deb
curl -sL "http://deb.debian.org/debian/pool/main/libp/libpcre2/libpcre2-8-0_10.43-1+b1_arm64.deb" -o libpcre2.deb
curl -sL "http://deb.debian.org/debian/pool/main/libn/libnettle/libnettle8t64_3.10-1+b1_arm64.deb" -o libnettle.deb
curl -sL "http://deb.debian.org/debian/pool/main/libc/glibc/libcrypt1t64_2.40-3_arm64.deb" -o libcrypt.deb
curl -sL "http://deb.debian.org/debian/pool/main/o/openssl/libssl3t64_3.0.16-1_arm64.deb" -o libssl.deb
curl -sL "http://deb.debian.org/debian/pool/main/o/openssl/libcrypto3t64_3.0.16-1_arm64.deb" -o libcrypto.deb

echo "[*] Packages downloaded:"
ls -lh *.deb

echo "[*] Installing with dpkg..."
sudo dpkg -i *.deb 2>&1 || true

echo "[*] Verifying:"
which lighttpd && lighttpd -v || echo "FAILED"

echo DONE
