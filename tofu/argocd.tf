# ArgoCD is bootstrapped by OpenTofu — the ONE component ArgoCD does not manage
# itself ("who manages the manager?"). tofu owns this release; ArgoCD owns every
# Application under mac_lab/apps/. Do NOT also create a self-managing argo-cd
# Application — two controllers reconciling the same release will fight.
# Same pattern as k8s_homelab/tofu/argocd.tf.
#
# Service is ClusterIP on purpose: ArgoCD's ingress LoadBalancer IP does not exist
# until MetalLB + ingress-nginx are reconciled by ArgoCD itself. Reach the UI via
#   kubectl --kubeconfig ~/.kube/mac_lab -n argocd port-forward svc/argocd-server 8080:80
# Once ingress-nginx is up, enable the ingress block below and re-apply.
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_version
  atomic           = true
  wait             = true

  values = [
    yamlencode({
      server = {
        service = { type = "ClusterIP" }
        # ingress = {
        #   enabled          = true
        #   ingressClassName = "nginx"
        #   hostname         = "argocd.mac.lab"
        # }
      }
      configs = {
        params = {
          "server.insecure" = true
        }
      }
    })
  ]

  # Needs the cluster reachable and the kubeconfig fetched before the provider can act.
  depends_on = [null_resource.fetch_kubeconfig]
}

variable "argocd_version" {
  type = string
  # This is the argo-cd HELM CHART version (argoproj/argo-helm), NOT the ArgoCD app
  # version. Verified against the repo 2026-06-28: chart 9.7.1 ships ArgoCD app
  # v3.4.4 (latest in the 9.x line). Chart 10.0.0 also exists with the SAME app
  # v3.4.4 — a major CHART bump (likely breaking values changes) with no newer
  # ArgoCD, so we stay on 9.7.1. Re-verify before a deliberate bump:
  #   helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
  #   helm search repo argo/argo-cd --versions | head
  default = "9.7.1"
}
