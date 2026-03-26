# EKS Platform Stack — Automated Deployment

## Architecture

```
Terraform creates:              FluxCD manages:
├── VPC + Subnets               ├── infrastructure/
├── EKS Cluster                 │   ├── sources/        (Helm repos)
├── Managed Node Group          │   ├── core/           (Metrics Server, Cert-Manager, Calico)
├── IRSA Roles                  │   ├── security/       (ESO, Kyverno)
│   ├── cert-manager            │   ├── monitoring/     (Prometheus Stack, Blackbox)
│   └── external-dns            │   ├── networking/     (Envoy Gateway, External DNS)
├── Vault (Helm + bootstrap)    │   └── logging/        (Logging Operator)
└── FluxCD bootstrap            ├── platform/           (Splunk, Gateway, ClusterIssuer, logging pipeline)
                                └── policies/           (Kyverno ClusterPolicies)
```

## Dependency Order (Flux handles this automatically)

```
sources
  └─► core (Metrics Server, Cert-Manager, Calico)
        ├─► security (ESO + Kyverno)
        │     └─► networking (Envoy GW + External DNS)
        │     └─► policies (Kyverno ClusterPolicies)
        ├─► monitoring (Prometheus + Blackbox)
        └─► logging (Logging Operator)
              └─► platform (Splunk, Gateway, ClusterIssuer, logging pipeline, probes)
```

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.5
- kubectl
- flux CLI (`curl -s https://fluxcd.io/install.sh | sudo bash`)
- GitHub PAT with `repo` scope

## Deployment — 3 Commands

### 1. Configure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

Set your GitHub token:

```bash
export TF_VAR_github_token="ghp_your_token_here"
```

### 2. Deploy

```bash
terraform init
terraform plan
terraform apply
```

This will:
1. Create the VPC and EKS cluster (~15 min)
2. Create IRSA roles for cert-manager and external-dns
3. Deploy Vault in dev mode and bootstrap it (KV engine, K8s auth, ESO role)
4. Create the GitHub repo and bootstrap FluxCD
5. Flux then reconciles all infrastructure layers automatically

### 3. Connect

```bash
aws eks update-kubeconfig --name platform-lab --region us-east-1
```

## Post-Deploy Steps

### Update IRSA ARNs in Flux manifests

After `terraform apply`, get the IRSA ARNs:

```bash
terraform output irsa_roles
```

Update these files with the actual ARNs:
- `flux/infrastructure/core/core.yaml` → cert-manager serviceAccount annotation
- `flux/infrastructure/networking/networking.yaml` → external-dns serviceAccount annotation

Commit and push — Flux picks up the changes automatically.

### Configure Splunk HEC Token

Once Splunk is running:

```bash
kubectl port-forward svc/splunk 8000:8000 -n splunk
# Open http://localhost:8000 — admin / Chang3Me!
# Settings > Data Inputs > HTTP Event Collector > New Token
# Name: kubernetes | Index: main | Source Type: _json
```

Create the secret for the logging pipeline:

```bash
kubectl create secret generic splunk-hec-token \
  -n logging --from-literal=token=YOUR_HEC_TOKEN
```

### Update Domain References

Search and replace `example.com` in `flux/platform/platform.yaml` with your actual domain.

## Monitoring Access

```bash
# Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
# http://localhost:3000 — admin / admin

# Prometheus
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring

# Alertmanager
kubectl port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 -n monitoring

# Vault
kubectl port-forward svc/vault 8200:8200 -n vault
# http://localhost:8200 — Token: root
```

## Verification

```bash
# Flux status
flux get all

# All pods
kubectl get pods -A | grep -v Running | grep -v Completed

# Individual components
kubectl get installation default                    # Calico
kubectl top nodes                                   # Metrics Server
kubectl get clusterissuer                           # Cert-Manager
kubectl get clustersecretstore                      # ESO → Vault
kubectl get externalsecret -A                       # ESO synced secrets
kubectl get clusterpolicy                           # Kyverno
kubectl get policyreport -A                         # Kyverno audit results
kubectl get prometheusrule -A                       # Prometheus
kubectl get servicemonitor -A                       # Prometheus targets
kubectl get gateway -A                              # Envoy Gateway
kubectl get logging -n logging                      # Logging Operator
kubectl get clusterflow,clusteroutput -n logging    # Logging pipeline
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=20
```

