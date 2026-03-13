###############################################################################
# IRSA Module — IAM Roles for Service Accounts
###############################################################################

variable "cluster_name" { type = string }
variable "cluster_oidc_provider_arn" { type = string }
variable "cluster_oidc_provider_url" { type = string }
variable "domain_zone_id" { type = string }

locals {
  oidc_issuer = replace(var.cluster_oidc_provider_url, "https://", "")
}

# ─── Cert-Manager ───────────────────────────────────────────────────────────

data "aws_iam_policy_document" "cert_manager_assume" {
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
  name               = "${var.cluster_name}-cert-manager"
  assume_role_policy = data.aws_iam_policy_document.cert_manager_assume.json
}

resource "aws_iam_role_policy" "cert_manager" {
  name = "cert-manager-route53"
  role = aws_iam_role.cert_manager.id

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

# ─── External DNS ───────────────────────────────────────────────────────────

data "aws_iam_policy_document" "external_dns_assume" {
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
  name               = "${var.cluster_name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume.json
}

resource "aws_iam_role_policy" "external_dns" {
  name = "external-dns-route53"
  role = aws_iam_role.external_dns.id

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
  value = aws_iam_role.cert_manager.arn
}

output "external_dns_role_arn" {
  value = aws_iam_role.external_dns.arn
}
