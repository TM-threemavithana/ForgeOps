output "network_name" {
  description = "Name of the Terraform-managed Docker bridge network."
  value       = docker_network.iac_lab.name
}

output "network_id" {
  description = "Docker network ID of the isolated bridge network."
  value       = docker_network.iac_lab.id
}

output "container_name" {
  description = "Name of the diagnostic fixture container."
  value       = docker_container.diag_fixture.name
}

output "container_id" {
  description = "Docker container ID of the diagnostic fixture."
  value       = docker_container.diag_fixture.id
}

output "fixture_endpoint" {
  description = "Loopback HTTP endpoint URL for accessing the diagnostic fixture."
  value       = "http://${var.host_ip}:${var.host_port}"
}

output "container_ports" {
  description = "Exposed port configurations of the diagnostic fixture container."
  value       = docker_container.diag_fixture.ports
}
