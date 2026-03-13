###############################################################################
# Flux Bootstrap Module — GitHub Repo + Deploy Key
###############################################################################

terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

variable "github_owner" { type = string }
variable "github_token" { type = string }
variable "repository_name" { type = string }
variable "cluster_name" { type = string }
variable "cluster_path" { type = string }
variable "flux_ssh_public_key" { type = string }

resource "github_repository" "flux" {
  name        = var.repository_name
  description = "FluxCD GitOps repository for ${var.cluster_name}"
  visibility  = "private"
  auto_init   = true
}

resource "github_repository_deploy_key" "flux" {
  title      = "flux-${var.cluster_name}"
  repository = github_repository.flux.name
  key        = var.flux_ssh_public_key
  read_only  = false
}

output "repository_ssh_url" {
  value = github_repository.flux.ssh_clone_url
}
