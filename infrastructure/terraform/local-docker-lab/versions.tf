terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  backend "local" {
    path = "/home/tharuka/.local/state/forgeops/g05/terraform.tfstate"
  }

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.6.0"
    }
  }
}
