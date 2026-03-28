#!/bin/bash
###############################################################################
# Lab 7 Test: RBAC, Security, and IRSA
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/../lab-07" && pwd)"
source "$SCRIPT_DIR/lib.sh"

export STUDENT_NAME="test-$$"
NS="lab07-$STUDENT_NAME"
NS_RESTRICTED="lab07-restricted-$STUDENT_NAME"
NS_IRSA="lab07-irsa-$STUDENT_NAME"
echo "=== Lab 7: RBAC & Security (ns: $NS) ==="
echo ""

kubectl create namespace "$NS" &>/dev/null

# ─── RBAC ───────────────────────────────────────────────────────────────────

echo "RBAC:"
envsubst < "$LAB_DIR/pod-reader-role.yaml" | kubectl apply -f - &>/dev/null
kubectl create serviceaccount pod-viewer -n "$NS" &>/dev/null
envsubst < "$LAB_DIR/pod-reader-binding.yaml" | kubectl apply -f - &>/dev/null

# Test can-i
CAN_GET=$(kubectl auth can-i get pods -n "$NS" \
  --as="system:serviceaccount:${NS}:pod-viewer" 2>/dev/null)
assert_eq "pod-viewer can get pods" "yes" "$CAN_GET"

CAN_CREATE=$(kubectl auth can-i create deployments -n "$NS" \
  --as="system:serviceaccount:${NS}:pod-viewer" 2>/dev/null)
assert_eq "pod-viewer cannot create deployments" "no" "$CAN_CREATE"

CAN_DELETE=$(kubectl auth can-i delete pods -n "$NS" \
  --as="system:serviceaccount:${NS}:pod-viewer" 2>/dev/null)
assert_eq "pod-viewer cannot delete pods" "no" "$CAN_DELETE"

# ─── ClusterRole ────────────────────────────────────────────────────────────

echo ""
echo "ClusterRole:"
envsubst < "$LAB_DIR/cluster-reader-role.yaml" | kubectl apply -f - &>/dev/null
kubectl create serviceaccount cluster-viewer -n "$NS" &>/dev/null
envsubst < "$LAB_DIR/cluster-reader-binding.yaml" | kubectl apply -f - &>/dev/null

CAN_LIST=$(kubectl auth can-i list pods -n kube-system \
  --as="system:serviceaccount:${NS}:cluster-viewer" 2>/dev/null)
assert_eq "cluster-viewer can list pods in kube-system" "yes" "$CAN_LIST"

CAN_DELETE_SYS=$(kubectl auth can-i delete pods -n kube-system \
  --as="system:serviceaccount:${NS}:cluster-viewer" 2>/dev/null)
assert_eq "cluster-viewer cannot delete pods in kube-system" "no" "$CAN_DELETE_SYS"

# ─── Pod Security Standards ────────────────────────────────────────────────

echo ""
echo "Pod Security Standards:"
kubectl create namespace "$NS_RESTRICTED" &>/dev/null
kubectl label namespace "$NS_RESTRICTED" \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest &>/dev/null

# Privileged pod should be rejected
PRIV_RESULT=$(envsubst < "$LAB_DIR/privileged-pod.yaml" | kubectl apply -f - 2>&1)
assert_contains "privileged pod rejected" "$PRIV_RESULT" "forbidden"

# Root pod should be rejected
ROOT_RESULT=$(envsubst < "$LAB_DIR/root-pod.yaml" | kubectl apply -f - 2>&1)
assert_contains "root pod rejected" "$ROOT_RESULT" "forbidden"

# Secure pod should succeed
envsubst < "$LAB_DIR/secure-pod.yaml" | kubectl apply -f - &>/dev/null
wait_for_pod "$NS_RESTRICTED" secure-app 60

ID_OUTPUT=$(kubectl exec secure-app -n "$NS_RESTRICTED" -- id 2>/dev/null)
assert_contains "secure pod runs as uid 1000" "$ID_OUTPUT" "uid=1000"

TOUCH_RESULT=$(kubectl exec secure-app -n "$NS_RESTRICTED" -- touch /test-file 2>&1)
assert_contains "root filesystem is read-only" "$TOUCH_RESULT" "Read-only file system"

assert_cmd "tmp is writable" kubectl exec secure-app -n "$NS_RESTRICTED" -- touch /tmp/test-file

# ─── IRSA ───────────────────────────────────────────────────────────────────

echo ""
echo "IRSA:"
if aws s3 ls s3://platform-lab-irsa-demo/ &>/dev/null; then
  kubectl create namespace "$NS_IRSA" &>/dev/null
  pass "IRSA demo bucket accessible"
else
  skip "IRSA demo bucket not accessible — skipping IRSA tests"
fi

# ─── Cleanup ────────────────────────────────────────────────────────────────

kubectl delete clusterrolebinding "cluster-pod-reader-binding-$STUDENT_NAME" &>/dev/null
kubectl delete clusterrole "cluster-pod-reader-$STUDENT_NAME" &>/dev/null
cleanup_ns "$NS"
cleanup_ns "$NS_RESTRICTED"
cleanup_ns "$NS_IRSA"
summary
