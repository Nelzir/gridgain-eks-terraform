# -----------------------
# Create GridGain Namespace
# -----------------------
resource "kubernetes_namespace" "gg9" {
  metadata {
    name = var.gg9_namespace
  }

  # Wait until the EKS cluster & access entries are fully created
  depends_on = [
    module.eks
  ]
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

  # Load values.yaml with license injected via templatefile
  values = [
    templatefile("${path.module}/${var.gg9_values_file}", {
      license_content = file(var.gg9_license_file)
    })
  ]

  # Ensure namespace and storage class exist before installing the chart
  depends_on = [
    kubernetes_namespace.gg9,
    kubernetes_storage_class.gp3
  ]
}