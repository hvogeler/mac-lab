# mac_lab — VM-based k3s cluster (Multipass + OpenTofu) — Plan & Tracker

> **Living document.** This is the running plan for `mac_lab`. We plan here first, then
> build, then tick items off. Update the Build Progress table and Findings as we go.
> Convert relative dates to absolute when noting completion.

## ⏯️ Resume here (paused evening 2026-06-28)

### TL;DR to say tomorrow morning
> "Good morning — resume mac_lab. First explain the CoreDNS DNS issue to me simply (I didn't
> get it last night), then let's discuss my 3 open questions BEFORE applying anything."

**Do NOT apply anything on resume until we've discussed the 3 questions below.** The CoreDNS
fix is staged in `bootstrap/coredns-custom.yaml` but has NOT been applied.

### Where we are
- Cluster **up and verified** (Steps 0–7 ✅): 3 nodes Ready (k3s v1.36.2, Ubuntu 26.04 arm64),
  ArgoCD running (app v3.4.4). Subnet `192.168.252.0/24`; MetalLB pool `192.168.252.240-250`.
- `apps/` scaffolded + `helm template`-validated: `apps/root.yaml` now has **two** ApplicationSets
  (`infra` + `platform`), `apps/infra/metallb-system/`, `apps/infra/ingress-nginx/`.
- `root.yaml` **already applied** to the cluster; both ApplicationSets exist.
- Repo credential **already done**: deploy key generated in gitignored `secrets/`, public key
  added as a read-only Forgejo deploy key, `repo-mac-lab` repository Secret applied to argocd ns.

### THE CURRENT BLOCKER (Step 8 🔄)
The ApplicationSets generate **zero** Applications because in-cluster DNS (CoreDNS) cannot
resolve `git.home.vogeler.cc`. See the Findings entry "In-cluster DNS can't resolve internal
homelab zones". The node resolves it; CoreDNS forwards to an upstream that only knows public
names → NXDOMAIN. Fix is staged but unapplied: `bootstrap/coredns-custom.yaml`.

### Pending apply steps (ONLY after we agree the approach)
```bash
export KUBECONFIG=~/.kube/mac_lab
kubectl apply -f bootstrap/coredns-custom.yaml
kubectl -n kube-system rollout restart deploy coredns
kubectl -n kube-system rollout status deploy coredns
kubectl -n argocd exec deploy/argocd-repo-server -- nslookup git.home.vogeler.cc   # expect 192.168.4.60
kubectl -n argocd rollout restart deploy argocd-applicationset-controller
kubectl -n argocd get applications      # expect infra-metallb-system, infra-ingress-nginx to appear & sync
```
Then verify ingress LB: `kubectl -n ingress-nginx get svc` → EXTERNAL-IP `192.168.252.240`,
`curl -I http://192.168.252.240` (nginx 404). Then Steps 9–11 (registry, CNPG, sample app).

### 🗣️ 3 open questions to DISCUSS FIRST on resume (then implement what we decide)
1. **Re-explain CoreDNS simply.** User didn't follow the DNS explanation when tired. Start here,
   plain-language, before anything else.
2. **Zero-manual-step rebuild (user's core expectation).** Goal: `wipe whole cluster → recreate
   entirely from the mac_lab repo with NO manual steps in between`. User is worried about all the
   one-off "bootstrap" kubectl applies (repo cred, coredns-custom, ArgoCD). My take to present:
   this IS achievable — the fix is to make **tofu** the single reproducible bootstrapper (it
   already is for VMs+k3s+ArgoCD; fold in the coredns ConfigMap via the `hashicorp/kubernetes`
   provider, and inject the repo credential into the ArgoCD `helm_release` values from the
   local key file). "tofu apply" is not a manual step in the worrying sense — it's the
   reproducible entrypoint. Only truly un-GitOps-able thing is the very first private key, which
   tofu reads from a local (uncommitted) file. End state: `tofu destroy && tofu apply` rebuilds
   everything, ArgoCD pulls the rest. See also the earlier sealed-secrets discussion.
3. **Cilium instead of flannel + MetalLB (like the Talos homelab)?** Yes, possible: install k3s
   with `--flannel-backend=none --disable-network-policy --disable=servicelb`, then install
   Cilium (kube-proxy replacement + LB-IPAM + L2 announcements + Hubble), CNI bootstrapped by
   tofu (nodes stay NotReady until CNI is up — same as homelab). Trade-off: one unified layer +
   consistency with homelab + better observability, vs. more complex bootstrap. flannel+MetalLB
   is simpler and already working. NOTE: this is orthogonal to the CoreDNS fix (DNS issue exists
   either way). Decide alongside Q2 since both reshape the k3s install / tofu bootstrap.

> **Bootstrap secret note (still relevant):** the ArgoCD repo Secret uses
> `insecureIgnoreHostKey: "true"` (fine on a trusted LAN); harden later via
> `argocd-ssh-known-hosts-cm` (`multipass exec cp1 -- ssh-keyscan git.home.vogeler.cc`).

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
- **In-cluster DNS can't resolve internal homelab zones (2026-06-28).** k3s CoreDNS
  (`forward . /etc/resolv.conf`) forwards to an upstream that only knows PUBLIC names, so pods
  get NXDOMAIN for `git.home.vogeler.cc` (and any `*.home.vogeler.cc`/`hvo.lan`/`infra.vogeler.cc`).
  The NODE resolves them fine via its real uplink `192.168.252.1` (Multipass bridge). Symptom:
  ApplicationSets generated zero apps — `failed to list refs: ... lookup git.home.vogeler.cc ...
  no such host`. NOT an auth problem (repo cred was fine). Fix = `bootstrap/coredns-custom.yaml`
  (coredns-custom ConfigMap forwarding the 3 internal zones to `192.168.252.1`) + restart
  coredns. Bootstrap concern — must precede ArgoCD pulling the repo, so applied out-of-band;
  TODO: fold into tofu (`hashicorp/kubernetes` provider) for reproducibility.

---

## State recovery (break-glass)

State is a fixed local file outside the repo, never in git. If it is lost, the running
cluster can be re-imported rather than rebuilt:

- `tofu import multipass_instance.cp1 cp1` (and `w1`, `w2`)
- `tofu import helm_release.argocd argocd/argocd`
- `tofu import random_password.k3s_token <token>` — the token is readable on the server at
  `/var/lib/rancher/k3s/server/token`.

Easier than relying on this: keep an occasional backup copy of the tiny state file.