## Multi-Student Shared Cluster (22 Students)

### Capacity Planning

The cluster is sized for 22 concurrent students:
- **Node group**: 6x m5.2xlarge (8 vCPU, 32 GiB each), auto-scaling 4-8 nodes
- **Pod capacity**: ~350 usable pods (after platform overhead)
- **ResourceQuotas**: Auto-generated per lab namespace (4 CPU, 8Gi requests, 40 pods max)
- **LimitRanges**: Default container limits (500m CPU, 512Mi memory)

### Pre-installed Platform Components

| Component | Namespace | Lab(s) |
|-----------|-----------|--------|
| Metrics Server | kube-system | Lab 02 |
| Calico (NetworkPolicy) | calico-system | Lab 08 |
| NGINX Ingress Controller | ingress-nginx | Lab 06 |
| Envoy Gateway + Gateway API CRDs | envoy-gateway-system | Lab 06 |
| Kyverno (Pod Security) | kyverno | Lab 07 |
| Prometheus + Grafana | monitoring | Lab 09 |
| ArgoCD | argocd | Lab 13 |
| Flux | flux-system | Lab 14 |
| Vault (dev mode) | vault | Lab 16 |
| External Secrets Operator | external-secrets | Lab 16 |

### Student Access Setup

1. Students assume the IAM role `<cluster-name>-student-role`
2. The role maps to Kubernetes group `students` via EKS access entry
3. The `student-lab-role` ClusterRole grants:
   - Create/delete namespaces matching `lab*`, `obs-*`, `deploy-*`, etc.
   - Full access to namespaced resources within their own namespaces
   - Read-only access to nodes, StorageClasses, CRDs
   - Access to platform CRDs (Flux, Gateway API, Monitoring, ESO)

### Student Onboarding

```bash
# Generate kubeconfig for a student (run as cluster admin)
CLUSTER_NAME=verisign-k8s-lab
REGION=us-east-1
STUDENT_ROLE_ARN=$(terraform -chdir=eks-platform/terraform output -raw student_role_arn)

aws eks update-kubeconfig \
  --name $CLUSTER_NAME \
  --region $REGION \
  --role-arn $STUDENT_ROLE_ARN \
  --kubeconfig student-kubeconfig.yaml

# Distribute student-kubeconfig.yaml to students
```

### Lab Prerequisites Checklist

Before class, verify all platform components are running:

```bash
# Check all platform pods
kubectl get pods -A | grep -E '(ingress-nginx|envoy-gateway|argocd|monitoring|vault|external-secrets|calico|kyverno|flux)'

# Verify IRSA demo bucket
aws s3 ls s3://<cluster-name>-irsa-demo/

# Verify Vault is accessible
kubectl exec -n vault vault-0 -- vault status

# Test student RBAC
kubectl auth can-i create namespaces --as-group=students
```

## Teardown

```bash
terraform destroy
```

## File Structure

```
eks-platform/
├── terraform/
│   ├── main.tf                          # Root module — providers, module calls
│   ├── variables.tf                     # Input variables
│   ├── outputs.tf                       # Outputs (kubeconfig cmd, IRSA ARNs)
│   ├── terraform.tfvars.example         # Example config
│   └── modules/
│       ├── eks/                         # VPC + EKS + node group
│       ├── irsa/                        # IAM roles (cert-manager, external-dns)
│       ├── vault/                       # Vault Helm + bootstrap Job
│       └── flux-bootstrap/              # GitHub repo + deploy key
└── flux/
    ├── infrastructure/
    │   ├── kustomizations.yaml          # Layer orchestration + dependencies
    │   ├── sources/                     # All HelmRepository definitions
    │   ├── core/                        # Metrics Server, Cert-Manager, Calico
    │   ├── security/                    # ESO, Kyverno, ClusterSecretStore
    │   ├── monitoring/                  # Prometheus Stack, Blackbox Exporter
    │   ├── networking/                  # Envoy Gateway, External DNS
    │   └── logging/                     # Logging Operator
    ├── platform/                        # Splunk, Gateway, ClusterIssuer, logging pipeline
    └── policies/                        # Kyverno ClusterPolicies
```
