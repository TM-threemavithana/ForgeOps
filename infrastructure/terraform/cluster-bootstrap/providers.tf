# ForgeOps Gate G08 — Provider Configuration
# Explicitly binds Terraform to the local Kind cluster via verified kubeconfig and context

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kubeconfig_context
}

provider "helm" {
  kubernetes {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = var.kubeconfig_context
  }
}
