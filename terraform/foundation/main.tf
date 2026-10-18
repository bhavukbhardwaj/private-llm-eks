# Random suffix so globally unique bucket names need no account ID.
resource "random_id" "suffix" {
  byte_length = 4
}

# Private network: VPC, two private subnets in two AZs, free S3 gateway endpoint, no NAT and no internet gateway.
module "vpc" {
  source = "../modules/vpc"

  name                 = "${var.project}-${var.environment}"
  cidr                 = var.vpc_cidr
  azs                  = var.azs
  private_subnet_cidrs = var.private_subnet_cidrs
  region               = var.region
}

# Bucket holding the model weights that the vLLM init container syncs at pod start (ADR-002).
module "models_bucket" {
  source = "../modules/s3-bucket"

  bucket_name   = "${var.project}-models-${random_id.suffix.hex}"
  force_destroy = true
}

# Bucket holding CLI tools (kubectl, helm) and manifests for the offline bastion (ADR-004).
module "tools_bucket" {
  source = "../modules/s3-bucket"

  bucket_name   = "${var.project}-tools-${random_id.suffix.hex}"
  force_destroy = true
}

# Private ECR repositories for mirrored images, since nodes have no internet access.
module "ecr" {
  source = "../modules/ecr"

  repository_names = var.ecr_repositories
}
