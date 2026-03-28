# Lab 8: Network Policies
### Controlling Pod-to-Pod Communication with NetworkPolicy Resources
**Intermediate Kubernetes — Module 8 of 13**

---

## Lab Overview

### Objectives

- Deploy a three-tier application and verify default connectivity
- Apply a default-deny NetworkPolicy
- Create targeted ingress policies per tier
- Test allowed/blocked paths and egress controls

### Prerequisites

- Completed Labs 1-7 with kubectl access
- CNI with NetworkPolicy support (Calico or Cilium)

> **Duration:** ~45 minutes

---

## Environment Setup

```bash
export STUDENT_NAME=<your-name>
echo "Student: $STUDENT_NAME"
```

---

## Step 1: Deploy a Three-Tier Application

```bash
kubectl create namespace lab08-$STUDENT_NAME
```

### Deploy the Database Tier

<!-- Creates a database Pod and Service -->

Apply the manifest:

```bash
envsubst < database.yaml | kubectl apply -f -
```

### Deploy the Backend and Frontend Tiers

<!-- Creates backend and frontend Pods and Services -->

Apply the manifests:

```bash
envsubst < backend.yaml | kubectl apply -f -
envsubst < frontend.yaml | kubectl apply -f -

kubectl wait --for=condition=Ready pod --all -n lab08-$STUDENT_NAME --timeout=60s
kubectl get pods -n lab08-$STUDENT_NAME -o wide --show-labels
```

---

## Step 2: Verify Default Connectivity

Confirm all pods can communicate (all should succeed):

```bash
kubectl exec frontend -n lab08-$STUDENT_NAME -- \
  curl -s --max-time 3 http://backend.lab08-$STUDENT_NAME.svc.cluster.local:80

kubectl exec frontend -n lab08-$STUDENT_NAME -- \
  curl -s --max-time 3 http://database.lab08-$STUDENT_NAME.svc.cluster.local:80

kubectl exec database -n lab08-$STUDENT_NAME -- \
  curl -s --max-time 3 http://frontend.lab08-$STUDENT_NAME.svc.cluster.local:80
```

---

## Step 3: Apply Default Deny-All Ingress Policy

<!-- Creates a NetworkPolicy that denies all ingress traffic in the namespace -->

Apply the manifest:

```bash
envsubst < deny-all-ingress.yaml | kubectl apply -f -
```

---

## Step 4: Verify Isolation

```bash
# All should FAIL / timeout
kubectl exec frontend -n lab08-$STUDENT_NAME -- \
  curl -s --max-time 3 http://backend.lab08-$STUDENT_NAME.svc.cluster.local:80
echo "Exit code: $?"

kubectl exec backend -n lab08-$STUDENT_NAME -- \
  curl -s --max-time 3 http://database.lab08-$STUDENT_NAME.svc.cluster.local:80
echo "Exit code: $?"

kubectl exec database -n lab08-$STUDENT_NAME -- \
  curl -s --max-time 3 http://frontend.lab08-$STUDENT_NAME.svc.cluster.local:80
echo "Exit code: $?"
```

> ✅ **Checkpoint:** All curl commands timeout with a non-zero exit code.

---

## Step 5: Allow Frontend to Backend Communication

<!-- Creates a NetworkPolicy allowing ingress to backend from frontend on port 80 -->

Apply the manifest:

```bash
envsubst < allow-frontend-to-backend.yaml | kubectl apply -f -

# Frontend -> Backend (should now SUCCEED)
kubectl exec frontend -n lab08-$STUDENT_NAME -- \
  curl -s --max-time 3 http://backend.lab08-$STUDENT_NAME.svc.cluster.local:80

# Database -> Backend (should still FAIL)
kubectl exec database -n lab08-$STUDENT_NAME -- \
  curl -s --max-time 3 http://backend.lab08-$STUDENT_NAME.svc.cluster.local:80
```

> ✅ **Checkpoint:** Frontend to backend succeeds; database to backend times out.

---

## Step 6: Allow Backend to Database Communication

<!-- Creates a NetworkPolicy allowing ingress to database from backend on port 80 -->

Apply the manifest:

```bash
envsubst < allow-backend-to-database.yaml | kubectl apply -f -

# Backend -> Database (should now SUCCEED)
kubectl exec backend -n lab08-$STUDENT_NAME -- \
  curl -s --max-time 3 http://database.lab08-$STUDENT_NAME.svc.cluster.local:80

# Frontend -> Database (should still FAIL)
kubectl exec frontend -n lab08-$STUDENT_NAME -- \
  curl -s --max-time 3 http://database.lab08-$STUDENT_NAME.svc.cluster.local:80
```

> ✅ **Checkpoint:** Backend to database succeeds; frontend to database times out.

---

## Step 7: Test the Complete Policy Set

