#!/usr/bin/env bash
set -euo pipefail
mkdir -p .certs
# EC P-384, CN=kong_clustering
openssl ecparam -name secp384r1 -genkey -noout -out .certs/tls.key
openssl req -new -x509 -key .certs/tls.key -out .certs/tls.crt -days 1095 -subj "/CN=kong_clustering"
chmod 600 .certs/tls.key
kubectl -n kong delete secret kong-cluster-cert 2>/dev/null || true
kubectl create namespace kong 2>/dev/null || true
kubectl -n kong create secret tls kong-cluster-cert --cert=.certs/tls.crt --key=.certs/tls.key
echo "Secret kong/kong-cluster-cert created."
