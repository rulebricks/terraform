variable "location" {
  description = "The Azure region to deploy to."
  default     = "East US"
}

variable "cluster_name" {
  description = "The name of the AKS cluster."
  default     = "rulebricks-cluster"
}

variable "node_group_name" {
  description = "The name of the node pool."
  default     = "rulebricks"
}

variable "vm_size" {
  description = "VM size for the nodes."
  default     = "Standard_D4ps_v5"  # ARM-based instance (Ampere Altra)
}

variable "node_count" {
  description = "Desired number of worker nodes."
  default     = 1
}

variable "max_count" {
  description = "Maximum number of worker nodes."
  default     = 4
}

variable "min_count" {
  description = "Minimum number of worker nodes."
  default     = 1
}

variable "vnet_cidr" {
  description = "Custom VNet CIDR block. If not specified, defaults to 10.0.0.0/16"
  type        = string
  default     = ""
}

variable "resource_group_name" {
  description = "The name of the resource group."
  default     = "rulebricks-rg"
}
