variable "region" {
  description = "AWS region (Learner Lab: us-east-1 or us-west-2)"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "iny1105-ea3-cluster"
}

variable "node_type" {
  description = "EC2 instance type for EKS nodes (Learner Lab: max large)"
  type        = string
  default     = "t3.small"
}

variable "nodes_desired" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "nodes_min" {
  type    = number
  default = 1
}

variable "nodes_max" {
  type    = number
  default = 3
}

variable "ecr_repo_name" {
  description = "ECR repository name for the Prometheus image"
  type        = string
  default     = "prometheus-healthtrack"
}

variable "image_tag" {
  description = "Docker image tag to build and push"
  type        = string
  default     = "1.0.0"
}

variable "namespace" {
  description = "Kubernetes namespace for all workloads"
  type        = string
  default     = "monitoring"
}

variable "nodeport_act31" {
  description = "NodePort for act31 Prometheus service (30000-32767)"
  type        = number
  default     = 30090
}

variable "nodeport_act32" {
  description = "NodePort for act32 Prometheus-v2 service (30000-32767)"
  type        = number
  default     = 30092
}

variable "eks_role_arn" {
  description = "ARN del rol IAM para EKS. El Learner Lab genera un nombre aleatorio por sesión. deploy.sh lo detecta automáticamente y lo pasa como TF_VAR_eks_role_arn."
  type        = string
  default     = ""
}
