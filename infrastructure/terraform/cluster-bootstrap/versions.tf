# ForgeOps Gate G08 — Terraform Cluster Bootstrap Versions Specification
# Pinning Terraform CLI and provider versions in accordance with ADR-0014 and compatibility matrix

terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  backend "local" {
    path = "/home/tharuka/.local/state/forgeops/g08/terraform.tfstate"
  }

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36.0"
    }
  }
}
