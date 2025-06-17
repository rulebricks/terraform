locals {
  kubeconfig = templatefile("${path.module}/kubeconfig.tpl", {
    cluster_name                       = module.eks.cluster_name
    cluster_endpoint                   = module.eks.cluster_endpoint
    cluster_certificate_authority_data = module.eks.cluster_certificate_authority_data
    region                             = var.region
  })
}

output "load_balancer_security_group_id" {
  description = "ID of the Load Balancer Security Group"
  value       = aws_security_group.load_balancer_sg.id
}

output "node_security_group_id" {
  description = "ID of the Node Security Group"
  value       = aws_security_group.node_group_sg.id
}

output "kubeconfig" {
  description = "Kubeconfig in YAML format"
  value       = local.kubeconfig
  sensitive   = true
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "region" {
  value = var.region
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}
