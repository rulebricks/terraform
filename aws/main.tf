provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Create security group for the ALB/NLB
resource "aws_security_group" "load_balancer_sg" {
  name_prefix = "eks-lb-sg-"
  description = "Security group for Load Balancer"
  vpc_id      = module.vpc.vpc_id

  # Allow inbound HTTP traffic
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound HTTPS traffic
  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.cluster_name}-lb-sg"
    Environment = "dev"
    Terraform   = "true"
  }
}

# Create security group for the EKS cluster nodes
resource "aws_security_group" "node_group_sg" {
  name_prefix = "eks-node-sg-"
  description = "Security group for EKS node group"
  vpc_id      = module.vpc.vpc_id

  # Allow all inbound traffic from the load balancer security group
  ingress {
    description     = "Allow inbound traffic from Load Balancer"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer_sg.id]
  }

  # Allow internal communication between nodes
  ingress {
    description = "Allow internal communication between nodes"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.cluster_name}-node-sg"
    Environment = "dev"
    Terraform   = "true"
  }
}

# Create a VPC for the EKS cluster
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.0"

  name = "rulebricks-vpc"
  cidr = var.vpc_cidr != "" ? var.vpc_cidr : "10.0.0.0/16"

  # Use first 3 available AZs (or all if less than 3)
  azs = slice(data.aws_availability_zones.available.names, 0, min(length(data.aws_availability_zones.available.names), 3))

  # Dynamically create subnet CIDRs based on number of AZs
  public_subnets  = [for i in range(min(length(data.aws_availability_zones.available.names), 3)) : cidrsubnet(var.vpc_cidr != "" ? var.vpc_cidr : "10.0.0.0/16", 8, i + 1)]
  private_subnets = [for i in range(min(length(data.aws_availability_zones.available.names), 3)) : cidrsubnet(var.vpc_cidr != "" ? var.vpc_cidr : "10.0.0.0/16", 8, i + 101)]

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    "Environment" = "dev"
    "Name"        = "rulebricks-vpc"
    "Terraform"   = "true"
  }

  enable_nat_gateway = true # Add NAT Gateway for private subnets
  single_nat_gateway = true # Use single NAT Gateway to save costs
  enable_vpn_gateway = false

  # Add required tags for EKS
  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

# Create an EKS cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"

  cluster_name    = var.cluster_name
  cluster_version = "1.30"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets # This is the correct attribute name

  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true
  cluster_endpoint_private_access          = true
  cluster_endpoint_public_access_cidrs     = ["0.0.0.0/0"]

  # Enable CloudWatch logging
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  authentication_mode = "API_AND_CONFIG_MAP"
  enable_irsa         = true

  # Enable proper security group rules for node communication
  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    ingress_cluster_all = {
      description                   = "Cluster API to nodes"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  # Cluster creation timeout
  cluster_timeouts = {
    create = "30m"
    update = "60m"
    delete = "30m"
  }

  eks_managed_node_groups = {
    default = {
      name = var.node_group_name

      instance_types = [var.node_instance_type]

      min_size     = var.min_capacity
      max_size     = var.max_capacity
      desired_size = var.desired_capacity

      capacity_type = "ON_DEMAND"
      ami_type      = "AL2_ARM_64"
      disk_size     = 50
      ebs_optimized = true

      vpc_security_group_ids = [aws_security_group.node_group_sg.id]
      subnet_ids             = module.vpc.private_subnets

      # Add more security and monitoring
      enable_monitoring = true

      # Speed up node group creation
      timeouts = {
        create = "30m"
        update = "60m"
        delete = "30m"
      }

      # Tags needed for cluster autoscaler
      tags = {
        "Environment"                                   = "dev"
        "Terraform"                                     = "true"
        "k8s.io/cluster-autoscaler/enabled"             = "true"
        "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      }

      node_security_group_tags = {
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
      }
    }
  }
}

# --- IAM Role for Cluster Autoscaler ---
data "aws_iam_policy_document" "cluster_autoscaler_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "cluster_autoscaler_policy" {
  name        = "EKSClusterAutoscalerPolicy"
  description = "EKS Cluster Autoscaler Policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeLaunchTemplateVersions"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "cluster_autoscaler_role" {
  name               = "EKSClusterAutoscalerRole"
  assume_role_policy = data.aws_iam_policy_document.cluster_autoscaler_assume_role.json
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler_attachment" {
  role       = aws_iam_role.cluster_autoscaler_role.name
  policy_arn = aws_iam_policy.cluster_autoscaler_policy.arn
}

# --- Required for PVC for Traefik TLS Certificate ---

# Create IAM role for EBS CSI driver
data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_role" {
  name               = "ebs-csi-controller-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  role       = aws_iam_role.ebs_csi_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Create EBS CSI driver addon
resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = "v1.31.0-eksbuild.1" # Updated for EKS 1.30 compatibility
  service_account_role_arn    = aws_iam_role.ebs_csi_role.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  # Add timeouts for faster feedback
  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi_policy,
    module.eks
  ]
}

# Patch the existing gp2 storage class to set it as default
resource "null_resource" "set_default_storage_class" {
  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region} && \
      kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    EOT
  }

  depends_on = [
    aws_eks_addon.ebs_csi,
    module.eks
  ]

  triggers = {
    cluster_id = module.eks.cluster_id
  }
}

# ---

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

# Configure kubectl to connect to the EKS cluster
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# Configure helm provider to deploy Cluster Autoscaler
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# Deploy Cluster Autoscaler using Helm
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.37.0"

  # Add timeout for helm deployment
  timeout = 600

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.region
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.cluster_autoscaler_role.arn
  }

  # Set image for ARM compatibility
  set {
    name  = "image.tag"
    value = "v1.30.0" # Match with your Kubernetes version (1.30)
  }

  # Ensure ARM architecture support
  set {
    name  = "image.repository"
    value = "registry.k8s.io/autoscaling/cluster-autoscaler"
  }

  # Cluster Autoscaler configuration
  set {
    name  = "extraArgs.scale-down-delay-after-add"
    value = "5m"
  }

  set {
    name  = "extraArgs.scale-down-unneeded-time"
    value = "5m"
  }

  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }

  set {
    name  = "extraArgs.expander"
    value = "least-waste"
  }

  depends_on = [
    module.eks,
    aws_iam_role_policy_attachment.cluster_autoscaler_attachment
  ]
}
