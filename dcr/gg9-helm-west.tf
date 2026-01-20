# =========================
# US-West-2 GridGain Deployment
# =========================

# -----------------------
# Create GridGain Namespace (West)
# -----------------------
resource "kubernetes_namespace" "gg9_west" {
  provider = kubernetes.west

  metadata {
    name = var.gg9_namespace
  }

  depends_on = [module.eks_west]
}

# -----------------------
# Create Kubernetes secret for license (West)
# Reuses license from us-east-1 Secrets Manager
# -----------------------
resource "kubernetes_secret" "gg9_license_west" {
  provider = kubernetes.west

  metadata {
    name      = "gg9-license"
    namespace = kubernetes_namespace.gg9_west.metadata[0].name
  }

  data = {
    "license.conf" = data.aws_secretsmanager_secret_version.gg9_license.secret_string
  }
}

# -----------------------
# GG9 Helm Release (West)
# -----------------------
resource "helm_release" "gridgain9_west" {
  provider  = helm.west
  name      = "gg9-west"
  namespace = kubernetes_namespace.gg9_west.metadata[0].name

  repository = "https://gridgain.github.io/helm-charts"
  chart      = "gridgain9"
  version    = var.gg9_chart_version
  replace    = true

  values = [file("${path.module}/gg9-values-west.yaml")]

  depends_on = [
    kubernetes_namespace.gg9_west,
    kubernetes_storage_class.gp3_west,
    kubernetes_secret.gg9_license_west
  ]
}
