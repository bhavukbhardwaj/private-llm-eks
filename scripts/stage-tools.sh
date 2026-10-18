#!/usr/bin/env bash
# Downloads kubectl and helm (arm64, for the bastion) and uploads them to the tools bucket, because the bastion has no internet (ADR-004).
# Tools: kubectl, helm, k9s (terminal UI for Kubernetes), stern (multi-pod log tailing). Tools already in the bucket are skipped.
# Usage: scripts/stage-tools.sh          env: AWS_REGION (default us-east-1), K8S_MINOR (default 1.35), HELM_VERSION (default v4.3.0), K9S_VERSION (default v0.51.0), STERN_VERSION (default 1.34.0), TOOLS_BUCKET (default: foundation terraform output)
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
K8S_MINOR="${K8S_MINOR:-1.35}"
HELM_VERSION="${HELM_VERSION:-v4.3.0}"
K9S_VERSION="${K9S_VERSION:-v0.51.0}"
STERN_VERSION="${STERN_VERSION:-1.34.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS_BUCKET="${TOOLS_BUCKET:-$(terraform -chdir="$ROOT/terraform/foundation" output -raw tools_bucket)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

have() { aws s3api head-object --bucket "$TOOLS_BUCKET" --key "bin/$1" --region "$REGION" >/dev/null 2>&1; }
put() { aws s3 cp "$1" "s3://${TOOLS_BUCKET}/bin/$2" --region "$REGION" --no-progress; echo "staged $2"; }

# kubectl: newest patch release of the cluster's minor version, checksum verified.
if have kubectl; then echo "skip kubectl (already staged)"; else
  KUBECTL_VERSION="$(curl -fsSL "https://dl.k8s.io/release/stable-${K8S_MINOR}.txt")"
  curl -fsSL -o "$WORK/kubectl" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/arm64/kubectl"
  echo "$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/arm64/kubectl.sha256")  $WORK/kubectl" | shasum -a 256 -c -
  put "$WORK/kubectl" kubectl
fi

# helm: pinned release, checksum verified, binary extracted from the tarball.
if have helm; then echo "skip helm (already staged)"; else
  curl -fsSL -o "$WORK/helm.tgz" "https://get.helm.sh/helm-${HELM_VERSION}-linux-arm64.tar.gz"
  EXPECTED="$(curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-arm64.tar.gz.sha256sum" | awk '{print $1}')"
  echo "${EXPECTED}  $WORK/helm.tgz" | shasum -a 256 -c -
  tar -xzf "$WORK/helm.tgz" -C "$WORK" linux-arm64/helm
  put "$WORK/linux-arm64/helm" helm
fi

# k9s: terminal UI for Kubernetes, checksum verified against the release's checksums file.
if have k9s; then echo "skip k9s (already staged)"; else
  BASE="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}"
  curl -fsSL -o "$WORK/k9s.tgz" "${BASE}/k9s_Linux_arm64.tar.gz"
  EXPECTED="$(curl -fsSL "${BASE}/checksums.sha256" | awk '$2=="k9s_Linux_arm64.tar.gz"{print $1}')"
  echo "${EXPECTED}  $WORK/k9s.tgz" | shasum -a 256 -c -
  tar -xzf "$WORK/k9s.tgz" -C "$WORK" k9s
  put "$WORK/k9s" k9s
fi

# stern: tails logs from many pods at once, checksum verified.
if have stern; then echo "skip stern (already staged)"; else
  BASE="https://github.com/stern/stern/releases/download/v${STERN_VERSION}"
  curl -fsSL -o "$WORK/stern.tgz" "${BASE}/stern_${STERN_VERSION}_linux_arm64.tar.gz"
  EXPECTED="$(curl -fsSL "${BASE}/checksums.txt" | awk -v f="stern_${STERN_VERSION}_linux_arm64.tar.gz" '$2==f{print $1}')"
  echo "${EXPECTED}  $WORK/stern.tgz" | shasum -a 256 -c -
  tar -xzf "$WORK/stern.tgz" -C "$WORK" stern
  put "$WORK/stern" stern
fi
