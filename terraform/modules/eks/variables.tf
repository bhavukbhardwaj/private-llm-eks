variable "name" {
  description = "EKS cluster name (also the prefix for IAM roles and node groups)."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version of the control plane."
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  description = "VPC of the cluster."
  type        = string
}

variable "cluster_subnet_ids" {
  description = "Subnets for the control-plane network interfaces; EKS requires at least two AZs."
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "Subnets for the node groups; one subnet keeps all nodes in one AZ (ADR-008)."
  type        = list(string)
}

variable "tags" {
  description = "Tags copied onto node instances and volumes (default_tags do not reach launch-template resources)."
  type        = map(string)
  default     = {}
}

variable "enabled_log_types" {
  description = "EKS control-plane log types sent to CloudWatch. Empty (default) means no logging and no CloudWatch cost (ADR-008)."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Retention of the control-plane log group, used only when enabled_log_types is not empty."
  type        = number
  default     = 3
}

variable "api_ingress_security_group_ids" {
  description = "Security groups (for example the bastion) allowed to reach the private API endpoint on 443."
  type        = list(string)
  default     = []
}

variable "admin_principal_arns" {
  description = "IAM principals (for example the bastion role) that get cluster-admin through EKS access entries."
  type        = list(string)
  default     = []
}

variable "system_instance_types" {
  description = "Instance types of the system node group (ADR-001)."
  type        = list(string)
  default     = ["t4g.small"]
}

variable "system_desired_size" {
  description = "Number of system nodes; t4g.small allows about 11 pods each, so two are needed for add-ons plus monitoring."
  type        = number
  default     = 2
}

variable "system_max_size" {
  description = "Maximum number of system nodes."
  type        = number
  default     = 3
}

variable "system_volume_gb" {
  description = "Root volume size of system nodes in GB (gp3, ADR-008)."
  type        = number
  default     = 20
}

variable "enable_gpu_nodes" {
  description = "Create the GPU node group (cost toggle, ADR-008)."
  type        = bool
  default     = false
}

variable "gpu_instance_type" {
  description = "GPU instance type (ADR-001)."
  type        = string
  default     = "g5.xlarge"
}

variable "gpu_capacity_type" {
  description = "SPOT (default). ON_DEMAND is kept only as a documented fallback and is NOT used: this is a PoC, so we accept Spot interruptions instead of paying about 2.3x (ADR-001)."
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.gpu_capacity_type)
    error_message = "gpu_capacity_type must be SPOT or ON_DEMAND."
  }
}

variable "gpu_volume_gb" {
  description = "Root volume size of GPU nodes in GB (gp3; 60 for the 7B run, 40 is enough for a small model)."
  type        = number
  default     = 60
}
