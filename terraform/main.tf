terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# ── Providers ─────────────────────────────────────────────────────────────────

provider "aws" {
  region = var.region
}

# El cluster EKS es creado por create-cluster.sh (requiere iam:PassRole
# con credenciales de usuario, no disponible desde el rol de la EC2).
# Terraform lee el cluster existente para configurar el provider kubernetes.
data "aws_eks_cluster" "main" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
  }
}

# ── Data sources ──────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  account_id = data.aws_caller_identity.current.account_id
  ecr_url    = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_repo_name}"
  image_uri  = "${local.ecr_url}:${var.image_tag}"
}
