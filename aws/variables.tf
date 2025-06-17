variable "region" {
  description = "The AWS region to deploy to."
  default     = "us-west-1"
}

variable "cluster_name" {
  description = "The name of the EKS cluster."
  default     = "rulebricks-cluster"
}

variable "node_group_name" {
  description = "The name of the node group."
  default     = "rulebricks-node-group"
}

variable "node_instance_type" {
  description = "EC2 instance type for the nodes."
  default     = "c8g.large" # ARM-based instance
}

variable "desired_capacity" {
  description = "Desired number of worker nodes."
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of worker nodes."
  default     = 4
}

variable "min_capacity" {
  description = "Minimum number of worker nodes."
  default     = 1
}

variable "vpc_cidr" {
  description = "Custom VPC CIDR block. If not specified, defaults to 10.0.0.0/16"
  type        = string
  default     = ""
}
