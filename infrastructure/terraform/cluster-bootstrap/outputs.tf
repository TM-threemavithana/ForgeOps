# ForgeOps Gate G08 — Cluster Bootstrap Outputs
# Provides operational metadata without exposing credentials or sensitive values

output "argocd_namespace" {
  description = "Kubernetes namespace housing the Argo CD control plane"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_helm_release_name" {
  description = "Name of the provisioned Helm release"
  value       = helm_release.argocd.name
}

output "argocd_chart_version" {
  description = "Pinned version of the deployed argo-cd Helm chart"
  value       = helm_release.argocd.version
}

output "argocd_server_service" {
  description = "Internal Kubernetes Service name for the Argo CD API / UI server"
  value       = "argocd-server.${kubernetes_namespace.argocd.metadata[0].name}.svc.cluster.local"
}

output "operator_access_guide" {
  description = "Operational instructions for accessing Argo CD securely via localhost without exposing credentials"
  value       = <<-EOT
    ==============================================================================
    Argo CD Operator Access (Zero Public Exposure)
    ==============================================================================
    1. Port-forward the Argo CD server to localhost:
       kubectl --kubeconfig ~/.kube/config-forgeops --context kind-forgeops \
         port-forward svc/argocd-server -n argocd 8080:443

    2. Retrieve initial admin password dynamically from the generated Secret:
       kubectl --kubeconfig ~/.kube/config-forgeops --context kind-forgeops \
         -n argocd get secret argocd-initial-admin-secret \
         -o jsonpath="{.data.password}" | base64 -d; echo

    3. Open Web UI: https://localhost:8080 (Username: admin)
    ==============================================================================
  EOT
}
