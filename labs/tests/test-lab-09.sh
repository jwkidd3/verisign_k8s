#!/bin/bash
###############################################################################
# Lab 9 Test: Observability
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/../lab-09" && pwd)"
source "$SCRIPT_DIR/lib.sh"

export STUDENT_NAME="test-$$"
NS="obs-lab-$STUDENT_NAME"
echo "=== Lab 9: Observability (ns: $NS) ==="
echo ""

kubectl create namespace "$NS" &>/dev/null
kubectl config set-context --current --namespace="$NS" &>/dev/null

# ─── Container logs ────────────────────────────────────────────────────────

echo "Container Logs:"
kubectl run log-generator --image=busybox:1.36 -n "$NS" --restart=Never \
  -- sh -c 'i=0; while true; do echo "INFO request_id=$i status=200"; i=$((i+1)); sleep 1; done' &>/dev/null
wait_for_pod "$NS" log-generator 60
sleep 3

LOGS=$(kubectl logs log-generator -n "$NS" --tail=5 2>/dev/null)
assert_contains "logs contain INFO messages" "$LOGS" "INFO"

LOGS_TS=$(kubectl logs log-generator -n "$NS" --timestamps --tail=3 2>/dev/null)
assert_contains "timestamps flag works" "$LOGS_TS" "Z "

# ─── Multi-container logs ──────────────────────────────────────────────────

echo ""
echo "Multi-Container Logs:"
envsubst < "$LAB_DIR/multi-container-app.yaml" | kubectl apply -f - &>/dev/null
wait_for_pod "$NS" multi-container-app 60
sleep 3

APP_LOG=$(kubectl logs multi-container-app -n "$NS" -c app --tail=3 2>/dev/null)
assert_contains "app container logs" "$APP_LOG" "APP"

SIDECAR_LOG=$(kubectl logs multi-container-app -n "$NS" -c sidecar --tail=3 2>/dev/null)
assert_contains "sidecar container logs" "$SIDECAR_LOG" "SIDECAR"

# ─── Metrics Server ────────────────────────────────────────────────────────

echo ""
echo "Metrics:"
if kubectl top nodes &>/dev/null; then
  pass "kubectl top nodes works"
else
  skip "metrics-server not responding"
fi

# ─── Prometheus ─────────────────────────────────────────────────────────────

echo ""
echo "Prometheus:"
if kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -q Running; then
  kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 18080:9090 &>/dev/null &
  PF_PID=$!
  sleep 3

  PROM_RESULT=$(curl -s "http://localhost:18080/api/v1/query" --data-urlencode 'query=up' 2>/dev/null)
  assert_contains "prometheus query returns results" "$PROM_RESULT" "success"

  kill $PF_PID &>/dev/null
else
  skip "prometheus not running"
fi

# ─── Grafana ────────────────────────────────────────────────────────────────

echo ""
echo "Grafana:"
if kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep -q Running; then
  kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 18081:80 &>/dev/null &
  PF_PID=$!
  sleep 3

  GF_RESULT=$(curl -s -u admin:admin "http://localhost:18081/api/datasources" 2>/dev/null)
  assert_contains "grafana API accessible" "$GF_RESULT" "Prometheus"

  DASH=$(curl -s -u admin:admin "http://localhost:18081/api/search" 2>/dev/null | jq 'length' 2>/dev/null)
  if [ "$DASH" -gt 0 ]; then
    pass "grafana has $DASH dashboards"
  else
    fail "no grafana dashboards found"
  fi

  kill $PF_PID &>/dev/null
else
  skip "grafana not running"
fi

# ─── PrometheusRule ─────────────────────────────────────────────────────────

echo ""
echo "Alerting:"
if kubectl get crd prometheusrules.monitoring.coreos.com &>/dev/null; then
  envsubst '$STUDENT_NAME' < "$LAB_DIR/prom-rule.yaml" | kubectl apply -f - &>/dev/null
  sleep 3
  RULE=$(kubectl get prometheusrule "pod-restart-alert-$STUDENT_NAME" -n monitoring --no-headers 2>/dev/null | wc -l | tr -d ' ')
  assert_eq "PrometheusRule created" "1" "$RULE"
  kubectl delete prometheusrule "pod-restart-alert-$STUDENT_NAME" -n monitoring &>/dev/null
else
  skip "PrometheusRule CRD not installed"
fi

# ─── Cleanup ────────────────────────────────────────────────────────────────

kubectl config set-context --current --namespace=default &>/dev/null
pkill -f "port-forward.*1808" &>/dev/null 2>&1 || true
cleanup_ns "$NS"
summary
