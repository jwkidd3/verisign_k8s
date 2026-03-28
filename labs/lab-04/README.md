# Lab 4: Services and Service Discovery
### ClusterIP, NodePort, LoadBalancer, and DNS-Based Discovery
**Intermediate Kubernetes — Module 4 of 13**

---

## Lab Overview

### Objectives

- Deploy a multi-tier application
- Create ClusterIP, NodePort, and LoadBalancer Services
- Test DNS-based service discovery and examine Endpoints
- Configure headless Services and multi-port Services

### Prerequisites

- Completion of Labs 1-3 with `kubectl` access

> **Duration:** ~45-60 minutes

---

## Environment Setup

```bash
export STUDENT_NAME=<your-name>
echo "Student: $STUDENT_NAME"
```

> ⚠️ **Important:** This shared cluster is used by all 22 students. Your `$STUDENT_NAME` ensures your resources don't conflict with others.

---

## Step 1: Deploy a Multi-Tier Application

```bash
kubectl create namespace lab04-$STUDENT_NAME
```

<!-- Creates backend Deployment (3 replicas of httpbin with readiness probe) -->
<!-- Creates frontend Deployment (2 replicas of nginx with http/https ports) -->
Apply the manifests:

```bash
envsubst < backend-deployment.yaml | kubectl apply -f -
envsubst < frontend-deployment.yaml | kubectl apply -f -
kubectl get pods -n lab04-$STUDENT_NAME -o wide
```

> ✅ **Checkpoint:** You should have 5 pods running -- 3 backend and 2 frontend, all 1/1 Ready.

---

## Step 2: Create a ClusterIP Service for the Backend

<!-- Creates a ClusterIP Service selecting backend pods on port 80 -->
Apply the manifest:

```bash
envsubst < backend-svc.yaml | kubectl apply -f -
kubectl get svc backend-svc -n lab04-$STUDENT_NAME
kubectl describe svc backend-svc -n lab04-$STUDENT_NAME
```

> ✅ **Checkpoint:** The `describe` output should list Endpoints matching all three backend pod IPs.

---

## Step 3: Test DNS-Based Service Discovery

```bash
FRONTEND_POD=$(kubectl get pod -n lab04-$STUDENT_NAME -l tier=web \
  -o jsonpath='{.items[0].metadata.name}')

# Install tools in the nginx container
kubectl exec $FRONTEND_POD -n lab04-$STUDENT_NAME -- \
  apt-get update -qq && kubectl exec $FRONTEND_POD -n lab04-$STUDENT_NAME -- \
  apt-get install -y -qq curl dnsutils > /dev/null

# Test DNS resolution
kubectl exec $FRONTEND_POD -n lab04-$STUDENT_NAME -- nslookup backend-svc

# Curl the backend through the Service
kubectl exec $FRONTEND_POD -n lab04-$STUDENT_NAME -- curl -s backend-svc/ip
```

> ✅ **Checkpoint:** `nslookup` resolves `backend-svc` to its ClusterIP. Run `curl` multiple times to see different backend pods responding.

---

## Step 4: Examine DNS Records in Detail

```bash
kubectl exec $FRONTEND_POD -n lab04-$STUDENT_NAME -- \
  nslookup backend-svc.lab04-$STUDENT_NAME.svc.cluster.local

kubectl exec $FRONTEND_POD -n lab04-$STUDENT_NAME -- cat /etc/resolv.conf
```

DNS resolution formats:

| Format | Example |
|--------|---------|
| Short name (same namespace) | `backend-svc` |
| Cross-namespace | `backend-svc.lab04-$STUDENT_NAME` |
| FQDN | `backend-svc.lab04-$STUDENT_NAME.svc.cluster.local` |

> ✅ **Checkpoint:** The `resolv.conf` should show search domains including your namespace.

---

## Step 5: Create a NodePort Service

<!-- Creates a NodePort Service for frontend pods on port 80 -->
Apply the manifest:

```bash
envsubst < frontend-nodeport.yaml | kubectl apply -f -
kubectl get svc frontend-nodeport -n lab04-$STUDENT_NAME
NODE_PORT=$(kubectl get svc frontend-nodeport -n lab04-$STUDENT_NAME -o jsonpath='{.spec.ports[0].nodePort}')
echo "NodePort assigned: $NODE_PORT"
```

