#!/bin/bash
###############################################################################
# Lab 12 Test: Helm and Templating
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

export STUDENT_NAME="test-$$"
NS="helm-lab-$STUDENT_NAME"
echo "=== Lab 12: Helm (ns: $NS) ==="
echo ""

kubectl create namespace "$NS" &>/dev/null

# ─── Helm basics ───────────────────────────────────────────────────────────

echo "Helm Basics:"
assert_cmd "helm version works" helm version --short

helm repo add bitnami https://charts.bitnami.com/bitnami &>/dev/null
helm repo update &>/dev/null
assert_cmd "bitnami repo added" helm repo list

SEARCH=$(helm search repo bitnami/nginx 2>/dev/null)
assert_contains "nginx chart found in bitnami" "$SEARCH" "bitnami/nginx"

# ─── Install a chart ───────────────────────────────────────────────────────

echo ""
echo "Chart Install:"
helm install lab-nginx bitnami/nginx -n "$NS" \
  --set replicaCount=2 \
  --set service.type=ClusterIP \
  --wait --timeout 120s &>/dev/null

RELEASE=$(helm list -n "$NS" --short 2>/dev/null)
assert_contains "release installed" "$RELEASE" "lab-nginx"

STATUS=$(helm status lab-nginx -n "$NS" -o json 2>/dev/null | jq -r '.info.status' 2>/dev/null)
assert_eq "release status is deployed" "deployed" "$STATUS"

REPLICAS=$(kubectl get deployment -n "$NS" -l app.kubernetes.io/instance=lab-nginx -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null)
assert_eq "nginx has 2 replicas" "2" "$REPLICAS"

# ─── Upgrade ───────────────────────────────────────────────────────────────

echo ""
echo "Chart Upgrade:"
helm upgrade lab-nginx bitnami/nginx -n "$NS" \
  --set replicaCount=3 \
  --set service.type=ClusterIP \
  --wait --timeout 120s &>/dev/null

REVISION=$(helm history lab-nginx -n "$NS" -o json 2>/dev/null | jq 'length' 2>/dev/null)
assert_eq "release at revision 2" "2" "$REVISION"

REPLICAS_UP=$(kubectl get deployment -n "$NS" -l app.kubernetes.io/instance=lab-nginx -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null)
assert_eq "upgraded to 3 replicas" "3" "$REPLICAS_UP"

# ─── Rollback ──────────────────────────────────────────────────────────────

echo ""
echo "Chart Rollback:"
helm rollback lab-nginx 1 -n "$NS" --wait &>/dev/null
sleep 10

REPLICAS_RB=$(kubectl get deployment -n "$NS" -l app.kubernetes.io/instance=lab-nginx -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null)
assert_eq "rolled back to 2 replicas" "2" "$REPLICAS_RB"

# ─── Custom chart ──────────────────────────────────────────────────────────

echo ""
echo "Custom Chart:"
TMPDIR=$(mktemp -d)
helm create "$TMPDIR/mychart" &>/dev/null
assert_cmd "chart scaffolded" test -f "$TMPDIR/mychart/Chart.yaml"
assert_cmd "helm lint passes" helm lint "$TMPDIR/mychart"

TEMPLATE=$(helm template "$TMPDIR/mychart" 2>/dev/null)
assert_contains "helm template renders deployment" "$TEMPLATE" "kind: Deployment"

helm package "$TMPDIR/mychart" -d "$TMPDIR" &>/dev/null
assert_cmd "chart packaged" ls "$TMPDIR"/mychart-*.tgz
rm -rf "$TMPDIR"

# ─── Cleanup ────────────────────────────────────────────────────────────────

helm uninstall lab-nginx -n "$NS" &>/dev/null
cleanup_ns "$NS"
summary
