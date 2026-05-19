# Operating the mac-lab cluster

Day-to-day commands for running, suspending, and tearing down the lab.
For architecture and "what to build next" see [`plan.md`](plan.md).

## Daily lifecycle

### Suspend the cluster (overnight, between sessions)

```bash
k3d cluster stop mac-lab
```

Stops every container (server, agents, serverlb, registry) but keeps:

- The Docker network `k3d-mac-lab` (and its subnet `172.19.0.0/16`)
- All container filesystems → ArgoCD state, Helm releases, MetalLB config,
  ingress-nginx pods, workload data, **everything**

Prefer this over `docker stop` directly — k3d handles container ordering
and the registry container that's tied to the cluster.

### Resume the cluster

```bash
# Make sure Docker Desktop is running first.
k3d cluster start mac-lab

# Pods take a minute or two to settle:
kubectl get pods -A -w
```

### Full teardown (destroys state)

```bash
./cluster/scripts/delete.sh
# equivalent: k3d cluster delete mac-lab
```

Wipes the cluster, the registry, and the Docker network. After this you
re-bootstrap from scratch (see `plan.md` for the order).

### Recreate from scratch

Everything below assumes you've just deleted the cluster (or never had one
on this machine) and want to bring it back from this repo. The cluster
state is gone — Helm releases, ArgoCD password, pushed images, all of it —
but the **manifests in Git are the source of truth**, so the cluster will
look the same once it converges.

**1. Recreate the cluster (k3s containers + registry + Docker network):**

```bash
./cluster/scripts/create.sh
# equivalent: k3d cluster create --config cluster/k3d-config.yaml
```

Pulls `rancher/k3s:v1.35.4-k3s1` and `registry:2` if not cached. Takes
1–3 minutes the first time, ~30s after that.

**2. Check the Docker subnet — it may have changed:**

```bash
docker network inspect k3d-mac-lab \
  --format '{{range .IPAM.Config}}{{.Subnet}}{{"\n"}}{{end}}'
```

- If it's still `172.19.0.0/16` → MetalLB pool in the repo is valid; skip to
  step 3.
- If it's different (say `172.20.0.0/16`) → edit
  `deployments/addons/metallb/config/pool.yaml` to use a range inside the
  new subnet (e.g. `172.20.255.200-172.20.255.250`), commit, and push
  **before** continuing. ArgoCD will read this from `main`, so the change
  has to be on GitHub before MetalLB syncs.

**3. Verify the cluster is healthy:**

```bash
kubectl config use-context k3d-mac-lab
kubectl get nodes                  # 3 nodes, Ready
kubectl get pods -A                # coredns + metrics-server + local-path-provisioner; no traefik, no svclb
```

**4. Bootstrap ArgoCD via Helm (one-time per recreate):**

```bash
helm repo add argo https://argoproj.github.io/argo-helm   # idempotent
helm repo update
helm install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --version 9.5.14 \
  -f deployments/addons/argocd/values.yaml
```

**5. Wait for ArgoCD to come up:**

```bash
kubectl -n argocd rollout status deploy/argocd-server --timeout=5m
```

**6. Create the Postgres admin secret (not stored in Git):**

```bash
kubectl create namespace postgres
kubectl create secret generic postgres-admin-secret \
  --from-literal=username=admin \
  --from-literal=password=<your-password> \
  -n postgres
```

This must exist before ArgoCD syncs the `postgres-cluster` application,
otherwise CNPG cannot complete the `initdb` bootstrap.

**7. Apply the root Application to hand control to GitOps:**

```bash
kubectl apply -f deployments/argocd/apps/root.yaml
```

From this point onward, ArgoCD watches `deployments/argocd/apps/` in the
repo and reconciles everything else: `argocd-self`, `metallb`,
`metallb-config`, `ingress-nginx`, `cloudnativepg`, `postgres-cluster`,
and any future apps.

**8. Watch the cascade:**

```bash
kubectl -n argocd get applications -w
```

Wait until all of these report `Synced / Healthy`:

- `root`
- `argocd`           (ArgoCD adopting its own Helm release)
- `metallb`          (chart)
- `metallb-config`   (IPAddressPool + L2Advertisement — may retry once or twice while CRDs land)
- `ingress-nginx`    (DaemonSet pod per node on hostPort 80/443)
- `cloudnativepg`    (CNPG operator in `cnpg-system`)
- `postgres-cluster` (Postgres pod in `postgres` — comes up after CNPG operator is ready)

