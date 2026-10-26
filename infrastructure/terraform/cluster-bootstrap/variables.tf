# ForgeOps Gate G08 — Cluster Bootstrap Variables
# Enforces strict parameter validation, explicit context matching, and resource-conscious defaults

variable "kubeconfig_path" {
  type        = string
  description = "Absolute or home-relative path to the Kind cluster kubeconfig file"
  default     = "~/.kube/config-forgeops"

  validation {
    condition     = length(trimspace(var.kubeconfig_path)) > 0
    error_message = "Kubeconfig path must not be empty."
  }
}

variable "kubeconfig_context" {
  type        = string
  description = "Target Kubernetes cluster context name; strictly enforced to prevent accidental mutation of other clusters"
  default     = "kind-forgeops"

  validation {
    condition     = var.kubeconfig_context == "kind-forgeops"
    error_message = "Strict boundary enforcement: kubeconfig_context must be 'kind-forgeops'."
  }
}

variable "argocd_namespace" {
  type        = string
  description = "Dedicated Kubernetes namespace for the Argo CD platform components"
  default     = "argocd"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.argocd_namespace))
    error_message = "Namespace must conform to RFC 1123 DNS label standards."
  }
}

variable "argocd_chart_version" {
  type        = string
  description = "Exact pinned version of the upstream argo/argo-cd Helm chart (deploys Argo CD v3.5.6)"
  default     = "10.11.6"

  validation {
    condition     = var.argocd_chart_version == "10.11.6"
    error_message = "Chart version must be pinned to 10.11.6 for Gate G08 reproducibility."
  }
}
