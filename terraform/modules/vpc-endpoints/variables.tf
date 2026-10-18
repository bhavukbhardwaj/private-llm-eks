variable "name" {
  description = "Name prefix for the endpoints and their security group."
  type        = string
}

variable "vpc_id" {
  description = "VPC that receives the endpoints."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR; only traffic from inside it may reach the endpoints on 443."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the endpoint network interfaces (one subnet = one AZ = lowest cost, ADR-003)."
  type        = list(string)
}

variable "region" {
  description = "AWS region, used to build endpoint service names."
  type        = string
}

variable "services" {
  description = "Interface endpoint services by short name, for example ecr.api. An empty list creates nothing (cost toggle)."
  type        = list(string)
  default     = []
}
