# ForgeOps G05 - Local Docker Lab Terraform Resources
# Manages exactly three resources: diagnostic image, isolated network, and diagnostic container.
# Protected boundaries: Single resource ownership, strictly loopback port binding, bounded resources.

# 1. Diagnostic HTTP container image
# kreuzwerker/docker provider does not support root-level labels on docker_image.
# keep_locally = true preserves the image in the Docker daemon cache upon terraform destroy,
# avoiding redundant image downloads during iterative lab provisioning cycles.
resource "docker_image" "fixture" {
  name         = var.fixture_image
  keep_locally = true
}

# 2. Isolated Docker bridge network
# Docker daemon performs automatic subnet allocation; no hardcoded CIDR to avoid overlapping existing lab networks.
resource "docker_network" "iac_lab" {
  name   = var.network_name
  driver = "bridge"

  labels {
    label = "org.opencontainers.image.vendor"
    value = "ForgeOps"
  }

  labels {
    label = "forgeops.io/managed-by"
    value = "terraform"
  }

  labels {
    label = "forgeops.io/gate"
    value = "G05"
  }
}

# 3. Disposable diagnostic HTTP container fixture
# Configured with must_run = true and restart = "no" so an external docker stop is detectable during DR-10.
# Published port binds strictly to loopback 127.0.0.1:8089 to prevent external network exposure.
resource "docker_container" "diag_fixture" {
  name     = var.container_name
  image    = docker_image.fixture.image_id
  restart  = "no"
  must_run = true

  memory      = var.memory_limit_mb
  memory_swap = var.memory_limit_mb * 2
  cpu_shares  = var.cpu_shares

  networks_advanced {
    name = docker_network.iac_lab.name
  }

  ports {
    internal = 80
    external = var.host_port
    ip       = var.host_ip
    protocol = "tcp"
  }

  labels {
    label = "org.opencontainers.image.vendor"
    value = "ForgeOps"
  }

  labels {
    label = "forgeops.io/managed-by"
    value = "terraform"
  }

  labels {
    label = "forgeops.io/gate"
    value = "G05"
  }

  labels {
    label = "forgeops.io/role"
    value = "diagnostic-fixture"
  }
}
