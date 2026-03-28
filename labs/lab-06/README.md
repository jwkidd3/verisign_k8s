# Lab 6: Ingress and Gateway API
### HTTP Routing, TLS Termination, and Egress Controls
**Intermediate Kubernetes — Module 6 of 13**

---

## Lab Overview

### What You Will Do

- Verify the Ingress controller and deploy sample applications
- Configure host-based and path-based routing with TLS
- Explore Ingress annotations (rewrite, rate limiting, CORS)
- Deploy Gateway API resources with HTTPRoute traffic splitting
- Configure egress NetworkPolicies to control outbound traffic

### Prerequisites

- Completion of Labs 1-5 with `kubectl` access
- Ingress controller installed (NGINX or AWS ALB)

> Steps 8-9 (Gateway API) require the Gateway API CRDs. If unavailable, read through as reference.

### Duration

Approximately 60 minutes

---

## Environment Setup

```bash
export STUDENT_NAME=<your-name>
echo "Student: $STUDENT_NAME"
```

---

## Step 1: Verify Ingress Controller and Create Namespace

```bash
# Check for NGINX Ingress Controller
kubectl get pods -n ingress-nginx

# Or check for AWS Load Balancer Controller
kubectl get pods -n kube-system \
  -l app.kubernetes.io/name=aws-load-balancer-controller

kubectl get ingressclass
```

> ⚠️ If no Ingress controller is found, notify the instructor.

```bash
kubectl create namespace lab06-$STUDENT_NAME

# Verify the Ingress controller service has an external IP/hostname
kubectl get svc -n ingress-nginx
```

---

## Step 2: Deploy Two Sample Applications

### Deploy app-v1

<!-- Creates a Deployment and Service for app v1 (http-echo) -->

Apply the manifest:

```bash
envsubst < app-v1.yaml | kubectl apply -f -
```

### Deploy app-v2

<!-- Creates a Deployment and Service for app v2 (http-echo) -->

Apply the manifest:

```bash
envsubst < app-v2.yaml | kubectl apply -f -
kubectl get pods -n lab06-$STUDENT_NAME -l app=web
kubectl get svc -n lab06-$STUDENT_NAME
```

> ✅ **Checkpoint:** 4 pods (2 for v1, 2 for v2) Running and 2 ClusterIP services.

---

## Step 3: Create a Host-Based Ingress

<!-- Creates an Ingress with host-based routing for v1 and v2 -->

Apply the manifest:

```bash
envsubst < ingress-host.yaml | kubectl apply -f -
```

---

## Step 4: Test Host-Based Routing

```bash
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Ingress address: $INGRESS_IP"

curl -s -H "Host: v1-$STUDENT_NAME.lab.local" http://$INGRESS_IP
curl -s -H "Host: v2-$STUDENT_NAME.lab.local" http://$INGRESS_IP
curl -s -H "Host: unknown.lab.local" http://$INGRESS_IP
```

> ✅ **Checkpoint:** v1 host returns `Hello from App V1`, v2 host returns `Hello from App V2`, unknown host returns 404.

> ⚠️ **AWS Note:** On EKS, use the hostname instead of IP. Allow 2-3 minutes for DNS propagation after LB creation.

---

## Step 5: Add Path-Based Routing

<!-- Creates an Ingress with path-based routing (/v1, /v2, /) -->

Apply the manifest:

```bash
envsubst < ingress-path.yaml | kubectl apply -f -

curl -s -H "Host: app-$STUDENT_NAME.lab.local" http://$INGRESS_IP/v1
curl -s -H "Host: app-$STUDENT_NAME.lab.local" http://$INGRESS_IP/v2
curl -s -H "Host: app-$STUDENT_NAME.lab.local" http://$INGRESS_IP/
```

> ✅ **Checkpoint:** `/v1` returns V1, `/v2` returns V2, `/` defaults to V1.

---

## Step 6: Configure TLS Termination

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout tls-ingress.key -out tls-ingress.crt \
    -subj "/CN=*.lab.local/O=Verisign Lab"

kubectl create secret tls lab-tls-secret \
    --cert=tls-ingress.crt --key=tls-ingress.key -n lab06-$STUDENT_NAME
```

<!-- Creates an Ingress with TLS termination and SSL redirect -->

Apply the manifest:

```bash
envsubst < ingress-tls.yaml | kubectl apply -f -

