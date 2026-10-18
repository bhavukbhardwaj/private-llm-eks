#!/usr/bin/env bash
# Runs on the laptop. Stages everything the bastion needs to S3: the k8s/ folder, the pinned Load Balancer Controller chart,
# and config.env (cluster name, VPC, ECR host, role ARNs) built from Terraform outputs. config.env lives only in S3, never in git.
# Usage: scripts/stage-k8s.sh      env: AWS_REGION (default us-east-1), LBC_CHART_VERSION (default 3.6.0)
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
LBC_CHART_VERSION="${LBC_CHART_VERSION:-3.6.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS_BUCKET="$(terraform -chdir="$ROOT/terraform/foundation" output -raw tools_bucket)"
MODELS_BUCKET="$(terraform -chdir="$ROOT/terraform/foundation" output -raw models_bucket)"
tf() { terraform -chdir="$ROOT/terraform/platform" output -raw "$1"; }
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp -R "$ROOT/k8s/." "$WORK/"
mkdir -p "$WORK/charts"
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update eks >/dev/null
helm pull eks/aws-load-balancer-controller --version "$LBC_CHART_VERSION" -d "$WORK/charts"

cat > "$WORK/config.env" <<CFG
CLUSTER_NAME=$(tf cluster_name)
AWS_REGION=$REGION
VPC_ID=$(tf vpc_id)
ECR=${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com
LB_ROLE_ARN=$(tf lb_controller_role_arn)
VLLM_ROLE_ARN=$(tf vllm_role_arn)
MODELS_BUCKET=${MODELS_BUCKET}
CFG
chmod +x "$WORK/bootstrap.sh"

aws s3 sync "$WORK" "s3://${TOOLS_BUCKET}/k8s/" --delete --no-progress --region "$REGION"
echo "staged to s3://${TOOLS_BUCKET}/k8s/"
echo "On the bastion run:  aws s3 sync s3://${TOOLS_BUCKET}/k8s ~/k8s && chmod +x ~/k8s/bootstrap.sh && ~/k8s/bootstrap.sh"