```bash
echo "=== ALLOWED PATHS ==="
echo -n "Frontend -> Backend: "
kubectl exec frontend -n lab08-$STUDENT_NAME -- curl -s -o /dev/null \
  -w "%{http_code}" --max-time 3 \
  http://backend:80 2>/dev/null || echo "BLOCKED"

echo -n "Backend -> Database: "
kubectl exec backend -n lab08-$STUDENT_NAME -- curl -s -o /dev/null \
  -w "%{http_code}" --max-time 3 \
  http://database:80 2>/dev/null || echo "BLOCKED"

echo ""
echo "=== BLOCKED PATHS ==="
echo -n "Frontend -> Database: "
kubectl exec frontend -n lab08-$STUDENT_NAME -- curl -s -o /dev/null \
  -w "%{http_code}" --max-time 3 \
  http://database:80 2>/dev/null || echo "BLOCKED"

echo -n "Database -> Frontend: "
kubectl exec database -n lab08-$STUDENT_NAME -- curl -s -o /dev/null \
  -w "%{http_code}" --max-time 3 \
  http://frontend:80 2>/dev/null || echo "BLOCKED"

echo -n "Database -> Backend: "
kubectl exec database -n lab08-$STUDENT_NAME -- curl -s -o /dev/null \
  -w "%{http_code}" --max-time 3 \
  http://backend:80 2>/dev/null || echo "BLOCKED"
```

> ✅ **Checkpoint:** Frontend->Backend: 200, Backend->Database: 200, all others: BLOCKED.

---

## Step 8: Add Egress Rules

<!-- Creates a NetworkPolicy that denies all egress traffic -->

Apply the manifest:

```bash
envsubst < deny-all-egress.yaml | kubectl apply -f -

# DNS is now broken — curl will fail to resolve
kubectl exec frontend -n lab08-$STUDENT_NAME -- \
  curl -s --max-time 3 http://backend.lab08-$STUDENT_NAME.svc.cluster.local:80 || echo "BLOCKED"
```

### Allow DNS and In-Namespace Egress

<!-- Creates a NetworkPolicy allowing DNS (port 53) and in-namespace egress (port 80) -->

Apply the manifest:

```bash
envsubst < allow-dns-egress.yaml | kubectl apply -f -

# Verify DNS resolves and traffic flows again
kubectl exec frontend -n lab08-$STUDENT_NAME -- \
  curl -s --max-time 3 http://backend.lab08-$STUDENT_NAME.svc.cluster.local:80
```

> ✅ **Checkpoint:** DNS works again and the frontend-to-backend path is restored. The egress policy allows DNS (port 53) and in-namespace traffic (port 80).

---

## Step 9: Test Namespace-Based Policies

```bash
kubectl create namespace monitoring-$STUDENT_NAME
kubectl label namespace monitoring-$STUDENT_NAME purpose=monitoring
kubectl run monitor --image=nginx:1.25 -n monitoring-$STUDENT_NAME
kubectl wait --for=condition=Ready pod/monitor -n monitoring-$STUDENT_NAME --timeout=60s

# Monitor cannot reach backend (denied by default)
kubectl exec monitor -n monitoring-$STUDENT_NAME -- \
  curl -s --max-time 3 http://backend.lab08-$STUDENT_NAME.svc.cluster.local:80
```

Allow monitoring namespace access:

<!-- Creates a NetworkPolicy allowing ingress from the monitoring namespace -->

Apply the manifest:

```bash
envsubst < allow-monitoring-ingress.yaml | kubectl apply -f -

kubectl exec monitor -n monitoring-$STUDENT_NAME -- \
  curl -s --max-time 3 http://backend.lab08-$STUDENT_NAME.svc.cluster.local:80
```

> ✅ **Checkpoint:** Monitoring pod can now reach application pods.

---

## Step 10: Debug a Broken Policy

Apply this intentionally broken policy and find the bugs:

<!-- Creates a NetworkPolicy with two intentional bugs for debugging practice -->

Apply the manifest:

```bash
envsubst < broken-policy.yaml | kubectl apply -f -
kubectl run test-client --image=nginx:1.25 -n lab08-$STUDENT_NAME --rm -it \
  --restart=Never -- curl -s --max-time 3 \
  http://frontend.lab08-$STUDENT_NAME.svc.cluster.local:80
```

> ⚠️ **Two bugs:** (1) `from.podSelector` matches `tier: frontend` (self-referencing) -- should be `from: []` to allow all sources. (2) Port is `8080` but frontend listens on `80`.

### Fix the Broken Policy

<!-- Creates the corrected NetworkPolicy (from: [] and port: 80) -->

Apply the manifest:

```bash
envsubst < fixed-policy.yaml | kubectl apply -f -
kubectl run test-client --image=nginx:1.25 \
  -n lab08-$STUDENT_NAME --rm -it --restart=Never -- \
  curl -s --max-time 3 \
  http://frontend.lab08-$STUDENT_NAME.svc.cluster.local:80
```

> ✅ **Checkpoint:** The test client can now reach the frontend.

---

## Step 11: Clean Up

```bash
kubectl delete namespace lab08-$STUDENT_NAME
kubectl delete namespace monitoring-$STUDENT_NAME
```

---

## Summary

- Kubernetes defaults to allowing all pod-to-pod communication -- NetworkPolicies add restrictions
- Start with a default deny-all policy, then selectively allow required traffic
- NetworkPolicies are additive -- multiple policies combine their allowed paths
- Always allow DNS (UDP/TCP port 53) when implementing egress policies
- Use `namespaceSelector` with namespace labels for cross-namespace communication

---

*Lab 8 Complete — Up Next: Lab 9 — Observability*
