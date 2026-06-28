terraform {
  required_version = ">= 1.8"

  # State lives at a FIXED ABSOLUTE PATH outside the repo, deliberately:
  # a fresh checkout of mac_lab in any directory still finds the same state.
  # State holds the k3s token and kubeconfig private key in plaintext, so it is
  # NEVER committed to git. Back this file up occasionally (it is tiny); if it is
  # ever lost the resources are recoverable via `tofu import` (see specs/plan.md).
  # `tofu init` creates the file but not its parent dir — run once:
  #   mkdir -p ~/.local/state/mac_lab
  backend "local" {
    path = "/Users/hvo/.local/state/mac_lab/terraform.tfstate"
  }

  required_providers {
    multipass = {
      source  = "larstobi/multipass"
      version = "~> 1.4"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# The provider shells out to the `multipass` CLI, so the multipass binary must be
# on PATH (`brew install multipass`). No provider-level auth is required.
provider "multipass" {}

# The Helm provider is fed kubeconfig attributes parsed from the file that
# null_resource.fetch_kubeconfig pulls off cp1 (see kubeconfig.tf). Same spirit as
# the k8s_homelab tofu/providers.tf, which feeds the provider explicit
# host/cert/key instead of a kubeconfig path. On a first apply these values are
# "known after apply"; helm_release does not need the API at plan time, so the
# argocd release is simply deferred until the cluster exists.
provider "helm" {
  kubernetes = {
    host                   = local.kube_cluster.server
    cluster_ca_certificate = base64decode(local.kube_cluster["certificate-authority-data"])
    client_certificate     = base64decode(local.kube_user["client-certificate-data"])
    client_key             = base64decode(local.kube_user["client-key-data"])
  }
}
