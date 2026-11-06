#!/usr/bin/env bash
# Private CA + one certificate per NATS server (used for client TLS and for
# mutually authenticated route TLS).
#
#   scripts/pki.sh            create what is missing; re-issue node certificates
#                             that expire within 30 days or whose SANs changed
#   scripts/pki.sh --renew    re-issue all node certificates (new keys)
#
# Then reload running servers (no restart, existing connections keep their
# session): docker compose kill -s SIGHUP nats-1 nats-2 nats-3
#
# Files (all gitignored):
#   certs/ca/ca.key           CA private key. Only needed to issue certificates:
#                             move it offline / into your PKI in production.
#   certs/ca/ca.crt           CA certificate: distribute to clients (public).
#   certs/nats-N/server.key   node private key (0600)
#   certs/nats-N/server.crt   node certificate, EKU serverAuth+clientAuth
#
# To use an existing PKI instead (Vault, step-ca, corporate CA), place PEM files
# at the same paths: per-node SANs nats-N, nats-N-cluster, localhost, 127.0.0.1
# (+ any external names) and both serverAuth and clientAuth EKUs.
SCRIPT_NAME=pki
# shellcheck source=scripts/lib.sh source-path=SCRIPTDIR
. "$(dirname "$0")/lib.sh"
require_cmd openssl

RENEW=0
while [ $# -gt 0 ]; do
  case "$1" in
    --renew) RENEW=1 ;;
    -h | --help)
      sed -n '2,23p' "$0"
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

CERT_DIR="$NATS_DIR/certs"
CA_DIR="$CERT_DIR/ca"
LEAF_DAYS="${NATS_TLS_LEAF_DAYS:-$(env_get NATS_TLS_LEAF_DAYS)}"
LEAF_DAYS="${LEAF_DAYS:-397}"
EXTRA_SANS="${NATS_TLS_EXTRA_SANS:-$(env_get NATS_TLS_EXTRA_SANS)}"

umask 077
mkdir -p "$CA_DIR"
chmod 700 "$CERT_DIR" "$CA_DIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat >"$WORK/openssl.cnf" <<'EOF'
[ req ]
distinguished_name = dn
prompt = no
[ dn ]
CN = placeholder
[ v3_ca ]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
EOF

# Replace the content of $2 in place (same inode), so containers that
# bind-mount the file see the new version after a reload.
install_file() {
  cat "$1" >"$2"
  chmod "$3" "$2"
}

if [ ! -s "$CA_DIR/ca.key" ] || [ ! -s "$CA_DIR/ca.crt" ]; then
  log "creating private CA (keep certs/ca/ca.key offline in production)"
  openssl ecparam -name prime256v1 -genkey -noout -out "$WORK/ca.key"
  openssl req -x509 -new -key "$WORK/ca.key" -sha256 -days 3650 \
    -config "$WORK/openssl.cnf" -extensions v3_ca \
    -subj "/O=PubSea/OU=NATS/CN=PubSea NATS internal CA" -out "$WORK/ca.crt"
  install_file "$WORK/ca.key" "$CA_DIR/ca.key" 600
  install_file "$WORK/ca.crt" "$CA_DIR/ca.crt" 644
fi
openssl x509 -checkend $((180 * 86400)) -noout -in "$CA_DIR/ca.crt" >/dev/null ||
  warn "the CA certificate expires within 180 days: plan a CA rotation (README)"

issued=0
for node in $NATS_NODES; do
  dir="$CERT_DIR/$node"
  mkdir -p "$dir"
  chmod 700 "$dir"
  sans="DNS:$node,DNS:$node-cluster,DNS:localhost,IP:127.0.0.1,IP:::1"
  if [ -n "$EXTRA_SANS" ]; then sans="$sans,$EXTRA_SANS"; fi

  if [ "$RENEW" = 0 ] && [ -s "$dir/server.crt" ] && [ -s "$dir/server.key" ] &&
    [ "$(cat "$dir/sans.txt" 2>/dev/null || true)" = "$sans" ] &&
    openssl verify -CAfile "$CA_DIR/ca.crt" "$dir/server.crt" >/dev/null 2>&1 &&
    openssl x509 -checkend $((30 * 86400)) -noout -in "$dir/server.crt" >/dev/null; then
    log "$node: certificate valid and unchanged (use --renew to force)"
    continue
  fi

  cat >"$WORK/$node.ext" <<EOF
[ v3_leaf ]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = $sans
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid, issuer
EOF
  openssl ecparam -name prime256v1 -genkey -noout -out "$WORK/$node.key"
  openssl req -new -key "$WORK/$node.key" -config "$WORK/openssl.cnf" \
    -subj "/O=PubSea/OU=NATS/CN=$node" -out "$WORK/$node.csr"
  openssl x509 -req -in "$WORK/$node.csr" -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" \
    -set_serial "0x$(openssl rand -hex 16)" -days "$LEAF_DAYS" -sha256 \
    -extfile "$WORK/$node.ext" -extensions v3_leaf -out "$WORK/$node.crt" 2>/dev/null
  install_file "$WORK/$node.key" "$dir/server.key" 600
  install_file "$WORK/$node.crt" "$dir/server.crt" 644
  printf '%s\n' "$sans" >"$dir/sans.txt"
  chmod 644 "$dir/sans.txt"
  log "$node: issued (expires $(openssl x509 -noout -enddate -in "$dir/server.crt" | cut -d= -f2)), SANs: $sans"
  issued=1
done

if [ "$issued" = 1 ] && [ -n "$(compose ps -q nats-1 nats-2 nats-3 2>/dev/null || true)" ]; then
  log "running servers detected; load the new certificates with:"
  log "  docker compose kill -s SIGHUP nats-1 nats-2 nats-3"
fi
