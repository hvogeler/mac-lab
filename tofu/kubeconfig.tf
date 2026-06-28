# Pull the kubeconfig off cp1 and rewrite the loopback server address to cp1's
# reachable IP. k3s automatically includes the node IP in the API server cert
# SANs, so connecting over that IP validates without an explicit --tls-san.
# The retry loop guards against the kubeconfig not being written the instant
# cloud-init's runcmd returns.
resource "null_resource" "fetch_kubeconfig" {
  depends_on = [multipass_instance.cp1]

  # Re-fetch if cp1 is replaced (new IP).
  triggers = {
    server_ip = multipass_instance.cp1.ipv4
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      mkdir -p "$(dirname '${local.kubeconfig_path}')"
      for i in $(seq 1 30); do
        if multipass exec ${var.server_name} -- sudo test -f /etc/rancher/k3s/k3s.yaml; then
          multipass exec ${var.server_name} -- sudo cat /etc/rancher/k3s/k3s.yaml \
            | sed 's#127.0.0.1#${multipass_instance.cp1.ipv4}#' > '${local.kubeconfig_path}'
          chmod 600 '${local.kubeconfig_path}'
          echo "wrote kubeconfig to ${local.kubeconfig_path}"
          exit 0
        fi
        echo "waiting for k3s kubeconfig on ${var.server_name}... ($i/30)"
        sleep 5
      done
      echo "timed out waiting for k3s kubeconfig" >&2
      exit 1
    EOT
  }
}

# Read the kubeconfig back so the helm provider can be configured from it.
# depends_on defers the read to apply time, after fetch_kubeconfig has written it.
data "local_file" "kubeconfig" {
  depends_on = [null_resource.fetch_kubeconfig]
  filename   = local.kubeconfig_path
}

locals {
  kubeconfig_path = pathexpand(var.kubeconfig_path)
  kubeconfig      = yamldecode(data.local_file.kubeconfig.content)
  kube_cluster    = local.kubeconfig.clusters[0].cluster
  kube_user       = local.kubeconfig.users[0].user
}
