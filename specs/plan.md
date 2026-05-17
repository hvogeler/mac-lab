# Plan the playground cluster

## Nodes

This cluster has 3 nodes:

1. One control node
2. Two agent nodes

## Basic services

Instead of the default traefik ingress it shoud have ingress-nginx deployed.
Instead of the default serviceLB it should metallb deployed
It should have a registry:2 deployed so we can keep images locally
It should have ArgoCD deployed and activated. All cluster configuration should use a gitops workflow.

## Order

After creating the cluster first create the ArgoCD deployment and let us create the github project for ArgoCD to use.

## Process

Please never execute any commands that manipulate the cluster. Always tell me what to do and i will do it manually to learn.

---

## Status (as of 2026-05-17)

Bootstrapped and working:

- [x] k3d cluster `mac-lab` (1 server + 2 agents, k3s v1.35.4)
  - Built-in Traefik disabled
  - Built-in servicelb disabled (replaced by MetalLB)
  - Host ports `8580 → 80`, `8543 → 443` via k3d serverlb
- [x] Local image registry `mac-lab-registry` on `localhost:5001` (k3d-managed)
- [x] ArgoCD installed via Helm chart 9.5.14
  - Self-managed via Application `argocd` (chart + values from this repo)
  - App-of-apps `root` watches `deployments/argocd/apps/`
  - Reachable at `https://argocd.localhost:8543` via ingress-nginx
- [x] MetalLB Helm chart 0.15.3
  - IP pool `172.19.255.200–250` (within the `k3d-mac-lab` Docker subnet `172.19.0.0/16`)
- [x] ingress-nginx Helm chart 4.15.1
  - DaemonSet with `hostPort: 80/443` so the k3d serverlb routes into it directly
  - Marked as the cluster's default `IngressClass`

Repository layout in use:

```
deployments/
├── addons/        # Helm values (and any chart-supplemental CRs) per addon
├── apps/          # workload manifests
└── argocd/apps/   # ArgoCD Application definitions — root watches this dir
```

## Next moves (pick up here tomorrow)

### 0. Explain the deployments of metallb and ingress-nginx in detail

### 1. cert-manager + locally-trusted CA

Goal: stop bypassing browser cert warnings on `argocd.localhost`.

- Install `cert-manager` Helm chart as an Argo Application under
  `deployments/addons/cert-manager/`
- Use `mkcert -install` on the Mac to add a local CA to the macOS keychain
- Create a `ClusterIssuer` backed by that CA (load the mkcert root cert as a
  Secret in `cert-manager` namespace)
- Update the ArgoCD Ingress to reference a `Certificate` (or use the chart's
  `tls.secretName` + cert-manager annotations) so it serves a cert signed by
  the local CA
- Verify: `https://argocd.localhost:8543` loads in Chrome with no warning

### 2. Sample nginx app via GitOps

Goal: prove the end-to-end GitOps loop with a real workload, not just
platform components.

- Wrap the existing `deployments/apps/nginx/deployment.yaml` in an Argo
  Application at `deployments/argocd/apps/nginx.yaml`
- Add an `Ingress` for the nginx Service on `nginx.localhost`
- Verify: `curl https://nginx.localhost:8543` returns the nginx welcome page
- Then: edit `replicas` in the manifest, push, watch ArgoCD reconcile

### 3. Push and consume a local image

Goal: exercise the `mac-lab-registry` we set up in the k3d config.

- Build a trivial image (e.g. a tiny Go or static-site container)
- Tag and push to `localhost:5001/<name>:<tag>`
- Reference it from a Deployment under `deployments/apps/`
- Verify the pod pulls from `mac-lab-registry`, not Docker Hub
- (Decide whether to use the registry for the nginx app above or a separate
  hello-world)

## Possible later additions

Not committed — capture ideas here as they come up.

- Prometheus + Grafana (kube-prometheus-stack) for observability
- ExternalDNS or Coredns customizations for `*.localhost` host resolution
- ApplicationSet experiments
- NetworkPolicy basics
- A stateful workload (Postgres, MinIO) to learn PVCs / local-path-provisioner

## Decisions log

- 2026-05-17 — Use Helm charts (not raw manifests) for all addons. Reason:
  closer to real-world distribution, easier to learn values files.
- 2026-05-17 — argocd-server runs in `--insecure` (HTTP) behind ingress-nginx
  TLS termination. Reason: ArgoCD docs recommend this over re-encrypt, gRPC
  paths are more reliable.
- 2026-05-17 — MetalLB installed even though not on the data path for
  ingress-nginx (the k3d serverlb + DaemonSet hostPort handles that). Reason:
  matches the plan; lets other Services experiment with `type: LoadBalancer`.
