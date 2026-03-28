#!/bin/bash
###############################################################################
# Lab 8 Test: Network Policies
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/../lab-08" && pwd)"
source "$SCRIPT_DIR/lib.sh"

export STUDENT_NAME="test-$$"
NS="lab08-$STUDENT_NAME"
echo "=== Lab 8: Network Policies (ns: $NS) ==="
echo ""

kubectl create namespace "$NS" &>/dev/null

# ─── Deploy three-tier app ─────────────────────────────────────────────────

echo "Three-Tier App:"
envsubst < "$LAB_DIR/database.yaml" | kubectl apply -f - &>/dev/null
envsubst < "$LAB_DIR/backend.yaml" | kubectl apply -f - &>/dev/null
envsubst < "$LAB_DIR/frontend.yaml" | kubectl apply -f - &>/dev/null
kubectl wait --for=condition=Ready pod --all -n "$NS" --timeout=90s &>/dev/null

PODS=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -c Running || true)
assert_eq "3 pods running" "3" "$PODS"

# ─── Default connectivity ──────────────────────────────────────────────────

echo ""
echo "Default Connectivity:"
RESULT=$(kubectl exec frontend -n "$NS" -- curl -s --max-time 5 "http://backend.${NS}.svc.cluster.local:80" 2>/dev/null)
assert_contains "frontend can reach backend (default)" "$RESULT" "nginx"

# ─── Default deny ──────────────────────────────────────────────────────────

echo ""
echo "Default Deny:"
envsubst < "$LAB_DIR/deny-all-ingress.yaml" | kubectl apply -f - &>/dev/null
sleep 3

kubectl exec frontend -n "$NS" -- curl -s --max-time 3 "http://backend.${NS}.svc.cluster.local:80" &>/dev/null
if [ $? -ne 0 ]; then
  pass "frontend to backend blocked after deny-all"
else
  fail "frontend to backend should be blocked"
fi

# ─── Selective allow ───────────────────────────────────────────────────────

echo ""
echo "Selective Allow:"
envsubst < "$LAB_DIR/allow-frontend-to-backend.yaml" | kubectl apply -f - &>/dev/null
sleep 3

F2B=$(kubectl exec frontend -n "$NS" -- curl -s --max-time 5 "http://backend.${NS}.svc.cluster.local:80" 2>/dev/null)
assert_contains "frontend to backend allowed" "$F2B" "nginx"

kubectl exec database -n "$NS" -- curl -s --max-time 3 "http://backend.${NS}.svc.cluster.local:80" &>/dev/null
if [ $? -ne 0 ]; then
  pass "database to backend still blocked"
else
  fail "database to backend should be blocked"
fi

envsubst < "$LAB_DIR/allow-backend-to-database.yaml" | kubectl apply -f - &>/dev/null
sleep 3

B2D=$(kubectl exec backend -n "$NS" -- curl -s --max-time 5 "http://database.${NS}.svc.cluster.local:80" 2>/dev/null)
assert_contains "backend to database allowed" "$B2D" "nginx"

kubectl exec frontend -n "$NS" -- curl -s --max-time 3 "http://database.${NS}.svc.cluster.local:80" &>/dev/null
if [ $? -ne 0 ]; then
  pass "frontend to database still blocked"
else
  fail "frontend to database should be blocked"
fi

# ─── Cleanup ────────────────────────────────────────────────────────────────

cleanup_ns "$NS"
summary
