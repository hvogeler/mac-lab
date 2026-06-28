output "server_ip" {
  description = "k3s control-plane (cp1) IP on the Multipass network."
  value       = multipass_instance.cp1.ipv4
}

output "agent_ips" {
  description = "k3s worker IPs on the Multipass network."
  value       = { for k, m in multipass_instance.agent : k => m.ipv4 }
}

output "kubeconfig_path" {
  description = "Kubeconfig written on the host."
  value       = local.kubeconfig_path
}

output "next_steps" {
  description = "What to do after apply."
  value       = <<-EOT

    Cluster is up. Next:

      export KUBECONFIG=${local.kubeconfig_path}
      kubectl get nodes -o wide          # expect cp1 + ${join(", ", var.agent_names)} Ready

    ArgoCD (ClusterIP until ingress-nginx exists):
      kubectl -n argocd port-forward svc/argocd-server 8080:80
      kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' | base64 -d ; echo

    Then confirm the Multipass subnet and pick a MetalLB pool (specs/plan.md Step 6):
      multipass list

    Finally seed the app-of-apps once it exists:
      kubectl apply -f ../apps/root.yaml
  EOT
}
