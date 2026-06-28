# mac_lab — VM-based k3s cluster (Multipass + OpenTofu) — Plan & Tracker

> **Living document.** This is the running plan for `mac_lab`. We plan here first, then
> build, then tick items off. Update the Build Progress table and Findings as we go.
> Convert relative dates to absolute when noting completion.

## ⏯️ Resume here (status as of 2026-06-28)

Cluster is **up and verified** (Steps 0–7 ✅): 3 nodes Ready (k3s v1.36.2, Ubuntu 26.04
arm64), ArgoCD running (app v3.4.4). Multipass subnet `192.168.252.0/24`; MetalLB pool
chosen `192.168.252.240-250`.

The **`apps/` app-of-apps is scaffolded and `helm template`-validated** (Step 8 🔄):
`apps/root.yaml` (infra ApplicationSet → SSH remote), `apps/infra/metallb-system/` (umbrella
chart, L2-only, pool CRs on sync-wave 1), `apps/infra/ingress-nginx/` (umbrella chart,
LB IP pinned to `.240`).

**Next action (operator-run): bring up GitOps —**
1. Register a read-only ArgoCD repo credential (SSH deploy key) for
   `ssh://git@git.home.vogeler.cc/hvo/mac_lab.git`.
2. `git add apps/ && commit && push` (the ApplicationSet reads from the remote, not local).
3. `kubectl --kubeconfig ~/.kube/mac_lab apply -f apps/root.yaml` (one-time seed).
4. Watch `infra-metallb-system` then `infra-ingress-nginx` go Synced/Healthy.
5. Verify: `kubectl -n ingress-nginx get svc` → EXTERNAL-IP `192.168.252.240`; curl it from macOS.

Then Steps 9–11: local registry, CloudNativePG, sample workload end-to-end.

## Context

`mac_lab` is being repurposed from its original **k3d (k3s-in-Docker)** design to a
**Docker-free, VM-based** Kubernetes lab on a **MacBook Pro M5, 64 GB**. Nodes are real
Ubuntu VMs (Apple Virtualization.framework via **Multipass**), not containers. The cluster
is **k3s**: 1 control plane + 2 workers.

This deliberately mirrors the patterns proven in the sibling project
`~/Projects/k8s_homelab` (Talos/Proxmox), adapted to a laptop:

- **OpenTofu owns the cluster + the one component GitOps can't manage itself (ArgoCD).**
  In k8s_homelab, tofu owns the Cilium CNI bootstrap + the ArgoCD `helm_release`
  ("who manages the manager?"), and ArgoCD owns everything under `apps/`. We replicate
  that boundary here.
- **Everything else is GitOps.** MetalLB, ingress-nginx, the local registry, CNPG, etc. are
  ArgoCD-managed Applications, not tofu.

### Why Multipass + k3s (not k3d, not Lima)

- **No Docker** — the explicit goal. Multipass runs lightweight Ubuntu VMs on the native
  macOS hypervisor; 64 GB gives huge headroom.
- **k3s** is purpose-built for "1 server + N agents on small VMs"; single binary, built-in
  containerd + flannel CNI, trivial token join. Our manifests/Helm charts carry over from
  the k3d design unchanged (k3d was already k3s, minus Docker).
- **Multipass over Lima** specifically for **MetalLB**: Multipass puts VMs on a shared NAT
  network (typically `192.168.64.0/24`) that the **host can reach directly**, so MetalLB
  L2-mode LoadBalancer IPs are reachable from macOS with no extra setup. Lima needs
  `socket_vmnet` to achieve the same.

---

## Decisions locked

| Topic | Decision |
|---|---|
| Host | MacBook Pro **M5, 64 GB** (arm64) |
| Hypervisor | **Multipass** (Apple Virtualization.framework). No Docker. |
| VM provisioning | **OpenTofu** with the **`larstobi/multipass`** provider (`~> 1.4`) + cloud-init |
| K8s distro | **k3s** (built-in containerd + flannel) |
| Topology | **1 control plane (`cp1`) + 2 workers (`w1`, `w2`)** |
| Datastore | **Embedded etcd** (`--cluster-init`), so a control-plane node can be added later without re-init |
| Disabled k3s built-ins | `traefik` (use ingress-nginx) + `servicelb` (use MetalLB) |
| Node join | Pre-shared token via tofu `random_password` → passed to server (`K3S_TOKEN`) and agents. Removes the read-token-back dependency. |
| Server IP → agents | `multipass_instance.cp1.ipv4` (provider exports it) templated into agent cloud-init |
| LoadBalancer | **MetalLB** (L2), ArgoCD-managed. IP pool = a slice of the Multipass subnet outside its DHCP range — **TBD after first `multipass list`** |
| Ingress | **ingress-nginx**, ArgoCD-managed |
| GitOps engine | **ArgoCD**, bootstrapped by tofu `helm_release` (the ONE thing ArgoCD does not self-manage); app-of-apps owns the rest |
| Postgres | **CloudNativePG** (carried from the k3d stack), ArgoCD-managed |
| tofu state | `backend "local"` at a **fixed absolute path outside the repo** (`~/.local/state/mac_lab/terraform.tfstate`) so a checkout in any dir finds it. **Never committed** (holds token + kubeconfig key in plaintext). |
| Manual ops | Per project rule: Claude authors files; the **operator runs all cluster-mutating commands** (`tofu apply`, `multipass`, `kubectl apply`, `helm`). |

