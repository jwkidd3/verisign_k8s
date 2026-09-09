#!/bin/bash
###############################################################################
# Lab 6 Test: Gateway API & Egress Policy
# Covers: app deployment, GatewayClass/Gateway (+ its own LB), weighted HTTPRoute,
#         path-based HTTPRoute, Gateway access (gated on LB reachability),
#         egress NetworkPolicy (the deny is deterministic and asserted).
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/../lab-06" && pwd)"
source "$SCRIPT_DIR/lib.sh"

export STUDENT_NAME="test-$$"
NS="lab06-$STUDENT_NAME"
echo "=== Lab 6: Gateway API & Egress (ns: $NS) ==="
echo ""

kubectl create namespace "$NS" &>/dev/null

# ─── Step 1: Deploy apps ──────────────────────────────────────────────────

echo "Step 1: Deploy Sample Applications"

envsubst '$STUDENT_NAME' < "$LAB_DIR/app-v1.yaml" | kubectl apply -f - &>/dev/null
envsubst '$STUDENT_NAME' < "$LAB_DIR/app-v2.yaml" | kubectl apply -f - &>/dev/null
wait_for_deploy "$NS" app-v1 90
wait_for_deploy "$NS" app-v2 90

V1_READY=$(kubectl get deployment app-v1 -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
assert_eq "app-v1 has 2 ready replicas" "2" "$V1_READY"

V2_READY=$(kubectl get deployment app-v2 -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
assert_eq "app-v2 has 2 ready replicas" "2" "$V2_READY"

assert_cmd "app-v1-svc exists" kubectl get svc app-v1-svc -n "$NS"
assert_cmd "app-v2-svc exists" kubectl get svc app-v2-svc -n "$NS"

# ─── Step 2: Gateway (GatewayClass + Gateway + its own LB) ─────────────────

echo ""
echo "Step 2: Gateway API"

if kubectl get crd gatewayclasses.gateway.networking.k8s.io &>/dev/null; then
  envsubst '$STUDENT_NAME' < "$LAB_DIR/gateway.yaml" | kubectl apply -f - &>/dev/null
  sleep 3

  assert_cmd "GatewayClass created" kubectl get gatewayclass "lab-gateway-class-$STUDENT_NAME"
  assert_cmd "Gateway created" kubectl get gateway lab-gateway -n "$NS"

  # Wait for the Gateway's own load balancer to be Programmed. Reachability is
  # probed after the first HTTPRoute is attached (below) — before that the
  # Gateway has no route and can only answer 404, so probing here could never
  # succeed and every access check degraded to a skip.
  kubectl wait --for=condition=Programmed gateway/lab-gateway -n "$NS" --timeout=120s &>/dev/null
  GW_ADDR=$(kubectl get gateway lab-gateway -n "$NS" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
  GW_REACHABLE=false

  # ── Step 3: weighted HTTPRoute (host-based 80/20) ──
  echo ""
  echo "Step 3: Weighted HTTPRoute"
  envsubst '$STUDENT_NAME' < "$LAB_DIR/httproute.yaml" | kubectl apply -f - &>/dev/null
  sleep 3
  assert_cmd "HTTPRoute app-route created" kubectl get httproute app-route -n "$NS"

  W_V1=$(kubectl get httproute app-route -n "$NS" -o jsonpath='{.spec.rules[0].backendRefs[0].weight}' 2>/dev/null)
  assert_eq "app-route v1 weight is 80" "80" "$W_V1"
  W_V2=$(kubectl get httproute app-route -n "$NS" -o jsonpath='{.spec.rules[0].backendRefs[1].weight}' 2>/dev/null)
  assert_eq "app-route v2 weight is 20" "20" "$W_V2"

  # Now that a route is attached, poll the LB until it serves (a fresh ELB can
  # take minutes). Only a genuinely unreachable LB degrades to skip.
  if [ -n "$GW_ADDR" ]; then
    for _i in $(seq 1 18); do
      code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
        -H "Host: app-$STUDENT_NAME.lab.local" "http://$GW_ADDR/" 2>/dev/null)
      [ "$code" = "200" ] && { GW_REACHABLE=true; break; }
      sleep 5
    done
  fi

  if [ "$GW_REACHABLE" = true ]; then
    GW_BODY=$(curl -s --max-time 8 -H "Host: app-$STUDENT_NAME.lab.local" "http://$GW_ADDR/" 2>/dev/null)
    assert_contains "Gateway routes to an app via its own LB" "$GW_BODY" "Hello from App"
    GW_404=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://$GW_ADDR/" 2>/dev/null)
    assert_eq "Gateway returns 404 without a matching Host" "404" "$GW_404"
  else
    skip "Gateway LB access (load balancer not reachable in window)"
    skip "Gateway 404-without-host (load balancer not reachable in window)"
  fi

  # ── Step 4: path-based HTTPRoute ──
  echo ""
  echo "Step 4: Path-Based HTTPRoute"
  envsubst '$STUDENT_NAME' < "$LAB_DIR/httproute-path.yaml" | kubectl apply -f - &>/dev/null
  sleep 3
  assert_cmd "HTTPRoute path-route created" kubectl get httproute path-route -n "$NS"

  P1=$(kubectl get httproute path-route -n "$NS" -o jsonpath='{.spec.rules[0].matches[0].path.value}' 2>/dev/null)
  assert_eq "path-route first match is /v1" "/v1" "$P1"
  P2=$(kubectl get httproute path-route -n "$NS" -o jsonpath='{.spec.rules[1].matches[0].path.value}' 2>/dev/null)
  assert_eq "path-route second match is /v2" "/v2" "$P2"

  if [ "$GW_REACHABLE" = true ]; then
    PB1=$(curl -s --max-time 8 -H "Host: path-$STUDENT_NAME.lab.local" "http://$GW_ADDR/v1" 2>/dev/null)
    assert_contains "path /v1 routes to App V1" "$PB1" "Hello from App V1"
    PB2=$(curl -s --max-time 8 -H "Host: path-$STUDENT_NAME.lab.local" "http://$GW_ADDR/v2" 2>/dev/null)
    assert_contains "path /v2 routes to App V2" "$PB2" "Hello from App V2"
  else
    skip "path /v1 routing (load balancer not reachable in window)"
    skip "path /v2 routing (load balancer not reachable in window)"
  fi

  # Clean up Gateway resources: delete the HTTPRoutes + Gateway first so Envoy
  # Gateway releases the gateway-exists finalizer on the GatewayClass.
  kubectl delete httproute app-route path-route -n "$NS" --ignore-not-found --timeout=60s &>/dev/null
  kubectl delete gateway lab-gateway -n "$NS" --ignore-not-found --timeout=60s &>/dev/null
  kubectl delete gatewayclass "lab-gateway-class-$STUDENT_NAME" --ignore-not-found --timeout=60s &>/dev/null
else
  skip "Gateway API CRD not installed — skipping Gateway tests"
fi

# ─── Step 5: Egress NetworkPolicy ──────────────────────────────────────────

echo ""
echo "Step 5: Egress NetworkPolicy"

envsubst '$STUDENT_NAME' < "$LAB_DIR/egress-policy.yaml" | kubectl apply -f - &>/dev/null
sleep 2

assert_cmd "egress policy exists" kubectl get networkpolicy restrict-egress -n "$NS"

EGRESS_SEL=$(kubectl get networkpolicy restrict-egress -n "$NS" \
  -o jsonpath='{.spec.podSelector.matchLabels.run}' 2>/dev/null)
assert_eq "egress policy selects run=egress-test" "egress-test" "$EGRESS_SEL"

EGRESS_TYPE=$(kubectl get networkpolicy restrict-egress -n "$NS" \
  -o jsonpath='{.spec.policyTypes[0]}' 2>/dev/null)
assert_eq "egress policy has Egress policyType" "Egress" "$EGRESS_TYPE"

DNS_PORT=$(kubectl get networkpolicy restrict-egress -n "$NS" \
  -o jsonpath='{.spec.egress[0].ports[0].port}' 2>/dev/null)
assert_eq "egress allows DNS on port 53" "53" "$DNS_PORT"

# Behavioral: external egress is denied once the policy exists (deterministic —
# the deny applies immediately; the "allowed" paths depend on CNI policy-vs-NAT
# ordering and aren't asserted here).
if kubectl get pods -n calico-system -l k8s-app=calico-node --no-headers 2>/dev/null | grep -q Running; then
  kubectl run egress-test --image=curlimages/curl --labels="run=egress-test" \
    -n "$NS" --restart=Never --command -- sleep 3600 &>/dev/null
  if wait_for_pod "$NS" egress-test 60; then
    if kubectl exec egress-test -n "$NS" -- curl -s --max-time 6 https://1.1.1.1/ &>/dev/null; then
      fail "external egress should be blocked by restrict-egress policy"
    else
      pass "external egress blocked by restrict-egress policy"
    fi
  else
    skip "egress-test pod not ready — external-block check"
  fi
  kubectl delete pod egress-test -n "$NS" --ignore-not-found &>/dev/null
else
  skip "CNI does not enforce NetworkPolicies — egress external-block check"
fi

# ─── Cleanup ──────────────────────────────────────────────────────────────

cleanup_ns "$NS"
summary
