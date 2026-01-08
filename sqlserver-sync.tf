# =========================
# SQL Server Sync Deployment
# =========================

# Job to create GridGain tables before sync starts
# Uses kubectl + bitnami/kubectl image to exec into GG pod and run SQL via CLI
resource "kubernetes_job" "gridgain_table_setup" {
  metadata {
    name      = "gridgain-table-setup"
    namespace = var.gg9_namespace
  }

  spec {
    ttl_seconds_after_finished = 300
    backoff_limit              = 5

    template {
      metadata {
        labels = {
          app = "gridgain-table-setup"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.table_setup.metadata[0].name

        node_selector = {
          role = "system"
        }

        restart_policy = "OnFailure"

        container {
          name  = "setup"
          image = "bitnami/kubectl:latest"

          command = ["/bin/bash", "-c"]
          args = [<<-EOF
            set -e
            echo "Waiting for GridGain pods to be ready..."
            kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=gridgain9 -n ${var.gg9_namespace} --timeout=120s
            
            GG_POD=$(kubectl get pods -l app.kubernetes.io/name=gridgain9 -n ${var.gg9_namespace} -o jsonpath='{.items[0].metadata.name}')
            echo "Using GridGain pod: $GG_POD"
            
            run_sql() {
              echo "Executing: $1"
              kubectl exec -n ${var.gg9_namespace} "$GG_POD" -- /opt/gridgain9cli/bin/gridgain9 sql "$1" || true
            }
            
            echo "Creating tables in GridGain..."
            run_sql "CREATE TABLE IF NOT EXISTS Customers (Id INT PRIMARY KEY, Name VARCHAR(100), Email VARCHAR(100))"
            run_sql "CREATE TABLE IF NOT EXISTS Products (Id INT PRIMARY KEY, Name VARCHAR(100), Price DECIMAL(10,2))"
            run_sql "CREATE TABLE IF NOT EXISTS Orders (Id INT PRIMARY KEY, CustomerId INT, ProductId INT, Quantity INT, OrderDate TIMESTAMP)"
            
            echo "Table setup complete"
          EOF
          ]

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
      }
    }
  }

  wait_for_completion = true
  timeouts {
    create = "5m"
  }

  depends_on = [
    helm_release.gridgain9,
    kubernetes_role_binding.table_setup,
  ]
}

# Service account for table setup job
resource "kubernetes_service_account" "table_setup" {
  metadata {
    name      = "gridgain-table-setup"
    namespace = var.gg9_namespace
  }
}

# Role to allow exec into pods
resource "kubernetes_role" "table_setup" {
  metadata {
    name      = "gridgain-table-setup"
    namespace = var.gg9_namespace
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/exec"]
    verbs      = ["create"]
  }
}

resource "kubernetes_role_binding" "table_setup" {
  metadata {
    name      = "gridgain-table-setup"
    namespace = var.gg9_namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.table_setup.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.table_setup.metadata[0].name
    namespace = var.gg9_namespace
  }
}

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
    kubernetes_job.gridgain_table_setup,
  ]
}
