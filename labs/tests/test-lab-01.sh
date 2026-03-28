#!/bin/bash
###############################################################################
# Lab 1 Test: Cluster Exploration
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

NS="lab01-test-$$"
echo "=== Lab 1: Cluster Exploration (ns: $NS) ==="
echo ""

# ─── Cluster navigation ────────────────────────────────────────────────────

echo "Cluster Navigation:"
NODES=$(kubectl get nodes -o wide --no-headers 2>/dev/null)
assert_contains "nodes listed with wide output" "$NODES" "Ready"

NS_LIST=$(kubectl get namespaces --no-headers 2>/dev/null)
assert_contains "namespaces listed" "$NS_LIST" "kube-system"

SYSTEM_PODS=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$SYSTEM_PODS" -gt 0 ]; then
  pass "kube-system has $SYSTEM_PODS pods"
else
  fail "no pods in kube-system"
fi

# ─── Deploy nginx ───────────────────────────────────────────────────────────

echo ""
echo "Application Deployment:"
kubectl create namespace "$NS" &>/dev/null
kubectl create deployment nginx-lab --image=nginx:1.25 --replicas=2 -n "$NS" &>/dev/null
kubectl expose deployment nginx-lab --port=80 --target-port=80 -n "$NS" &>/dev/null

wait_for_deploy "$NS" nginx-lab 90
READY=$(kubectl get deployment nginx-lab -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
assert_eq "deployment has 2 ready replicas" "2" "$READY"

SVC=$(kubectl get svc nginx-lab -n "$NS" -o jsonpath='{.spec.type}' 2>/dev/null)
assert_eq "service type is ClusterIP" "ClusterIP" "$SVC"

# ─── Pod inspection ─────────────────────────────────────────────────────────

echo ""
echo "Pod Inspection:"
POD=$(kubectl get pods -n "$NS" -l app=nginx-lab -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
DESCRIBE=$(kubectl describe pod "$POD" -n "$NS" 2>/dev/null)
assert_contains "pod describe shows container info" "$DESCRIBE" "nginx:1.25"

LOGS=$(kubectl logs "$POD" -n "$NS" --tail=5 2>&1)
assert_cmd "pod logs accessible" test -n "$LOGS"

EXEC_RESULT=$(kubectl exec "$POD" -n "$NS" -- curl -s localhost:80 2>/dev/null)
assert_contains "exec curl returns nginx welcome" "$EXEC_RESULT" "Welcome to nginx"

# ─── Scale ──────────────────────────────────────────────────────────────────

echo ""
echo "Scaling:"
kubectl scale deployment nginx-lab --replicas=5 -n "$NS" &>/dev/null
sleep 10
PODS_5=$(kubectl get pods -n "$NS" -l app=nginx-lab --no-headers 2>/dev/null | wc -l | tr -d ' ')
assert_eq "scaled to 5 pods" "5" "$PODS_5"

kubectl scale deployment nginx-lab --replicas=2 -n "$NS" &>/dev/null
sleep 10
PODS_2=$(kubectl get pods -n "$NS" -l app=nginx-lab --no-headers 2>/dev/null | grep -c Running || true)
assert_eq "scaled down to 2 pods" "2" "$PODS_2"

# ─── Cleanup ────────────────────────────────────────────────────────────────

cleanup_ns "$NS"
summary
