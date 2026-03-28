# Instructor Setup — Verisign Kubernetes Course

---

## Step 1: Deploy the EKS Cluster

### Prerequisites

- AWS CLI v2, Terraform >= 1.5, kubectl, Flux CLI
- GitHub PAT with `repo` and `admin:public_key` scopes

### Configure and Deploy

```bash
cd eks-platform/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

export TF_VAR_github_token="ghp_your_token_here"

terraform init
terraform plan
terraform apply
```

### Connect

```bash
aws eks update-kubeconfig --name platform-lab --region us-east-2
```

---

## Step 2: Verify Flux

Wait 5-10 minutes after deploy, then:

```bash
flux get kustomizations
```

All should show `Ready: True`.

---

## Step 3: Post-Deploy Configuration

### Update IRSA ARNs

```bash
terraform output irsa_roles
```

Update ARNs in:
- `flux/infrastructure/core/core.yaml` → cert-manager
- `flux/infrastructure/networking/networking.yaml` → external-dns

Commit and push.

### Configure Splunk HEC Token

```bash
kubectl port-forward svc/splunk 8000:8000 -n splunk
# http://localhost:8000 — admin / Chang3Me!
# Settings > Data Inputs > HTTP Event Collector > New Token
# Name: kubernetes | Index: main | Source Type: _json

kubectl create secret generic splunk-hec-token \
  -n logging --from-literal=token=YOUR_HEC_TOKEN
```

---

## Step 4: Create Student IAM Role

One role shared by all 22 students:

1. IAM Console → **Roles → Create role**
2. Trusted entity: **AWS service / EC2** → Next
3. Policy: **AdministratorAccess** → Next
4. Role name: `k8s-lab-role` → Create

---

## Step 5: Grant the Role EKS Access

Run once:

```bash
aws eks create-access-entry \
  --cluster-name platform-lab \
  --principal-arn arn:aws:iam::001613358280:role/k8s-lab-role \
  --region us-east-2

aws eks associate-access-policy \
  --cluster-name platform-lab \
  --principal-arn arn:aws:iam::001613358280:role/k8s-lab-role \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster \
  --region us-east-2
```

---

## Step 6: Verify Platform Components

```bash
kubectl top nodes                                    # Metrics Server
kubectl get installation default                     # Calico
kubectl get pods -n ingress-nginx                    # NGINX Ingress
kubectl get pods -n envoy-gateway-system             # Envoy Gateway
kubectl get crd | grep gateway                       # Gateway API CRDs
kubectl get pods -n monitoring                       # Prometheus + Grafana
kubectl get pods -n kyverno                          # Kyverno
kubectl get pods -n argocd                           # ArgoCD
kubectl get pods -n flux-system                      # Flux
kubectl get pods -n vault                            # Vault
kubectl exec -n vault vault-0 -- vault status
kubectl get pods -n external-secrets                 # ESO
kubectl get clustersecretstore                       # Vault integration
aws s3 ls s3://platform-lab-irsa-demo/               # IRSA demo bucket
```

---

## Monitoring Access

```bash
# Grafana — admin / admin
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring

# Prometheus
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring

# Vault — Token: root
kubectl port-forward svc/vault 8200:8200 -n vault
```

---

## Teardown (after course)

```bash
aws eks delete-access-entry \
  --cluster-name platform-lab \
  --principal-arn arn:aws:iam::001613358280:role/k8s-lab-role \
  --region us-east-2

aws iam detach-role-policy \
  --role-name k8s-lab-role \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam delete-role --role-name k8s-lab-role

cd eks-platform/terraform
terraform destroy
```
