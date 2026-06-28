# Pre-shared k3s cluster token. Generated once and passed to BOTH the server
# (K3S_TOKEN) and the agents (K3S_TOKEN) so we never have to read the node-token
# back off the server — removes the otherwise-circular dependency. Stored in
# state (plaintext), which is why state is never committed. See specs/plan.md.
resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

# --- Control plane (cp1) -----------------------------------------------------

resource "local_file" "server_cloudinit" {
  content = templatefile("${path.module}/cloud-init/server.yaml.tftpl", {
    token = random_password.k3s_token.result
  })
  filename        = "${path.module}/.rendered/server.yaml"
  file_permission = "0600"
}

resource "multipass_instance" "cp1" {
  name           = var.server_name
  image          = var.ubuntu_image
  cpus           = var.server_cpus
  memory         = var.server_memory
  disk           = var.server_disk
  cloudinit_file = local_file.server_cloudinit.filename
}

# --- Workers (w1, w2) --------------------------------------------------------
# Each agent's cloud-init embeds cp1's IP, so these implicitly depend on cp1
# through local_file.agent_cloudinit referencing multipass_instance.cp1.ipv4.

resource "local_file" "agent_cloudinit" {
  for_each = toset(var.agent_names)

  content = templatefile("${path.module}/cloud-init/agent.yaml.tftpl", {
    server_ip = multipass_instance.cp1.ipv4
    token     = random_password.k3s_token.result
  })
  filename        = "${path.module}/.rendered/agent-${each.key}.yaml"
  file_permission = "0600"
}

resource "multipass_instance" "agent" {
  for_each = toset(var.agent_names)

  name           = each.key
  image          = var.ubuntu_image
  cpus           = var.agent_cpus
  memory         = var.agent_memory
  disk           = var.agent_disk
  cloudinit_file = local_file.agent_cloudinit[each.key].filename
}
