# mac_lab — k3d learning cluster
# to be replaced

A local Kubernetes playground built on [k3d](https://k3d.io) (k3s in Docker) for
experimenting with cluster operations, addons, and application deployments.

## Folder structure

```
mac_lab/
├── README.md                          # this file
├── cluster/                           # cluster lifecycle & configuration
│   ├── k3d-config.yaml                # declarative k3d cluster definition
│   └── scripts/
│       ├── create.sh                  # create cluster from config
│       └── delete.sh                  # tear cluster down
└── deployments/                       # everything that runs *on* the cluster
    ├── apps/                          # application workloads
    │   └── nginx/
    │       └── deployment.yaml        # sample nginx Deployment + Service
    └── addons/                        # cluster-level addons (ingress, monitoring, …)
```

### Why this split?

- **`cluster/`** — concerns the *existence and shape* of the cluster itself
  (node count, ports, k3s flags, registries). Edit here when you want a
  different cluster.
- **`deployments/apps/`** — workloads you would also run in a real cluster
  (web apps, APIs, demos). One folder per app.
- **`deployments/addons/`** — platform-level components that extend the
  cluster (ingress-nginx, cert-manager, Prometheus, ArgoCD, …). One folder
  per addon.

## Prerequisites

- Docker Desktop (or any Docker-compatible runtime)
- [`k3d`](https://k3d.io/#installation) — `brew install k3d`
- [`kubectl`](https://kubernetes.io/docs/tasks/tools/) — `brew install kubectl`

## Quick start

```bash
# 1. create the cluster
./cluster/scripts/create.sh

# 2. verify
kubectl get nodes

# 3. deploy the sample nginx app
kubectl apply -f deployments/apps/nginx/deployment.yaml
kubectl port-forward svc/nginx 8000:80
# → http://localhost:8000

# 4. tear down when done
./cluster/scripts/delete.sh
```

## Cluster details (from `cluster/k3d-config.yaml`)

- Name: `mac-lab`
- 1 server + 2 agent nodes
- Built-in Traefik **disabled** so you can install your own ingress
- Host ports: `8580 → 80`, `8543 → 443` on the loadbalancer
- Kubeconfig is merged and the context is switched automatically

---

## Stack

| Component | Purpose |
|---|---|
| k3d | k3s in Docker — 1 server + 2 agent nodes |
| MetalLB | LoadBalancer IPs from the Docker bridge subnet |
| ingress-nginx | HTTP/HTTPS ingress |
| ArgoCD | GitOps controller — watches this repo |
| CloudNativePG | Postgres operator |

## Bootstrapping a fresh cluster

The Quick Start above creates the cluster and deploys the sample app only.
To bring up the full GitOps stack see **[`specs/operation.md`](specs/operation.md)** — specifically the *Recreate from scratch* section.

The one step that cannot come from Git is the Postgres admin secret. Create
it before applying `root.yaml`:

```bash
kubectl create namespace postgres
kubectl create secret generic postgres-admin-secret \
  --from-literal=username=admin \
  --from-literal=password=<your-password> \
  -n postgres
```

Then apply the root ArgoCD application and let it converge:

```bash
kubectl apply -f deployments/argocd/apps/root.yaml
kubectl -n argocd get applications -w
```
