#!/bin/bash
###############################################################################
# Lab 13 Test: CI/CD and GitOps
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/../lab-13" && pwd)"
source "$SCRIPT_DIR/lib.sh"

export STUDENT_NAME="test-$$"
NS_CICD="cicd-lab-$STUDENT_NAME"
NS_FLUX="flux-lab-$STUDENT_NAME"
echo "=== Lab 13: CI/CD & GitOps (ns: $NS_CICD, $NS_FLUX) ==="
echo ""

# ─── Docker build ──────────────────────────────────────────────────────────

echo "Container Build:"
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
git init &>/dev/null

cat > index.html <<'HEREDOC'
<html><body><h1>CI/CD Test</h1><p>Build: TEST</p></body></html>
HEREDOC

cat > Dockerfile <<'HEREDOC'
FROM nginx:1.25-alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
HEREDOC

git add . && git commit -m "test" &>/dev/null
GIT_SHA=$(git rev-parse --short HEAD)

if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  docker build -t my-app:$GIT_SHA . &>/dev/null
  assert_cmd "image built with SHA tag" docker image inspect "my-app:$GIT_SHA"
else
  skip "docker not available or not running"
fi
cd - &>/dev/null
rm -rf "$TMPDIR"

# ─── ECR push ──────────────────────────────────────────────────────────────

echo ""
echo "ECR Integration:"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ -n "$AWS_ACCOUNT_ID" ]; then
  pass "AWS account accessible: $AWS_ACCOUNT_ID"
  ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.us-east-2.amazonaws.com"

  # Test ECR login (don't actually push)
  ECR_LOGIN=$(aws ecr get-login-password --region us-east-2 2>/dev/null | \
    docker login --username AWS --password-stdin "$ECR_REGISTRY" 2>&1 || true)
  if echo "$ECR_LOGIN" | grep -q "Login Succeeded"; then
    pass "ECR login succeeded"
  else
    skip "ECR login failed (docker may not be running)"
  fi
else
  skip "AWS account not accessible"
fi

# ─── kubectl deploy ────────────────────────────────────────────────────────

echo ""
echo "Kubernetes Deploy:"
kubectl create namespace "$NS_CICD" &>/dev/null
kubectl create deployment cicd-test --image=nginx:1.25 --replicas=2 -n "$NS_CICD" &>/dev/null
wait_for_deploy "$NS_CICD" cicd-test 90

READY=$(kubectl get deployment cicd-test -n "$NS_CICD" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
assert_eq "deployment has 2 replicas" "2" "$READY"

# ─── ArgoCD ─────────────────────────────────────────────────────────────────

echo ""
echo "ArgoCD:"
if kubectl get pods -n argocd --no-headers 2>/dev/null | grep -q Running; then
  pass "argocd pods running"
  assert_cmd "argocd CLI works" argocd version --client

  # Verify Application CRD exists
  assert_cmd "Application CRD exists" kubectl get crd applications.argoproj.io
else
  skip "argocd not running"
fi

# ─── FluxCD ─────────────────────────────────────────────────────────────────

echo ""
echo "FluxCD:"
if kubectl get pods -n flux-system --no-headers 2>/dev/null | grep -q Running; then
  pass "flux pods running"

  FLUX_CHECK=$(flux check 2>&1)
  assert_contains "flux check passes" "$FLUX_CHECK" "all checks passed"

  # Test HelmRepository creation
  kubectl create namespace "$NS_FLUX" &>/dev/null
  export ECR_REGISTRY="${ECR_REGISTRY:-placeholder}" ECR_REPO="test" GIT_SHA="test"
  envsubst < "$LAB_DIR/helm-source.yaml" | kubectl apply -f - &>/dev/null
  sleep 3

  HR=$(kubectl get helmrepository "bitnami-$STUDENT_NAME" -n flux-system --no-headers 2>/dev/null | wc -l | tr -d ' ')
  assert_eq "HelmRepository created" "1" "$HR"

  # Clean up flux resources
  kubectl delete helmrepository "bitnami-$STUDENT_NAME" -n flux-system &>/dev/null
else
  skip "flux not running"
fi

# ─── Cleanup ────────────────────────────────────────────────────────────────

docker rmi "my-app:$GIT_SHA" &>/dev/null 2>&1 || true
cleanup_ns "$NS_CICD"
cleanup_ns "$NS_FLUX"
summary
