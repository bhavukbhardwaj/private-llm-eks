variable "name" {
  description = "Name prefix for the VPC and its parts."
  type        = string
}

variable "cidr" {
  description = "IPv4 CIDR of the VPC."
  type        = string
}

variable "azs" {
  description = "Availability Zones for the private subnets (at least two, EKS and the internal ALB need two)."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "Provide at least two Availability Zones."
  }
}

variable "private_subnet_cidrs" {
  description = "One CIDR per AZ, same order as azs."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "Provide at least two private subnet CIDRs."
  }
}

variable "region" {
  description = "AWS region, used for the S3 gateway endpoint service name."
  type        = string
}
