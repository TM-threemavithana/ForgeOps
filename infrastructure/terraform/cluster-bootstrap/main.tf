# ForgeOps Gate G08 — Terraform Cluster Bootstrap Main Configuration
# Strictly scopes Terraform ownership to the Argo CD control plane platform bootstrap.
# Does NOT manage application workloads, G06 resources, or out-of-band secrets.

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace

    labels = {
      "app.kubernetes.io/name"       = "argocd"
      "app.kubernetes.io/part-of"    = "forgeops"
      "app.kubernetes.io/managed-by" = "terraform"
      "forgeops.io/gate"             = "G08"
      "forgeops.io/role"             = "gitops-platform"
    }
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # Non-destructive timeout and wait controls
  timeout = 600
  wait    = true

  # Ensure clean lifecycle tracking
  cleanup_on_fail = true
  max_history     = 5

  # Load resource-constrained values profile strictly validated against chart 10.11.6
  values = [
    file("${path.module}/values-argocd-core.yaml")
  ]

  # Explicit dependency on namespace ownership
  depends_on = [
    kubernetes_namespace.argocd
  ]
}
