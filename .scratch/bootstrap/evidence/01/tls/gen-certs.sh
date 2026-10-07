#!/bin/sh
# Ticket 01 evidence: two unrelated CAs and two server certificates, all
# throwaway, written to <out-dir>. Uses whichever openssl is first on PATH
# (run.sh puts the pixi environment's first).
#   ca-a        signs both server certificates
#   ca-b        unrelated; a client trusting only ca-b must reject both
#   server      CA-A, SAN DNS:localhost and IP:127.0.0.1
#   server-dns  CA-A, SAN DNS:localhost only (proves the IP SAN is checked)
# Usage: sh gen-certs.sh <out-dir>
set -eu
out=${1:?usage: gen-certs.sh <out-dir>}
mkdir -p "$out"; cd "$out"
ca() {
  openssl req -x509 -newkey rsa:2048 -nodes -days 2 -keyout "$1.key" -out "$1.pem" \
    -subj "/CN=knarr ticket 01 $1" \
    -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign' 2>/dev/null
}
leaf() { # name, san
  openssl req -new -newkey rsa:2048 -nodes -keyout "$1.key" -out "$1.csr" -subj "/CN=$1" 2>/dev/null
  printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=%s\n' "$2" > "$1.ext"
  openssl x509 -req -in "$1.csr" -CA ca-a.pem -CAkey ca-a.key -CAcreateserial -days 2 -extfile "$1.ext" -out "$1.pem" 2>/dev/null
  rm -f "$1.csr" "$1.ext"
}
ca ca-a
ca ca-b
leaf server 'DNS:localhost,IP:127.0.0.1'
leaf server-dns 'DNS:localhost'
openssl verify -CAfile ca-a.pem server.pem server-dns.pem
openssl x509 -in server.pem -noout -ext subjectAltName
