#!/bin/bash
###############################################################################
# Platform Prerequisites Test
# Verifies tools, cluster access, and platform components
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

echo "=== Platform Prerequisites ==="
echo ""

# ─── Tools ──────────────────────────────────────────────────────────────────

echo "Tools:"
assert_cmd "kubectl installed" kubectl version --client
assert_cmd "helm installed" helm version --short
assert_cmd "flux installed" flux version --client
assert_cmd "argocd installed" argocd version --client
assert_cmd "jq installed" jq --version
assert_cmd "envsubst installed" envsubst --version
assert_cmd "git installed" git --version
assert_cmd "docker installed" docker --version
assert_cmd "aws cli installed" aws --version

# ─── Cluster Access ─────────────────────────────────────────────────────────

echo ""
echo "Cluster Access:"

CLUSTER_INFO=$(kubectl cluster-info 2>&1)
assert_contains "kubectl can reach cluster" "$CLUSTER_INFO" "is running at"

NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$NODES" -gt 0 ]; then
  pass "cluster has $NODES node(s)"
else
  fail "no nodes found"
fi

NODE_STATUS=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | sort -u)
assert_eq "all nodes Ready" "Ready" "$NODE_STATUS"

# ─── Platform Components ────────────────────────────────────────────────────

echo ""
echo "Platform Components:"

# Metrics Server
MS_PODS=$(kubectl get pods -n kube-system -l k8s-app=metrics-server --no-headers 2>/dev/null | grep -c Running || true)
if [ "$MS_PODS" -gt 0 ]; then
  pass "metrics-server running"
else
  skip "metrics-server not found (labs 1,2,9 may have limited functionality)"
fi

# Calico / Cilium
if kubectl get installation default &>/dev/null; then
  pass "calico installed"
elif kubectl get pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null | grep -q Running; then
  pass "cilium installed"
else
  skip "no CNI with NetworkPolicy support detected (labs 6,8 may fail)"
fi

# Ingress NGINX
INGRESS_PODS=$(kubectl get pods -n ingress-nginx --no-headers 2>/dev/null | grep -c Running || true)
if [ "$INGRESS_PODS" -gt 0 ]; then
  pass "ingress-nginx running ($INGRESS_PODS pods)"
else
  skip "ingress-nginx not found (lab 6 may fail)"
fi

# Envoy Gateway
if kubectl get pods -n envoy-gateway-system --no-headers 2>/dev/null | grep -q Running; then
  pass "envoy-gateway running"
else
  skip "envoy-gateway not found (lab 6 gateway section may fail)"
fi

# Gateway API CRDs
if kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null; then
  pass "gateway API CRDs installed"
else
  skip "gateway API CRDs not found"
fi

# Prometheus stack
PROM_PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -c Running || true)
if [ "$PROM_PODS" -gt 0 ]; then
  pass "prometheus running"
else
  skip "prometheus not found (lab 9 may fail)"
fi

GRAFANA_PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep -c Running || true)
if [ "$GRAFANA_PODS" -gt 0 ]; then
  pass "grafana running"
else
  skip "grafana not found (lab 9 may fail)"
fi

# Kyverno
if kubectl get pods -n kyverno --no-headers 2>/dev/null | grep -q Running; then
  pass "kyverno running"
else
  skip "kyverno not found"
fi

# ArgoCD
ARGO_PODS=$(kubectl get pods -n argocd --no-headers 2>/dev/null | grep -c Running || true)
if [ "$ARGO_PODS" -gt 0 ]; then
  pass "argocd running ($ARGO_PODS pods)"
else
  skip "argocd not found (lab 13 may fail)"
fi

# Flux
FLUX_PODS=$(kubectl get pods -n flux-system --no-headers 2>/dev/null | grep -c Running || true)
if [ "$FLUX_PODS" -gt 0 ]; then
  pass "flux running ($FLUX_PODS pods)"
else
  skip "flux not found (lab 13 may fail)"
fi

# Vault
if kubectl get pods -n vault --no-headers 2>/dev/null | grep -q Running; then
  pass "vault running"
  VAULT_STATUS=$(kubectl exec -n vault vault-0 -- vault status -format=json 2>/dev/null | jq -r '.sealed' 2>/dev/null || echo "unknown")
  assert_eq "vault unsealed" "false" "$VAULT_STATUS"
else
  skip "vault not found (lab 5 may fail)"
fi

# External Secrets Operator
if kubectl get pods -n external-secrets --no-headers 2>/dev/null | grep -q Running; then
  pass "external-secrets-operator running"
else
  skip "external-secrets-operator not found (lab 5 ESO section may fail)"
fi

# ClusterSecretStore
if kubectl get clustersecretstore vault-backend &>/dev/null; then
  pass "vault ClusterSecretStore configured"
else
  skip "vault ClusterSecretStore not found"
fi

# IRSA demo bucket
BUCKET_CHECK=$(aws s3 ls s3://platform-lab-irsa-demo/ 2>&1)
if echo "$BUCKET_CHECK" | grep -q "test-file.txt"; then
  pass "IRSA demo S3 bucket accessible"
else
  skip "IRSA demo S3 bucket not accessible (lab 7 IRSA section may fail)"
fi

# StorageClasses
SC_COUNT=$(kubectl get storageclasses --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$SC_COUNT" -gt 0 ]; then
  pass "$SC_COUNT StorageClass(es) available"
else
  fail "no StorageClasses found"
fi

summary
