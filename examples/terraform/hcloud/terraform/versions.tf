# TF setup

terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.48.1"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.7.0"
    }
  }
}