### Tentative VM sizing (64 GB host — adjust freely)

| Node | Role | vCPU | RAM | Disk |
|---|---|---|---|---|
| `cp1` | k3s server (control plane, etcd) | 2 | 4 GiB | 20 GiB |
| `w1` | k3s agent | 2 | 6 GiB | 20 GiB |
| `w2` | k3s agent | 2 | 6 GiB | 20 GiB |

~16 GB committed; macOS + tooling keep the rest. Ubuntu image: **24.04 LTS**.

---

## Target architecture

```
  macOS host (arm64, M5)                          Multipass NAT net (e.g. 192.168.64.0/24,
  - tofu / kubectl / helm                          host reaches VMs directly)
  - ~/.kube/mac_lab kubeconfig          ┌──────────────────────────────────────────────┐
        │                               │  cp1  k3s server --cluster-init (etcd)         │
        │  tofu apply ─────────────────▶│       --disable traefik,servicelb              │
        │                               │  w1   k3s agent ─┐                             │
        │                               │  w2   k3s agent ─┴─ join via shared token      │
        │                               │                                                │
        │  helm_release.argocd (tofu) ─▶│  argocd ns  (ClusterIP; port-forward at first) │
        │                               └──────────────────────────────────────────────┘
        │  kubectl apply -f apps/root.yaml (manual seed)
        ▼
   ArgoCD app-of-apps owns:  metallb → ingress-nginx → registry → cnpg → workloads
```

**Bootstrap order**

1. `tofu apply` → `random_password.k3s_token` → `cp1` (server) → `w1`,`w2` (agents) →
   fetch kubeconfig to `~/.kube/mac_lab` → `helm_release.argocd` (ClusterIP).
