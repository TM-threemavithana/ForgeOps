provider "docker" {
  host = var.docker_host != null ? var.docker_host : "unix:///var/run/docker.sock"
}
