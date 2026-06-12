# ── ECR Repository ────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "prometheus" {
  name                 = var.ecr_repo_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  # force_delete permite destruir el repo aunque tenga imágenes
  force_delete = true
}

# ── Build y push de la imagen Docker ─────────────────────────────────────────
# Usa null_resource con local-exec para:
#   1. Autenticar Docker con ECR
#   2. Construir la imagen desde terraform/docker/Dockerfile
#   3. Taggear y pushear al repositorio

resource "null_resource" "docker_build_push" {
  triggers = {
    # Re-ejecuta si cambia el Dockerfile o el tag de imagen
    dockerfile_hash = filemd5("${path.module}/docker/Dockerfile")
    image_tag       = var.image_tag
    ecr_repo        = aws_ecr_repository.prometheus.repository_url
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "==> Autenticando Docker con ECR..."
      aws ecr get-login-password --region ${var.region} \
        | docker login --username AWS --password-stdin ${local.account_id}.dkr.ecr.${var.region}.amazonaws.com

      echo "==> Construyendo imagen..."
      docker build -t ${var.ecr_repo_name}:${var.image_tag} ${path.module}/docker/

      echo "==> Taggeando imagen..."
      docker tag ${var.ecr_repo_name}:${var.image_tag} ${local.image_uri}

      echo "==> Pusheando imagen a ECR..."
      docker push ${local.image_uri}

      echo "==> Imagen publicada: ${local.image_uri}"
    EOT
  }

  depends_on = [aws_ecr_repository.prometheus]
}
