output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "ecr_repository_url" {
  description = "Full ECR repository URL"
  value       = aws_ecr_repository.prometheus.repository_url
}

output "image_uri" {
  description = "Full Docker image URI pushed to ECR"
  value       = local.image_uri
}

output "node_external_ips" {
  description = "External IPs of EKS worker nodes (run: kubectl get nodes -o wide)"
  value       = "Run: kubectl get nodes -o wide -o jsonpath='{.items[*].status.addresses[?(@.type==\"ExternalIP\")].address}'"
}

output "act31_prometheus_url" {
  description = "URL para acceder a Prometheus de act31 (reemplaza <NODE_IP>)"
  value       = "http://<NODE_IP>:${var.nodeport_act31}"
}

output "act32_prometheus_v2_url" {
  description = "URL para acceder a Prometheus-v2 de act32 (reemplaza <NODE_IP>)"
  value       = "http://<NODE_IP>:${var.nodeport_act32}"
}

output "kubeconfig_command" {
  description = "Comando para configurar kubectl si es necesario"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}"
}
