# Remote state in S3 with native locking (ADR-005). The bucket name is passed at init time:
#   terraform init -backend-config="bucket=<state bucket from the bootstrap output>"
terraform {
  backend "s3" {
    key          = "private-llm/assessment/foundation/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
