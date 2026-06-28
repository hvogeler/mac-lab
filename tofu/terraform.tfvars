# Node sizing for a MacBook Pro M5 (64 GB). Adjust freely — ~16 GB committed here.
# 26.04 LTS (Resolute Raccoon, released 2026-04-23, supported to 2031) is the current LTS.
# Confirm Multipass actually ships it before apply:  multipass find
# If not yet published, fall back to "24.04".
ubuntu_image = "26.04"

server_name   = "cp1"
server_cpus   = 2
server_memory = "4GiB"
server_disk   = "20GiB"

agent_names  = ["w1", "w2"]
agent_cpus   = 2
agent_memory = "6GiB"
agent_disk   = "50GiB"

kubeconfig_path = "~/.kube/mac_lab"