> ⚠️ **Note:** In EKS, node security groups may block NodePort traffic by default. NodePort is primarily for development -- production uses LoadBalancer or Ingress.

---

## Step 6: Create a LoadBalancer Service

> ⚠️ **Instructor Demo:** LoadBalancer services create real AWS NLBs (~$16/day each). Observe the instructor's demo or clean up immediately after testing.

<!-- Creates a LoadBalancer Service with AWS NLB annotations for frontend -->
Apply the manifest:

```bash
envsubst < frontend-lb.yaml | kubectl apply -f -
kubectl get svc frontend-lb -n lab04-$STUDENT_NAME -w
```

Once EXTERNAL-IP appears, test:

```bash
LB_HOST=$(kubectl get svc frontend-lb -n lab04-$STUDENT_NAME \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s http://$LB_HOST
```

> ✅ **Checkpoint:** You should see the nginx default page served through the NLB.

> ⚠️ **Troubleshooting:** If EXTERNAL-IP stays `<pending>` for more than 5 minutes, check: `kubectl get deployment -n kube-system aws-load-balancer-controller`.

---

## Step 7: Explore Endpoints and EndpointSlices

```bash
kubectl get endpoints backend-svc -n lab04-$STUDENT_NAME
kubectl get endpointslices -n lab04-$STUDENT_NAME \
  -l kubernetes.io/service-name=backend-svc
```

Scale the backend and watch Endpoints change:

```bash
# In one terminal, watch endpoints
kubectl get endpoints backend-svc -n lab04-$STUDENT_NAME -w

# In another terminal, scale down then back up
kubectl scale deployment backend -n lab04-$STUDENT_NAME --replicas=1
kubectl scale deployment backend -n lab04-$STUDENT_NAME --replicas=3
```

> ✅ **Checkpoint:** Endpoints update dynamically as pods scale.

---

## Step 8: Create a Headless Service

<!-- Creates a headless Service (clusterIP: None) for direct pod IP resolution -->
Apply the manifest:

```bash
envsubst < backend-headless.yaml | kubectl apply -f -
```

Compare DNS responses between normal and headless Services:

```bash
# ClusterIP Service - returns the virtual IP
kubectl exec $FRONTEND_POD -n lab04-$STUDENT_NAME -- \
  dig backend-svc.lab04-$STUDENT_NAME.svc.cluster.local +short

# Headless Service - returns individual pod IPs
kubectl exec $FRONTEND_POD -n lab04-$STUDENT_NAME -- \
  dig backend-headless.lab04-$STUDENT_NAME.svc.cluster.local +short
```

> ✅ **Checkpoint:** ClusterIP returns 1 virtual IP. Headless returns all pod IPs directly, letting the client choose which pod to connect to.

---

## Step 9: Multi-Port Service

<!-- Creates a ClusterIP Service exposing both port 80 (http) and 8443 (https) -->
Apply the manifest:

```bash
envsubst < frontend-multiport.yaml | kubectl apply -f -
kubectl get svc frontend-multiport -n lab04-$STUDENT_NAME
```

> ✅ **Checkpoint:** Output shows `80/TCP,8443/TCP`. When a Service has multiple ports, each **must** have a `name` field.

---

## Step 10: Clean Up

```bash
# Delete LoadBalancer first to ensure NLB cleanup
kubectl delete svc frontend-lb -n lab04-$STUDENT_NAME
sleep 30
kubectl config set-context --current --namespace=default
kubectl delete namespace lab04-$STUDENT_NAME
```

> ⚠️ Delete the LoadBalancer Service **before** the namespace to prevent orphaned NLBs.

---

## Summary

| Service Type | Scope | Use Case |
|-------------|-------|----------|
| **ClusterIP** | Internal only | Service-to-service communication |
| **NodePort** | External via node IP | Development and testing |
| **LoadBalancer** | External via cloud LB | Production external access |
| **Headless** | Internal, no VIP | StatefulSets, direct pod access |

- DNS is the primary discovery mechanism (short names within namespace, FQDN across namespaces)
- Endpoints track ready pod IPs dynamically as pods scale
- Always configure readiness probes so only healthy pods receive traffic

---

*Lab 4 Complete — Up Next: Lab 5 — ConfigMaps, Secrets, and External Secrets*
