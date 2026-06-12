# ── Kubernetes resources ──────────────────────────────────────────────────────
# Todos dependen de null_resource.update_kubeconfig para garantizar que
# el cluster esté ACTIVE y kubectl esté configurado antes de aplicar.

# ── Namespace compartido ──────────────────────────────────────────────────────

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.namespace
  }

  depends_on = [null_resource.update_kubeconfig]
}

# ════════════════════════════════════════════════════════════════════════════
# ACT 3.1 — Prometheus básico con NodePort
# ════════════════════════════════════════════════════════════════════════════

resource "kubernetes_deployment" "act31_prometheus" {
  metadata {
    name      = "prometheus"
    namespace = var.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "prometheus"
      }
    }

    template {
      metadata {
        labels = {
          app = "prometheus"
        }
      }

      spec {
        container {
          name  = "prometheus"
          image = local.image_uri

          port {
            container_port = 9090
          }

          env {
            name  = "APP_ENV"
            value = "production"
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.monitoring,
    null_resource.docker_build_push,
  ]
}

resource "kubernetes_service" "act31_prometheus" {
  metadata {
    name      = "prometheus"
    namespace = var.namespace
  }

  spec {
    selector = {
      app = "prometheus"
    }

    type = "NodePort"

    port {
      protocol    = "TCP"
      port        = 9090
      target_port = 9090
      node_port   = var.nodeport_act31
    }
  }

  depends_on = [kubernetes_namespace.monitoring]
}

# ════════════════════════════════════════════════════════════════════════════
# ACT 3.2 — Prometheus v2 con ConfigMap, 2 réplicas, resources
# ════════════════════════════════════════════════════════════════════════════

resource "kubernetes_config_map" "act32_config" {
  metadata {
    name      = "prometheus-config"
    namespace = var.namespace
  }

  data = {
    APP_ENV                   = "production"
    LOG_LEVEL                 = "info"
    PROMETHEUS_RETENTION_TIME = "15d"
  }

  depends_on = [kubernetes_namespace.monitoring]
}

resource "kubernetes_deployment" "act32_prometheus_v2" {
  metadata {
    name      = "prometheus-v2"
    namespace = var.namespace
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "prometheus-v2"
      }
    }

    template {
      metadata {
        labels = {
          app = "prometheus-v2"
        }
      }

      spec {
        container {
          name  = "prometheus"
          image = local.image_uri

          port {
            container_port = 9090
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.act32_config.metadata[0].name
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.monitoring,
    kubernetes_config_map.act32_config,
    null_resource.docker_build_push,
  ]
}

resource "kubernetes_service" "act32_prometheus_v2" {
  metadata {
    name      = "prometheus-v2"
    namespace = var.namespace
  }

  spec {
    selector = {
      app = "prometheus-v2"
    }

    type = "NodePort"

    port {
      protocol    = "TCP"
      port        = 9090
      target_port = 9090
      node_port   = var.nodeport_act32
    }
  }

  depends_on = [kubernetes_namespace.monitoring]
}
