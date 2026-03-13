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