curl -sk -H "Host: secure-$STUDENT_NAME.lab.local" https://$INGRESS_IP
curl -sI -H "Host: secure-$STUDENT_NAME.lab.local" http://$INGRESS_IP
```

> ✅ **Checkpoint:** HTTPS returns `Hello from App V1`. HTTP returns a `308 Permanent Redirect` to HTTPS.

---

## Step 7: Explore Ingress Annotations

<!-- Creates an Ingress with rewrite, rate limiting, CORS, and custom headers -->

Apply the manifest:

```bash
envsubst < ingress-annotations.yaml | kubectl apply -f -

curl -s -H "Host: api-$STUDENT_NAME.lab.local" http://$INGRESS_IP/api/

# Check CORS and custom headers
curl -sI -H "Host: api-$STUDENT_NAME.lab.local" \
    -H "Origin: https://app.verisign.com" \
    http://$INGRESS_IP/api/ 2>&1 | grep -iE "access-control|X-Served"

# Test rate limiting
for i in $(seq 1 15); do
    curl -s -o /dev/null -w "%{http_code} " \
        -H "Host: api-$STUDENT_NAME.lab.local" http://$INGRESS_IP/api/
done
echo ""
```

> ✅ **Checkpoint:** CORS and custom headers appear. After 10 rapid requests, excess requests return `503`.

---

## Step 8: Gateway API -- GatewayClass and Gateway

```bash
kubectl get crd | grep gateway
```

> ⚠️ **If CRDs are not installed:**
> ```bash
> kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
> ```

<!-- Creates a GatewayClass and Gateway with HTTP and HTTPS listeners -->

Apply the manifest:

```bash
envsubst < gateway.yaml | kubectl apply -f -
kubectl get gateway -n lab06-$STUDENT_NAME
```

---

## Step 9: HTTPRoute for Traffic Splitting

<!-- Creates an HTTPRoute with 80/20 traffic split between v1 and v2 -->

Apply the manifest:

```bash
envsubst < httproute.yaml | kubectl apply -f -

GATEWAY_IP=$(kubectl get gateway lab-gateway -n lab06-$STUDENT_NAME \
    -o jsonpath='{.status.addresses[0].value}')

for i in $(seq 1 20); do
    curl -s -H "Host: app-$STUDENT_NAME.lab.local" http://$GATEWAY_IP
done | sort | uniq -c | sort -rn
```

> ✅ **Checkpoint:** Expect roughly 80/20 distribution between V1 and V2.

> ⚠️ If the Gateway controller is not running, use Ingress-based routing from earlier steps as fallback.

---

## Step 10: Configure Egress Controls with NetworkPolicy

```bash
kubectl run egress-test --image=busybox:1.36 \
    -n lab06-$STUDENT_NAME --restart=Never \
    --command -- sleep 3600

# Test outbound connectivity
kubectl exec egress-test -n lab06-$STUDENT_NAME -- \
    wget -qO- --timeout=5 http://app-v1-svc.lab06-$STUDENT_NAME.svc.cluster.local
kubectl exec egress-test -n lab06-$STUDENT_NAME -- \
    wget -qO- --timeout=5 http://example.com
```

### Apply Egress NetworkPolicy

<!-- Creates a NetworkPolicy restricting egress to DNS and in-namespace traffic -->

Apply the manifest:

```bash
envsubst < egress-policy.yaml | kubectl apply -f -

# Internal service access should work
kubectl exec egress-test -n lab06-$STUDENT_NAME -- \
    wget -qO- --timeout=5 http://app-v1-svc.lab06-$STUDENT_NAME.svc.cluster.local

# External access should be BLOCKED
kubectl exec egress-test -n lab06-$STUDENT_NAME -- \
    wget -qO- --timeout=5 http://example.com
```

> ✅ **Checkpoint:** Internal returns `Hello from App V1`. External times out.

> ⚠️ NetworkPolicy enforcement requires a compatible CNI (Calico, Cilium). Default AWS VPC CNI without a policy engine will accept but not enforce policies.

---

## Step 11: Clean Up

```bash
kubectl delete gatewayclass lab-gateway-class-$STUDENT_NAME --ignore-not-found
kubectl delete namespace lab06-$STUDENT_NAME

rm -f tls-ingress.key tls-ingress.crt
```

---

## Summary

- **Ingress:** Host-based and path-based routing, TLS termination with SSL redirect, controller-specific annotations for rewrite/rate-limiting/CORS
- **Gateway API:** Role-based separation (GatewayClass/Gateway/HTTPRoute), native traffic splitting via weighted `backendRefs`
- **Egress Controls:** NetworkPolicy egress rules restrict outbound traffic; always include a DNS exception (port 53) when restricting egress

---

*Lab 6 Complete — Up Next: Lab 7 — RBAC, Security, and IRSA*
