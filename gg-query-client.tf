# =========================
# GridGain Query Client Deployment
# HTTP proxy for k6 load testing
# =========================

variable "query_client_image" {
  description = "Docker image for gg-query-client"
  type        = string
  default     = "nelzir/gg-query-client:latest"
}

resource "kubernetes_deployment" "query_client" {
  metadata {
    name      = "gg-query-client"
    namespace = var.gg9_namespace
    labels = {
      app = "gg-query-client"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "gg-query-client"
      }
    }

    template {
      metadata {
        labels = {
          app = "gg-query-client"
        }
      }

      spec {
        node_selector = {
          role = "loadtest"
        }

        toleration {
          key      = "dedicated"
          operator = "Equal"
          value    = "loadtest"
          effect   = "NoSchedule"
        }

        container {
          name  = "query-client"
          image = var.query_client_image

          args = [
            "-listen", ":8080",
            "-gg-host", "gg9-gridgain9-headless.${var.gg9_namespace}.svc.cluster.local",
            "-gg-port", "10800",
            "-gg-user", var.gg9_admin_username,
            "-gg-password", var.gg9_admin_password,
          ]

          port {
            container_port = 8080
            name           = "http"
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }

          resources {
            requests = {
              memory = "64Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "256Mi"
              cpu    = "500m"
            }
          }
        }

        restart_policy = "Always"
      }
    }
  }

  depends_on = [helm_release.gridgain9]
}

resource "kubernetes_service" "query_client" {
  metadata {
    name      = "gg-query-client"
    namespace = var.gg9_namespace
    labels = {
      app = "gg-query-client"
    }
  }

  spec {
    type = "LoadBalancer"

    selector = {
      app = "gg-query-client"
    }

    port {
      port        = 80
      target_port = 8080
      protocol    = "TCP"
      name        = "http"
    }
  }

  depends_on = [kubernetes_deployment.query_client]
}

output "query_client_lb_command" {
  description = "Command to get query client LoadBalancer hostname"
  value       = "kubectl --context ${var.cluster_name} get svc gg-query-client -n ${var.gg9_namespace} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
