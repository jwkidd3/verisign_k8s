# Lab 13: GitOps with ArgoCD
### Declarative Application Delivery, Sync, and Rollback
**Intermediate Kubernetes — Module 13 of 13**

---

## Lab Overview

### Objectives

- Explore the ArgoCD UI and CLI
- Create an ArgoCD Application from a public Git repo
- Observe sync status and application health
- Make changes and trigger a sync
- Perform a rollback
- *Optional:* Explore FluxCD reconciliation and drift detection

### Prerequisites

- Lab 1 (cluster access configured)

> **Duration:** ~30 minutes
>
> **Note:** Steps 7-9 (FluxCD) are optional stretch goals for students who finish early.

---

## Environment Setup

```bash
cd ~/environment/verisign_k8s/labs/lab-13
export STUDENT_NAME=<your-name>
echo "Student: $STUDENT_NAME"
kubectl config set-context --current --namespace=default
```

---

## Step 1: Verify ArgoCD Installation

```bash
kubectl get pods -n argocd
kubectl get svc -n argocd
```

> ⚠️ ArgoCD is pre-installed. Do not reinstall or delete the `argocd` namespace.

Get the ArgoCD admin password:

```bash
ARGOCD_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD password: $ARGOCD_PWD"
```

Access the ArgoCD UI:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
```

> ⚠️ **Cloud9:** Click **Preview → Preview Running Application** to open the UI. Login: `admin` / password from above.

---

## Step 2: Log In with the ArgoCD CLI

```bash
argocd login localhost:8080 --username admin --password $ARGOCD_PWD --insecure

argocd version
argocd cluster list
argocd proj list
```

> ✅ **Checkpoint:** CLI shows the in-cluster destination and the `default` project.

---

## Step 3: Prepare a GitOps Repository

Create a local Git repo with Kubernetes manifests:

```bash
mkdir -p ~/argocd-lab/manifests && cd ~/argocd-lab
git init
```

```bash
cat <<'EOF' > manifests/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  labels: { app: demo-app }
spec:
  replicas: 2
  selector:
    matchLabels: { app: demo-app }
  template:
    metadata:
      labels: { app: demo-app }
    spec:
      containers:
      - name: app
        image: hashicorp/http-echo
        args: ["-text=Hello from ArgoCD v1", "-listen=:8080"]
        ports:
        - containerPort: 8080
        resources:
          requests: { cpu: 50m, memory: 32Mi }
          limits: { cpu: 100m, memory: 64Mi }
EOF
```

```bash
cat <<'EOF' > manifests/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: demo-app-svc
spec:
  selector: { app: demo-app }
  ports:
  - port: 80
    targetPort: 8080
EOF
```

```bash
git add . && git commit -m "Initial demo-app manifests"
```

---

## Step 4: Create an ArgoCD Application

Since we're using a local repo (not hosted on GitHub), we'll apply manifests directly through ArgoCD using the CLI:

```bash
kubectl create namespace argocd-lab-$STUDENT_NAME

argocd app create demo-$STUDENT_NAME \
  --project default \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace argocd-lab-$STUDENT_NAME \
  --directory-recurse \
  --path manifests \
  --repo https://github.com/argoproj/argocd-example-apps.git \
  --revision master \
  --sync-policy automated \
  --auto-prune \
  --self-heal
```

> This uses the ArgoCD example apps repo to demonstrate a working sync. We'll also deploy our local manifests separately.

```bash
argocd app get demo-$STUDENT_NAME
argocd app list
```

> ✅ **Checkpoint:** The application shows `Synced` and `Healthy` status.

---

## Step 5: Deploy Local Manifests and Observe

Apply your local manifests alongside the ArgoCD app:

```bash
kubectl apply -f ~/argocd-lab/manifests/ -n argocd-lab-$STUDENT_NAME

kubectl get pods -n argocd-lab-$STUDENT_NAME
kubectl get svc -n argocd-lab-$STUDENT_NAME
```

Test the application:

```bash
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never \
  -n argocd-lab-$STUDENT_NAME -- curl -s demo-app-svc
```

> ✅ **Checkpoint:** Returns `Hello from ArgoCD v1`.

---

## Step 6: Update and Rollback

### Make a Change

```bash
cd ~/argocd-lab
sed -i 's/Hello from ArgoCD v1/Hello from ArgoCD v2/' manifests/deployment.yaml
kubectl apply -f manifests/ -n argocd-lab-$STUDENT_NAME
kubectl rollout status deployment/demo-app -n argocd-lab-$STUDENT_NAME