**9. Get the new admin password and reach the UI:**

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Browse to `https://argocd.localhost:8543`. The admin password regenerates
on every recreate; any previous password you remembered is gone.

### Connecting to Postgres from macOS

Once the cluster is running, connect directly on `localhost:5432`:

```bash
psql -h localhost -p 5432 -U admin -d labdb
```

The path is: `macOS localhost:5432 → k3d serverlb → ingress-nginx TCP passthrough → Postgres`

This relies on the `5432:5432` port mapping in `k3d-config.yaml` and the
`tcp-services` ConfigMap in `deployments/addons/ingress-nginx/`. Both are
applied automatically on cluster create and ArgoCD sync — no manual steps needed.

### What does *not* come back automatically

- **Postgres admin secret** — recreate it manually (see step 6 above).
  Without it the `postgres-cluster` application will stall on `initdb`.
- **Locally-built images** in the registry — push them again
  (`docker push localhost:5001/<name>:<tag>`).
- **Any one-off `kubectl apply` you did outside Git** — by design.
  GitOps means "if it's not in the repo, it doesn't exist."
- **Browser HSTS / cert-trust state for `argocd.localhost`** — usually
  harmless; if Chrome misbehaves see the Troubleshooting table.

## Reaching the cluster

### Kubeconfig

k3d merges into your default kubeconfig and switches context on create.
Switch back manually:

```bash
kubectl config use-context k3d-mac-lab
```

### ArgoCD UI

- URL: `https://argocd.localhost:8543`
- User: `admin`
- Password:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d; echo
  ```

If the Ingress is broken for any reason, fall back to port-forward:

```bash
kubectl -n argocd port-forward svc/argocd-server 8081:80
# → http://localhost:8081   (note: HTTP, because server.insecure: true)
```

## Common verification commands

```bash
# Cluster + nodes
kubectl get nodes -o wide
docker ps --filter name=k3d-mac-lab --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# ArgoCD Applications
kubectl -n argocd get applications

# MetalLB
kubectl -n metallb-system get pods
kubectl -n metallb-system get ipaddresspool,l2advertisement

# ingress-nginx
kubectl -n ingress-nginx get pods -o wide
kubectl -n ingress-nginx get svc       # EXTERNAL-IP from the MetalLB pool
kubectl get ingressclass               # 'nginx' should be (default)

# Local registry
curl -s http://localhost:5001/v2/_catalog

# CloudNativePG
kubectl -n cnpg-system get pods
kubectl -n postgres get cluster
kubectl -n postgres get pods
```

## Force ArgoCD to re-poll Git

ArgoCD polls every ~3 minutes. To trigger immediately:

```bash
# Single app — replace <name> (e.g. argocd, root, ingress-nginx)
kubectl -n argocd annotate application <name> \
  argocd.argoproj.io/refresh=hard --overwrite

# Or in the UI: select the Application -> Refresh / Hard Refresh
```

## Network notes

- **Docker subnet** (`172.19.0.0/16`) persists across `stop/start`. It only
  changes if you `delete` and recreate the network.
- **MetalLB pool** is pinned to `172.19.255.200–250` and depends on the
  subnet above staying the same.
- **Host port mappings** from `cluster/k3d-config.yaml`:
  - `8580 → 80` (HTTP into ingress-nginx via k3d serverlb)
  - `8543 → 443` (HTTPS into ingress-nginx via k3d serverlb)
  - `5001 → 5000` (local registry on `localhost:5001`)
- **DNS for `*.localhost`** is handled by macOS mDNSResponder, no
  `/etc/hosts` entry needed. If a host stops resolving, add:
  ```
  127.0.0.1   argocd.localhost
  ```

## Troubleshooting one-liners

| Symptom | Try |
|---|---|
| `https://argocd.localhost:8543` connection refused | `kubectl -n ingress-nginx get pods -o wide` — DaemonSet pod per node? |
| Browser stuck on "Your connection is not private" | Type `thisisunsafe` in Chrome, or use Firefox/Safari, or clear HSTS at `chrome://net-internals/#hsts` |
| Application stuck `OutOfSync` | Hard refresh (see above); then `kubectl -n argocd get app <name> -o yaml | grep -A10 status:` |
| `metallb-config` failing with "no matches for kind IPAddressPool" | Wait for MetalLB chart to install CRDs; the retry block will catch up |
| Pods in `ImagePullBackOff` from `localhost:5001/...` | Confirm `curl http://localhost:5001/v2/_catalog` lists the image |
