# Control-plane log group, created only when logging is switched on, so retention is short and cost is bounded.
resource "aws_cloudwatch_log_group" "cluster" {
  count = length(var.enabled_log_types) > 0 ? 1 : 0

  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = var.log_retention_days
}

# Trust policy letting the EKS service assume the cluster role.
data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

# IAM role used by the EKS control plane.
resource "aws_iam_role" "cluster" {
  name               = "${var.name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
}

# AWS managed policy that the control plane needs.
resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# The EKS cluster: private API endpoint only, access via IAM access entries, control-plane logging off unless enabled.
resource "aws_eks_cluster" "this" {
  name                      = var.name
  version                   = var.kubernetes_version
  role_arn                  = aws_iam_role.cluster.arn
  enabled_cluster_log_types = var.enabled_log_types

  vpc_config {
    subnet_ids              = var.cluster_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]
}

# OIDC provider that lets pods assume IAM roles through service accounts (IRSA).
resource "aws_iam_openid_connect_provider" "this" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}

# Allows the bastion security group to reach the private API endpoint on 443.
resource "aws_vpc_security_group_ingress_rule" "api" {
  count = length(var.api_ingress_security_group_ids)

  security_group_id            = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description                  = "Kubernetes API from bastion"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = var.api_ingress_security_group_ids[count.index]
}

# Registers each admin principal (such as the bastion role) with the cluster.
resource "aws_eks_access_entry" "admin" {
  count = length(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.admin_principal_arns[count.index]
  type          = "STANDARD"
}

# Grants those principals cluster-admin permissions.
resource "aws_eks_access_policy_association" "admin" {
  count = length(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.admin_principal_arns[count.index]
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

# Trust policy letting EC2 nodes assume the node role.
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# IAM role shared by all worker nodes.
resource "aws_iam_role" "node" {
  name               = "${var.name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

# Minimum managed policies for nodes: join the cluster, run the CNI plugin, pull images from ECR (read only).
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# Network add-ons that nodes need before they can become Ready (managed by EKS, default versions).
resource "aws_eks_addon" "early" {
  for_each = toset(["vpc-cni", "kube-proxy"])

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# Launch template for system nodes: gp3 encrypted root volume, detailed monitoring off, IMDSv2 with hop limit 1 so pods cannot read node credentials.
resource "aws_launch_template" "system" {
  name_prefix = "${var.name}-system-"

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.system_volume_gb
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = false
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags          = var.tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = var.tags
  }
}

# System node group: Graviton Spot in the single working AZ, for cluster add-ons and monitoring.
resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "system"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.node_subnet_ids
  ami_type        = "AL2023_ARM_64_STANDARD"
  capacity_type   = "SPOT"
  instance_types  = var.system_instance_types

  scaling_config {
    desired_size = var.system_desired_size
    min_size     = 1
    max_size     = var.system_max_size
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.system.id
    version = aws_launch_template.system.latest_version
  }

  labels = { role = "system" }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.early,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# DNS add-on; it needs nodes to schedule on, so it is created after the system node group.
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.system]
}

# Launch template for GPU nodes: bigger gp3 encrypted volume for the image and model weights, monitoring off, IMDSv2.
resource "aws_launch_template" "gpu" {
  count = var.enable_gpu_nodes ? 1 : 0

  name_prefix = "${var.name}-gpu-"

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.gpu_volume_gb
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = false
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags          = var.tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = var.tags
  }
}

# GPU node group: AL2023 NVIDIA AMI (driver and container toolkit preinstalled), Spot, tainted so only GPU pods land here.
resource "aws_eks_node_group" "gpu" {
  count = var.enable_gpu_nodes ? 1 : 0

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "gpu"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.node_subnet_ids
  ami_type        = "AL2023_x86_64_NVIDIA"
  capacity_type   = var.gpu_capacity_type # SPOT for the PoC; ON_DEMAND is the unused fallback (ADR-001)
  instance_types  = [var.gpu_instance_type]

  scaling_config {
    desired_size = 1
    min_size     = 0
    max_size     = 1
  }

  launch_template {
    id      = aws_launch_template.gpu[0].id
    version = aws_launch_template.gpu[0].latest_version
  }

  labels = { role = "gpu" }

  taint {
    key    = "nvidia.com/gpu"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.early,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
