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

# El provider kubernetes se configura con los datos del cluster creado en este
# mismo apply. Se usa depends_on en los recursos kubernetes_* para garantizar
# que el cluster exista antes de intentar conectarse.
provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
  }
}

# ── Data sources ──────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

# Rol LabEksClusterRole — ya existe en el Learner Lab, no se crea
data "aws_iam_role" "eks_cluster_role" {
  name = "LabEksClusterRole"
}

# Subnets públicas de la VPC por defecto (primeras 2)
data "aws_subnets" "default_public" {
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = data.aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids              = slice(tolist(data.aws_subnets.default_public.ids), 0, 2)
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  # Learner Lab: no se especifica versión → AWS usa la última disponible
  # Si se quiere fijar: version = "1.29"

  timeouts {
    create = "25m"
    delete = "20m"
  }
}

# ── EKS Node Group ────────────────────────────────────────────────────────────

resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "standard-workers"
  node_role_arn   = data.aws_iam_role.eks_cluster_role.arn
  subnet_ids      = slice(tolist(data.aws_subnets.default_public.ids), 0, 2)
  instance_types  = [var.node_type]

  scaling_config {
    desired_size = var.nodes_desired
    min_size     = var.nodes_min
    max_size     = var.nodes_max
  }

  depends_on = [aws_eks_cluster.main]

  timeouts {
    create = "20m"
    delete = "20m"
  }
}

# ── Actualizar kubeconfig al crear el cluster ─────────────────────────────────
# Permite que kubectl y los providers kubernetes funcionen correctamente
# tras el apply sin necesidad de pasos manuales.

resource "null_resource" "update_kubeconfig" {
  triggers = {
    cluster_name = aws_eks_cluster.main.name
    endpoint     = aws_eks_cluster.main.endpoint
  }

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}"
  }

  depends_on = [aws_eks_node_group.workers]
}

# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  account_id = data.aws_caller_identity.current.account_id
  ecr_url    = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_repo_name}"
  image_uri  = "${local.ecr_url}:${var.image_tag}"
}
