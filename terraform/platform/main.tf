# Reads the foundation stack outputs (VPC, subnets, buckets, ECR) from its remote state.
data "terraform_remote_state" "foundation" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "private-llm/assessment/foundation/terraform.tfstate"
    region = var.region
  }
}

locals {
  foundation   = data.terraform_remote_state.foundation.outputs
  name         = "${var.project}-${var.environment}"
  cluster_name = local.name

  # Same tags as the provider default_tags, for resources created through launch templates.
  tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
    Stack       = "platform"
  }

  endpoint_services = concat(
    var.enable_interface_endpoints ? var.interface_endpoints : [],
    var.enable_ssm_endpoints ? ["ssm", "ssmmessages", "ec2messages"] : [],
  )
}

# Account ID, used to build the Auto Scaling service-linked role ARN for the KMS grant (never written to files).
data "aws_caller_identity" "current" {}

# Lets the Auto Scaling service-linked role use the existing customer-managed key, so node groups can launch encrypted volumes.
# The key is only referenced here; Terraform never creates, changes or destroys it (ADR-008). Destroying this stack revokes the grant.
resource "aws_kms_grant" "autoscaling" {
  count = var.kms_key_arn == null ? 0 : 1

  name              = "${local.name}-autoscaling-ebs"
  key_id            = var.kms_key_arn
  grantee_principal = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
  operations        = ["Encrypt", "Decrypt", "ReEncryptFrom", "ReEncryptTo", "GenerateDataKey", "GenerateDataKeyWithoutPlaintext", "DescribeKey", "CreateGrant"]
}

# Interface endpoints (single AZ, 443 from the VPC only); empty list means nothing is created and nothing is billed.
module "endpoints" {
  source = "../modules/vpc-endpoints"

  name       = local.name
  vpc_id     = local.foundation.vpc_id
  vpc_cidr   = local.foundation.vpc_cidr
  subnet_ids = [local.foundation.primary_subnet_id]
  region     = var.region
  services   = local.endpoint_services
}

# Spot bastion reachable only through Session Manager; admin entry point for kubectl and helm (ADR-006).
module "bastion" {
  source = "../modules/bastion"
  count  = var.enable_bastion ? 1 : 0

  name             = local.name
  vpc_id           = local.foundation.vpc_id
  vpc_cidr         = local.foundation.vpc_cidr
  subnet_id        = local.foundation.primary_subnet_id
  region           = var.region
  cluster_name     = local.cluster_name
  tools_bucket     = local.foundation.tools_bucket
  tools_bucket_arn = local.foundation.tools_bucket_arn
  instance_type    = var.bastion_instance_type
}

# The EKS cluster with a private API endpoint, a Graviton Spot system node group and an optional GPU node group.
module "eks" {
  source = "../modules/eks"

  name                           = local.cluster_name
  kubernetes_version             = var.kubernetes_version
  vpc_id                         = local.foundation.vpc_id
  cluster_subnet_ids             = values(local.foundation.private_subnet_ids_by_az)
  node_subnet_ids                = [local.foundation.primary_subnet_id]
  tags                           = local.tags
  enabled_log_types              = var.eks_control_plane_log_types
  log_retention_days             = var.eks_log_retention_days
  api_ingress_security_group_ids = var.enable_bastion ? [module.bastion[0].security_group_id] : []
  admin_principal_arns           = var.enable_bastion ? [module.bastion[0].role_arn] : []
  system_instance_types          = var.system_instance_types
  system_desired_size            = var.system_desired_size
  system_volume_gb               = var.system_volume_gb
  enable_gpu_nodes               = var.enable_gpu_nodes
  gpu_instance_type              = var.gpu_instance_type
  gpu_capacity_type              = var.gpu_capacity_type
  kms_key_arn                    = var.kms_key_arn
  gpu_volume_gb                  = var.gpu_volume_gb

  # Nodes need the endpoints to pull images and join, so create them first.
  depends_on = [module.endpoints, aws_kms_grant.autoscaling]
}

# IRSA role for the AWS Load Balancer Controller (official IAM policy file, pinned in policies/).
module "irsa_lb_controller" {
  source = "../modules/irsa"

  name              = "${local.name}-lb-controller"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  namespace         = "kube-system"
  service_account   = "aws-load-balancer-controller"
  policy_json       = file("${path.module}/policies/aws-lb-controller-iam-policy.json")
}

# Read-only permission on the models bucket for the vLLM init container (ADR-002).
data "aws_iam_policy_document" "models_read" {
  statement {
    sid       = "ListModels"
    actions   = ["s3:ListBucket"]
    resources = [local.foundation.models_bucket_arn]
  }

  statement {
    sid       = "ReadModels"
    actions   = ["s3:GetObject"]
    resources = ["${local.foundation.models_bucket_arn}/*"]
  }
}

# IRSA role for the vLLM service account: it can read model weights and nothing else.
module "irsa_vllm" {
  source = "../modules/irsa"

  name              = "${local.name}-vllm-models-read"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  namespace         = "llm"
  service_account   = "vllm"
  policy_json       = data.aws_iam_policy_document.models_read.json
}

# IRSA role for the EBS CSI driver (created only if the driver is enabled).
module "irsa_ebs_csi" {
  source = "../modules/irsa"
  count  = var.enable_ebs_csi ? 1 : 0

  name                = "${local.name}-ebs-csi"
  oidc_provider_arn   = module.eks.oidc_provider_arn
  oidc_provider_url   = module.eks.oidc_provider_url
  namespace           = "kube-system"
  service_account     = "ebs-csi-controller-sa"
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
}

# EBS CSI add-on so gp3 PersistentVolumeClaims work (off by default; PoC workloads use emptyDir).
resource "aws_eks_addon" "ebs_csi" {
  count = var.enable_ebs_csi ? 1 : 0

  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = module.irsa_ebs_csi[0].role_arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [module.eks]
}
