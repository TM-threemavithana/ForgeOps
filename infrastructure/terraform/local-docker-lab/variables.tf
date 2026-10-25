variable "docker_host" {
  description = "Docker daemon socket or endpoint URL. Defaults to the standard WSL2 Linux socket."
  type        = string
  default     = null
}

variable "network_name" {
  description = "Name of the isolated Docker bridge network for G05 IaC fixture."
  type        = string
  default     = "forgeops-iac-lab"
}

variable "container_name" {
  description = "Name of the disposable diagnostic container."
  type        = string
  default     = "forgeops-diag-fixture"
}

variable "fixture_image" {
  description = "Diagnostic HTTP container image pinned to a verified official registry digest."
  type        = string
  default     = "nginx:1.30.6-alpine@sha256:47928bf67eb62a1863cb08d9ecb52d3e704304ba614eaee17884204677702951"

  validation {
    condition     = can(regex("@sha256:[a-f0-9]{64}$", var.fixture_image))
    error_message = "The fixture_image must be pinned to an immutable registry sha256 digest."
  }
}

variable "host_port" {
  description = "Loopback host port bound to the diagnostic container HTTP port 80."
  type        = number
  default     = 8089

  validation {
    condition     = var.host_port >= 1024 && var.host_port <= 65535
    error_message = "The host_port must be an unprivileged port between 1024 and 65535."
  }
}

variable "host_ip" {
  description = "Loopback interface IP address for container port publishing. Never bind to 0.0.0.0."
  type        = string
  default     = "127.0.0.1"

  validation {
    condition     = var.host_ip == "127.0.0.1" || var.host_ip == "localhost"
    error_message = "The host_ip must strictly bind to loopback (127.0.0.1 or localhost) to prevent public exposure."
  }
}

variable "memory_limit_mb" {
  description = "Memory limit in megabytes assigned to the diagnostic container."
  type        = number
  default     = 128

  validation {
    condition     = var.memory_limit_mb >= 32 && var.memory_limit_mb <= 1024
    error_message = "The memory_limit_mb must be bounded between 32MB and 1024MB."
  }
}

variable "cpu_shares" {
  description = "Relative CPU weight (shares) allocated to the diagnostic container."
  type        = number
  default     = 512

  validation {
    condition     = var.cpu_shares >= 128 && var.cpu_shares <= 2048
    error_message = "The cpu_shares must be between 128 and 2048."
  }
}
