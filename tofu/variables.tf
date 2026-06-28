# All values are set in terraform.tfvars (the single source of truth). These
# declarations intentionally carry NO defaults, so a missing/edited tfvars fails
# loudly rather than silently falling back to a stale default.

variable "ubuntu_image" {
  type        = string
  description = "Multipass image alias for all nodes."
}

variable "server_name" {
  type        = string
  description = "Name of the k3s control-plane VM."
}

variable "agent_names" {
  type        = list(string)
  description = "Names of the k3s worker VMs."
}

variable "server_cpus" {
  type        = number
  description = "vCPUs for the control-plane VM."
}

variable "server_memory" {
  type        = string
  description = "RAM for the control-plane VM (unit suffix, e.g. 4GiB)."
}

variable "server_disk" {
  type        = string
  description = "Disk for the control-plane VM (unit suffix, e.g. 20GiB)."
}

variable "agent_cpus" {
  type        = number
  description = "vCPUs per worker VM."
}

variable "agent_memory" {
  type        = string
  description = "RAM per worker VM (unit suffix, e.g. 6GiB)."
}

variable "agent_disk" {
  type        = string
  description = "Disk per worker VM (unit suffix, e.g. 50GiB)."
}

variable "kubeconfig_path" {
  type        = string
  description = "Where to write the cluster kubeconfig on the host. ~ is expanded."
}
