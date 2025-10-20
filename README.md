# KongOnK8S (OSS Hybrid with k3d + Helm)

## Structure
- db/cnpg/… — CloudNativePG operator objects (namespace, secret, postgres cluster)
- kong/cp/values.yaml — Control Plane Helm values (OSS)
- kong/dp/values.yaml — Data Plane Helm values (OSS)
- scripts/gen-certs.sh — generates hybrid clustering certs; creates secret kong/kong-cluster-cert

## Quickstart

### Install required tools
```bash
sudo apt-get update
sudo apt-get install -y curl git openssl jq
# kubectl
curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl
# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
# k3d (if not already present)
command -v k3d >/dev/null || curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
```

### Create k3d kubernetes cluster
```bash
# === 1) CLUSTER (k3d) ===
k3d cluster create kong -p "32080:32080@server:0"
kubectl cluster-info
kubectl config use-context k3d-kong
```

### Create Repo layout
```bash
# === 2) REPO LAYOUT (if not already) ===
cd ~/KongOnK8S
mkdir -p cluster kong/{cp,dp} scripts db/cnpg
```

### CNPG Operator (cloudnative postgres)
```bash
# === 3) CNPG OPERATOR (install once) ===
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update
helm upgrade --install cnpg cnpg/cloudnative-pg -n cnpg --create-namespace
kubectl -n cnpg get pods
```

### Generate cluster certs & kubernetes secret
```bash
# === 4) HYBRID CERTS (shared cert for dev) + SECRET ===
chmod +x scripts/gen-certs.sh
./scripts/gen-certs.sh
# Secret created: kong/kong-cluster-cert
```

### Database objects
```bash
# === 5) DATABASE OBJECTS (CNPG cluster in kong ns) ===
kubectl apply -k db/cnpg
# Wait until DB is ready:
kubectl -n kong get pods -w
# You should see kong-cp-db-1 -> 1/1 Running, and services kong-cp-db-rw / kong-cp-db-ro:
kubectl -n kong get svc
```

### Kong helm repo
```bash
# === 6) KONG HELM REPO ===
helm repo add kong https://charts.konghq.com
helm repo update
```

### Setup control plane
```bash
# === 7) CONTROL PLANE (OSS) ===
# Ensure kong/cp/values.yaml is present
helm upgrade --install kong-cp kong/kong -n kong -f kong/cp/values.yaml
kubectl -n kong get pods -w

# Quick CP check:
kubectl -n kong port-forward svc/kong-cp-kong-admin 8001:8001 &
sleep 2
curl -s http://localhost:8001/ | jq . || true
```

### Setup data plane
```bash
# === 8) DATA PLANE (OSS) ===
# Ensure kong/dp/values.yaml is present
helm upgrade --install kong-dp kong/kong -n kong -f kong/dp/values.yaml
kubectl -n kong get pods -w
```

### Test
```bash
# === 9) TEST (create route on CP, call through DP NodePort) ===
curl -s -X POST http://localhost:8001/services \
  -H 'content-type: application/json' \
  -d '{"name":"example","url":"http://httpbin.konghq.com"}' >/dev/null

curl -s -X POST http://localhost:8001/services/example/routes \
  -H 'content-type: application/json' \
  -d '{"name":"example-route","paths":["/anything"]}' >/dev/null

curl -i http://localhost:32080/anything
```

### Cleanup (Optional)
```bash
# === 10) CLEANUP (optional) ===
k3d cluster delete kong
```