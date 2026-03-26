###############################################################################
# IRSA Module — IAM Roles for Service Accounts
###############################################################################

variable "cluster_name" { type = string }
variable "cluster_oidc_provider_arn" { type = string }
variable "cluster_oidc_provider_url" { type = string }
variable "domain_zone_id" {
  type    = string
  default = ""
}
variable "enable_dns" {
  description = "Whether to create cert-manager and external-dns IAM roles"
  type        = bool
  default     = false
}

locals {
  oidc_issuer = replace(var.cluster_oidc_provider_url, "https://", "")
}

# ============================================================
# IRSA Demo Resources (Lab 15)
# ============================================================

resource "aws_s3_bucket" "irsa_demo" {
  bucket        = "${var.cluster_name}-irsa-demo"
  force_destroy = true

  tags = {
    Purpose     = "IRSA Lab Demo"
    Environment = "training"
  }
}

resource "aws_s3_bucket_versioning" "irsa_demo" {
  bucket = aws_s3_bucket.irsa_demo.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "test_file" {
  bucket  = aws_s3_bucket.irsa_demo.id
  key     = "test-file.txt"
  content = "Hello from the IRSA demo bucket! If you can read this, your IRSA configuration is working correctly."
}

resource "aws_s3_object" "sample_data" {
  bucket  = aws_s3_bucket.irsa_demo.id
  key     = "data/sample.json"
  content = jsonencode({
    message   = "IRSA S3 read access verified"
    timestamp = "2024-01-01T00:00:00Z"
    lab       = "lab-15-irsa"
  })
}

# ─── Cert-Manager (DNS only) ────────────────────────────────────────────────

data "aws_iam_policy_document" "cert_manager_assume" {
  count = var.enable_dns ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.cluster_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:cert-manager:cert-manager"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cert_manager" {
  count              = var.enable_dns ? 1 : 0
  name               = "${var.cluster_name}-cert-manager"
  assume_role_policy = data.aws_iam_policy_document.cert_manager_assume[0].json
}

resource "aws_iam_role_policy" "cert_manager" {
  count = var.enable_dns ? 1 : 0
  name  = "cert-manager-route53"
  role  = aws_iam_role.cert_manager[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:GetChange",
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ]
        Resource = [
          "arn:aws:route53:::hostedzone/${var.domain_zone_id}",
          "arn:aws:route53:::change/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones", "route53:ListHostedZonesByName"]
        Resource = "*"
      }
    ]
  })
}

# ─── External DNS (DNS only) ────────────────────────────────────────────────

data "aws_iam_policy_document" "external_dns_assume" {
  count = var.enable_dns ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.cluster_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:external-dns:external-dns"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_dns" {
  count              = var.enable_dns ? 1 : 0
  name               = "${var.cluster_name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume[0].json
}

resource "aws_iam_role_policy" "external_dns" {
  count = var.enable_dns ? 1 : 0
  name  = "external-dns-route53"
  role  = aws_iam_role.external_dns[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/${var.domain_zone_id}"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListHostedZonesByName"
        ]
        Resource = "*"
      }
    ]
  })
}

# ─── Outputs ────────────────────────────────────────────────────────────────

output "cert_manager_role_arn" {
  value = var.enable_dns ? aws_iam_role.cert_manager[0].arn : ""
}

output "external_dns_role_arn" {
  value = var.enable_dns ? aws_iam_role.external_dns[0].arn : ""
}

output "demo_bucket_name" {
  description = "S3 bucket name for IRSA lab demo"
  value       = aws_s3_bucket.irsa_demo.id
}
