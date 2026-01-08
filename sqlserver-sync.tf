# =========================
# SQL Server Sync Deployment
# =========================

resource "kubernetes_config_map" "sqlserver_sync" {
  metadata {
    name      = "sqlserver-sync-config"
    namespace = var.gg9_namespace
  }

  data = {
    SYNC_INTERVAL = "30s"
    SYNC_TABLES   = var.sync_tables
    GG_PORT       = "10800"
    GG_USER       = var.gg9_admin_username
  }

  depends_on = [helm_release.gridgain9]
}

resource "kubernetes_secret" "sqlserver_sync" {
  metadata {
    name      = "sqlserver-sync-secrets"
    namespace = var.gg9_namespace
  }

  data = {
    SQLSERVER_CONN = "sqlserver://${var.sqlserver_username}:${var.sqlserver_password}@${aws_instance.sqlserver.private_ip}:1433?database=${var.sync_database}"
    GG_PASS        = var.gg9_admin_password
  }

  depends_on = [helm_release.gridgain9]
}

resource "kubernetes_deployment" "sqlserver_sync" {
  metadata {
    name      = "sqlserver-sync"
    namespace = var.gg9_namespace
    labels = {
      app = "sqlserver-sync"
    }
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "sqlserver-sync"
      }
    }

    template {
      metadata {
        labels = {
          app = "sqlserver-sync"
        }
      }

      spec {
        node_selector = {
          role = "system"
        }

        container {
          name  = "sync"
          image = var.sync_image

          args = [
            "-sqlserver", "$(SQLSERVER_CONN)",
            "-gg-host", "gg9-gridgain9-client.${var.gg9_namespace}.svc.cluster.local",
            "-gg-port", "$(GG_PORT)",
            "-gg-user", "$(GG_USER)",
            "-gg-password", "$(GG_PASS)",
            "-tables", "$(SYNC_TABLES)",
            "-interval", "$(SYNC_INTERVAL)",
          ]

          env_from {
            config_map_ref {
              name = kubernetes_config_map.sqlserver_sync.metadata[0].name
            }
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.sqlserver_sync.metadata[0].name
            }
          }

          resources {
            requests = {
              memory = "64Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "128Mi"
              cpu    = "200m"
            }
          }
        }

        restart_policy = "Always"
      }
    }
  }

  depends_on = [
    helm_release.gridgain9,
    aws_instance.sqlserver,
  ]
}
