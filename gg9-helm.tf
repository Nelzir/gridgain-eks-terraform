# -----------------------
# Create GridGain Namespace
# -----------------------
resource "kubernetes_namespace" "gg9" {
  metadata {
    name = var.gg9_namespace
  }

  depends_on = [module.eks]
}

# -----------------------
# Fetch license from AWS Secrets Manager
# -----------------------
data "aws_secretsmanager_secret_version" "gg9_license" {
  secret_id = var.gg9_license_secret_arn
}

# -----------------------
# Create Kubernetes secret for license
# -----------------------
resource "kubernetes_secret" "gg9_license" {
  metadata {
    name      = "gg9-license"
    namespace = kubernetes_namespace.gg9.metadata[0].name
  }

  data = {
    "license.conf" = data.aws_secretsmanager_secret_version.gg9_license.secret_string
  }
}

# -----------------------
# GG9 Helm Release
# -----------------------
resource "helm_release" "gridgain9" {
  name      = "gg9"
  namespace = kubernetes_namespace.gg9.metadata[0].name

  repository = "https://gridgain.github.io/helm-charts"
  chart      = "gridgain9"
  version    = var.gg9_chart_version
  replace    = true

  values = [file("${path.module}/${var.gg9_values_file}")]

  depends_on = [
    kubernetes_namespace.gg9,
    kubernetes_storage_class.gp3,
    kubernetes_secret.gg9_license
  ]
}

# -----------------------
# Annotate client service for AWS NLB
# (Chart has a bug with annotations, so we apply them separately)
# -----------------------
resource "kubernetes_annotations" "gg9_client_nlb" {
  api_version = "v1"
  kind        = "Service"
  metadata {
    name      = "gg9-gridgain9-client"
    namespace = kubernetes_namespace.gg9.metadata[0].name
  }

  annotations = {
    "service.beta.kubernetes.io/aws-load-balancer-type"                            = "external"
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"                 = "ip"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"                          = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
  }

  depends_on = [helm_release.gridgain9]
}