2. `kubectl apply -f apps/root.yaml` (manual, once) → ArgoCD reconciles MetalLB, then
   ingress-nginx (gets an LB IP from MetalLB's pool), then the rest.
3. ArgoCD reachable via `kubectl -n argocd port-forward svc/argocd-server 8080:80`
   until ingress-nginx + MetalLB are up; then switch to an ingress host.

> ArgoCD starts as **ClusterIP** on purpose — its ingress LB IP doesn't exist until
> MetalLB + ingress-nginx are reconciled *by ArgoCD itself*. No chicken-and-egg.

---

## Proposed repo structure

```
mac_lab/
├── README.md                 # rewrite: VM/k3s quick start (replaces k3d)
├── specs/
│   └── plan.md               # this file
├── tofu/                     # OpenTofu: Multipass VMs + k3s + ArgoCD bootstrap
│   ├── providers.tf          # multipass + helm + random + local + null; absolute-path local backend
│   ├── variables.tf
│   ├── terraform.tfvars      # node sizes, image, kubeconfig path
│   ├── vms.tf                # random_password token + cp1 + w1/w2 + rendered cloud-init
│   ├── kubeconfig.tf         # fetch /etc/rancher/k3s/k3s.yaml off cp1, rewrite 127.0.0.1→cp1 IP
│   ├── argocd.tf             # helm_release argocd (copied/adapted from k8s_homelab)
│   ├── outputs.tf            # node IPs, kubeconfig path, next-step hints
│   └── cloud-init/
│       ├── server.yaml.tftpl
│       └── agent.yaml.tftpl
└── apps/                     # [later] ArgoCD app-of-apps: metallb, ingress-nginx, registry, cnpg, ...
    └── root.yaml
```

---

## Build Progress

| Step | Status | Completed |
|---|---|---|
| **0** — Plan (this doc) | ✅ | 2026-06-28 |
| **1** — Prereqs: `brew install multipass`; `mkdir -p ~/.local/state/mac_lab` | ✅ | 2026-06-28 (multipass 1.16.3; init/plan ok) |
| **2** — Scaffold `tofu/` (providers, vms, cloud-init, kubeconfig, argocd, outputs) | ✅ | 2026-06-28 (fmt + `validate` pass; providers resolve) |
| **3** — `tofu init` + `tofu plan` review | ✅ | 2026-06-28 (plan reviewed, clean) |
| **4** — `tofu apply` → 3 VMs up, k3s server + agents joined | ✅ | 2026-06-28 (9 resources; launch blocked on cloud-init as hoped) |
| **5** — Verify: `kubectl --kubeconfig ~/.kube/mac_lab get nodes` → 3 Ready | ✅ | 2026-06-28 (k3s v1.36.2, Ubuntu 26.04 arm64) |
| **6** — Confirm Multipass subnet; set MetalLB IP pool range | ✅ | 2026-06-28 (subnet 192.168.252.0/24; pool 192.168.252.240-250) |
| **7** — ArgoCD up (tofu) + reachable via port-forward | ✅ | 2026-06-28 (7 pods Running, app v3.4.4) |
| **8** — `apps/` app-of-apps: MetalLB → ingress-nginx | 🔄 | 2026-06-28 files scaffolded + `helm template` validated; pending: register repo cred → push → seed |
| **9** — Local registry (Helm/ArgoCD) | 🔲 | — |
| **10** — CloudNativePG (Helm/ArgoCD) | 🔲 | — |
| **11** — Sample workload end-to-end (ingress + LB IP reachable from host) | 🔲 | — |

Legend: 🔲 planned · 🔄 in progress · ✅ done

---

## Open items to confirm (non-blocking — default as noted)

1. **MetalLB IP pool** — ✅ resolved 2026-06-28. Subnet `192.168.252.0/24` (host `.1` on
   bridge100; VMs `.2`–`.4`). Pool = **`192.168.252.240-192.168.252.250`** (high slice, clear
   of DHCP-allocated low addresses, reachable from macOS).
2. **ArgoCD chart version** — ✅ pinned `9.7.1` (app v3.4.4), verified against the repo
   2026-06-28. Chart 10.0.0 exists (same app v3.4.4, major chart bump) — deferred.
3. **Registry** — in-cluster registry (Helm chart) vs Multipass-host registry. *Default:* in-cluster.
4. **kubeconfig merge** — keep a standalone `~/.kube/mac_lab` file (set `KUBECONFIG` /
   `--kubeconfig`) vs merge a `mac-lab` context into `~/.kube/config`. *Default:* standalone file.

---

## Findings (surprises vs the plan)

- **`larstobi/multipass` resource exports `ipv4`** (read-only) — so agents reference
  `multipass_instance.cp1.ipv4` directly for their join config and the kubeconfig rewrite;
  no data source needed. Resource args: `name`, `image`, `cpus`, `memory` (string e.g.
  `"4GiB"`), `disk`, `cloudinit_file`. Provider resolved to v1.4.3.
- **tfvars vs variables.tf was redundant** — originally every sizing knob had a default in
  `variables.tf` AND a value in `terraform.tfvars` (two-places-must-match drift). Fixed:
  `variables.tf` declares type+description with **no defaults**; `terraform.tfvars` is the
  single source of values. `argocd_version` is the one exception — a pinned constant living
  only in `argocd.tf`.
- **Ubuntu LTS choice** — use the current LTS, never interim releases. 26.04 LTS (Resolute
  Raccoon, 2026-04-23) confirmed available in `multipass find` (alias `resolute`/`lts`).
  Pinned the explicit `26.04`, not the `lts` alias, so it can't silently float to 28.04 and
  trigger a surprise rebuild.
- **ArgoCD chart** — repo `argoproj/argo-helm`, chart `argo-cd`. Latest is `10.0.0` but it's
  a major CHART bump (likely breaking values) with the SAME app v3.4.4 as `9.7.1`; pinned
  `9.7.1`.

---

## State recovery (break-glass)

State is a fixed local file outside the repo, never in git. If it is lost, the running
cluster can be re-imported rather than rebuilt:

- `tofu import multipass_instance.cp1 cp1` (and `w1`, `w2`)
- `tofu import helm_release.argocd argocd/argocd`
- `tofu import random_password.k3s_token <token>` — the token is readable on the server at
  `/var/lib/rancher/k3s/server/token`.

Easier than relying on this: keep an occasional backup copy of the tiny state file.