kubectl run curl-test2 --image=curlimages/curl --rm -it --restart=Never \
  -n argocd-lab-$STUDENT_NAME -- curl -s demo-app-svc
```

> ✅ **Checkpoint:** Returns `Hello from ArgoCD v2`.

### Rollback

```bash
kubectl rollout undo deployment/demo-app -n argocd-lab-$STUDENT_NAME
kubectl rollout status deployment/demo-app -n argocd-lab-$STUDENT_NAME

kubectl run curl-test3 --image=curlimages/curl --rm -it --restart=Never \
  -n argocd-lab-$STUDENT_NAME -- curl -s demo-app-svc
```

> ✅ **Checkpoint:** Returns `Hello from ArgoCD v1` — rolled back to the previous version.

### ArgoCD Self-Heal Demo

If ArgoCD detects drift from the Git source, it auto-corrects. Observe self-heal on the ArgoCD-managed app:

```bash
# Scale the ArgoCD-managed guestbook app to create drift
kubectl scale deployment guestbook-ui -n argocd-lab-$STUDENT_NAME --replicas=5 2>/dev/null

# Watch ArgoCD revert it (within ~30 seconds)
kubectl get deployment -n argocd-lab-$STUDENT_NAME --watch
```

> ✅ **Checkpoint:** ArgoCD detects the drift and reverts replicas to the Git-defined value.

### ArgoCD History and Rollback

```bash
argocd app history demo-$STUDENT_NAME
argocd app rollback demo-$STUDENT_NAME 0
```

---

---

## Optional Stretch Goals

> These exercises cover additional topics from the presentation. Complete them if you finish the core lab early.

### Step 7: Explore FluxCD

> ⚠️ Flux is pre-installed on the cluster. Do not run `flux bootstrap` or `flux uninstall`.

```bash
flux check

kubectl get pods -n flux-system
kubectl get crds | grep flux

flux get sources git
flux get sources helm
flux get kustomizations
```

---

### Step 8: Create a FluxCD HelmRelease

```bash
kubectl create namespace flux-lab-$STUDENT_NAME
```

Review `helm-source.yaml` and `helm-release.yaml`, then apply:

```bash
envsubst < helm-source.yaml | kubectl apply -f -
envsubst < helm-release.yaml | kubectl apply -f -

flux get helmreleases -n flux-lab-$STUDENT_NAME lab-nginx-$STUDENT_NAME --watch

helm list -n flux-lab-$STUDENT_NAME

kubectl get all -n flux-lab-$STUDENT_NAME \
  -l app.kubernetes.io/instance=lab-nginx-$STUDENT_NAME
```

> ✅ The HelmRelease shows `Ready: True` and nginx pods are running with 2 replicas.

---

### Step 9: Test Drift Detection

```bash
# Scale manually to create drift
kubectl scale deployment -n flux-lab-$STUDENT_NAME \
  -l app.kubernetes.io/instance=lab-nginx-$STUDENT_NAME \
  --replicas=5

kubectl get deployment -n flux-lab-$STUDENT_NAME

# Force reconciliation -- Flux reverts to 2 replicas
flux reconcile helmrelease lab-nginx-$STUDENT_NAME \
  -n flux-lab-$STUDENT_NAME

kubectl get deployment -n flux-lab-$STUDENT_NAME --watch
```

> ✅ After reconciliation, Flux reverts replicas to 2.

---

## Clean Up

```bash
# ArgoCD resources
argocd app delete demo-$STUDENT_NAME --yes 2>/dev/null
kubectl delete namespace argocd-lab-$STUDENT_NAME
rm -rf ~/argocd-lab

# FluxCD resources (if completed)
kubectl delete helmrelease lab-nginx-$STUDENT_NAME \
  -n flux-lab-$STUDENT_NAME --ignore-not-found
kubectl delete helmrepository bitnami-$STUDENT_NAME \
  -n flux-system --ignore-not-found
kubectl delete namespace flux-lab-$STUDENT_NAME 2>/dev/null

pkill -f "port-forward.*8080" 2>/dev/null
```

> ⚠️ Do NOT delete the `argocd` or `flux-system` namespaces — they are shared by all students.

---

## Summary

- **ArgoCD Application** — declares Git source, destination cluster/namespace, and sync policy
- **Automated Sync** — ArgoCD continuously reconciles cluster state with Git
- **Self-Heal** — manual changes are automatically reverted to match Git
- **Rollback** — use `argocd app rollback` or `kubectl rollout undo`
- **FluxCD** — HelmRelease CRD for declarative Helm lifecycle with drift correction

---

*Lab 13 Complete*
