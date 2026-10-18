#!/usr/bin/env bash
# Downloads kubectl and helm (arm64, for the bastion) and uploads them to the tools bucket, because the bastion has no internet (ADR-004).
# Usage: scripts/stage-tools.sh          env: AWS_REGION (default us-east-1), K8S_MINOR (default 1.35), HELM_VERSION (default v4.3.0), TOOLS_BUCKET (default: foundation terraform output)
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
K8S_MINOR="${K8S_MINOR:-1.35}"
HELM_VERSION="${HELM_VERSION:-v4.3.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS_BUCKET="${TOOLS_BUCKET:-$(terraform -chdir="$ROOT/terraform/foundation" output -raw tools_bucket)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# kubectl: newest patch release of the cluster's minor version, checksum verified.
KUBECTL_VERSION="$(curl -fsSL "https://dl.k8s.io/release/stable-${K8S_MINOR}.txt")"
curl -fsSL -o "$WORK/kubectl" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/arm64/kubectl"
echo "$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/arm64/kubectl.sha256")  $WORK/kubectl" | shasum -a 256 -c -

# helm: pinned release, checksum verified, binary extracted from the tarball.
curl -fsSL -o "$WORK/helm.tgz" "https://get.helm.sh/helm-${HELM_VERSION}-linux-arm64.tar.gz"
EXPECTED="$(curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-arm64.tar.gz.sha256sum" | awk '{print $1}')"
echo "${EXPECTED}  $WORK/helm.tgz" | shasum -a 256 -c -
tar -xzf "$WORK/helm.tgz" -C "$WORK" linux-arm64/helm

aws s3 cp "$WORK/kubectl" "s3://${TOOLS_BUCKET}/bin/kubectl" --region "$REGION" --no-progress
aws s3 cp "$WORK/linux-arm64/helm" "s3://${TOOLS_BUCKET}/bin/helm" --region "$REGION" --no-progress
echo "staged kubectl ${KUBECTL_VERSION} and helm ${HELM_VERSION} to the tools bucket"
