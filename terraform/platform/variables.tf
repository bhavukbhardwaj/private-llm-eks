variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name; used in tags and names."
  type        = string
  default     = "private-llm"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "assessment"
}

variable "owner" {
  description = "Owner tag value. No personal details (no emails or names of individuals)."
  type        = string
  default     = "platform"
}

variable "state_bucket" {
  description = "Name of the Terraform state bucket (bootstrap output); used to read the foundation stack outputs."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of an existing customer-managed KMS key used to encrypt node EBS volumes (brief 2.2). Pass it from an untracked tfvars file; it contains the account ID. Null keeps the AWS-managed aws/ebs key (ADR-003)."
  type        = string
  default     = null
}

variable "kubernetes_version" {
  description = "Kubernetes version of the EKS control plane."
  type        = string
  default     = "1.35"
}

# ---- Cost toggles (ADR-003): everything that bills by the hour is off until needed ----

variable "enable_interface_endpoints" {
  description = "Create the interface endpoints the private cluster needs (about $0.01/hr per endpoint). The cluster cannot pull images or join nodes without them."
  type        = bool
  default     = false
}

variable "interface_endpoints" {
  description = "Interface endpoint services for the cluster (no logs endpoint: nothing sends to CloudWatch, ADR-003)."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "sts", "kms", "ec2", "elasticloadbalancing"]
}

variable "enable_ssm_endpoints" {
  description = "Create the ssm, ssmmessages and ec2messages endpoints so Session Manager reaches the bastion (ADR-004)."
  type        = bool
  default     = false
}

variable "enable_bastion" {
  description = "Create the Spot t4g.micro bastion (ADR-004)."
  type        = bool
  default     = false
}

variable "enable_gpu_nodes" {
  description = "Create the GPU node group (needs AWS GPU quota approval, ADR-001)."
  type        = bool
  default     = false
}

variable "enable_ebs_csi" {
  description = "Install the EBS CSI driver add-on (only needed if a workload uses a PersistentVolumeClaim)."
  type        = bool
  default     = false
}

variable "eks_control_plane_log_types" {
  description = "EKS control-plane log types sent to CloudWatch. Empty (default) means no logging and no CloudWatch cost (ADR-003). Production: [\"api\", \"audit\", \"authenticator\"]."
  type        = list(string)
  default     = []
}

variable "eks_log_retention_days" {
  description = "Retention of the control-plane log group when logging is enabled."
  type        = number
  default     = 3
}

# ---- Sizing (ADR-001, ADR-003) ----

variable "system_instance_types" {
  description = "Instance types of the system node group."
  type        = list(string)
  default     = ["t4g.small"]
}

variable "system_desired_size" {
  description = "Number of system nodes (t4g.small fits about 11 pods)."
  type        = number
  default     = 2
}

variable "system_volume_gb" {
  description = "Root volume of system nodes in GB (gp3)."
  type        = number
  default     = 20
}

variable "gpu_instance_type" {
  description = "GPU instance type."
  type        = string
  default     = "g5.xlarge"
}

variable "gpu_capacity_type" {
  description = "SPOT (default, PoC). ON_DEMAND is a documented fallback that we deliberately do not use (cost, ADR-001)."
  type        = string
  default     = "SPOT"
}

variable "gpu_volume_gb" {
  description = "Root volume of GPU nodes in GB (gp3)."
  type        = number
  default     = 60
}

variable "bastion_instance_type" {
  description = "Bastion instance type."
  type        = string
  default     = "t4g.micro"
}
