#!/usr/bin/env bash
# Downloads a model from Hugging Face at a PINNED revision and uploads it to the models bucket under <name>/<revision>/ (ADR-002).
# Usage: scripts/upload-model.sh [repo_id] [revision] [name]
#   defaults: Qwen/Qwen2.5-0.5B-Instruct  7ae557604adf67be50417f59c2c2f167def9a775  qwen2.5-0.5b-instruct
# Needs: python3, AWS CLI with credentials. Weights are never committed to git (see .gitignore).
set -euo pipefail

REPO_ID="${1:-Qwen/Qwen2.5-0.5B-Instruct}"
REVISION="${2:-7ae557604adf67be50417f59c2c2f167def9a775}"
NAME="${3:-qwen2.5-0.5b-instruct}"
REGION="${AWS_REGION:-us-east-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUCKET="${MODELS_BUCKET:-$(terraform -chdir="$ROOT/terraform/foundation" output -raw models_bucket)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install -q huggingface_hub
"$WORK/venv/bin/python" - <<PY
from huggingface_hub import snapshot_download
snapshot_download("$REPO_ID", revision="$REVISION", local_dir="$WORK/model",
                  allow_patterns=["*.json", "*.safetensors", "merges.txt", "LICENSE"])
PY

aws s3 sync "$WORK/model" "s3://${BUCKET}/${NAME}/${REVISION}/" --exclude ".cache/*" --no-progress --region "$REGION"
echo "uploaded to s3://${BUCKET}/${NAME}/${REVISION}/"
echo "use MODEL_NAME=${NAME} MODEL_PREFIX=${NAME}/${REVISION} with scripts/stage-k8s.sh"
