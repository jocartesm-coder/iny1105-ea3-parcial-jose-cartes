output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = data.aws_eks_cluster.main.endpoint
}

output "ecr_repository_url" {
  description = "Full ECR repository URL"
  value       = aws_ecr_repository.prometheus.repository_url
}

output "image_uri" {
  description = "Full Docker image URI pushed to ECR"
  value       = local.image_uri
}

output "act31_prometheus_url" {
  description = "URL para acceder a Prometheus de act31 (reemplaza <NODE_IP>)"
  value       = "http://<NODE_IP>:${var.nodeport_act31}"
}

output "act32_prometheus_v2_url" {
  description = "URL para acceder a Prometheus-v2 de act32 (reemplaza <NODE_IP>)"
  value       = "http://<NODE_IP>:${var.nodeport_act32}"
}

output "get_node_ip_command" {
  description = "Comando para obtener la IP externa de los nodos"
  value       = "kubectl get nodes -o wide"
}
