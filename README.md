# mac_lab

A local Kubernetes lab on a **MacBook Pro M5 (64 GB)** — **no Docker**. Nodes are real
Ubuntu VMs on Apple's native hypervisor via **Multipass**, running **k3s**
(1 control plane + 2 workers, embedded etcd).

**Infrastructure as code, GitOps from the start:**

- **OpenTofu** (`larstobi/multipass` provider + cloud-init) provisions the VMs, installs
  k3s, and bootstraps **ArgoCD** — the one component ArgoCD can't manage itself.
- **ArgoCD** owns everything else as an app-of-apps: **MetalLB** (LoadBalancer IPs),
  **ingress-nginx**, a local registry, **CloudNativePG**, and workloads.

This mirrors the patterns from the sibling Talos/Proxmox project `~/Projects/k8s_homelab`,
adapted to a laptop.

## Layout

- `specs/plan.md` — the living plan & progress tracker. **Start here.**
- `tofu/` — OpenTofu: Multipass VMs + k3s + ArgoCD bootstrap.
- `apps/` — ArgoCD app-of-apps (added after the cluster is up).

## Prerequisites

`brew install multipass` · `tofu` · `kubectl` · `helm`
