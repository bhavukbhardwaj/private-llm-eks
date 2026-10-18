#!/usr/bin/env bash
# Streams a model from Hugging Face straight into the models bucket, with no local disk, at a PINNED revision (ADR-002).
# Meant for AWS CloudShell (datacenter bandwidth, about 5 minutes for 15 GB); from a laptop use scripts/upload-model.sh.
# Usage: ./upload-model-stream.sh <models-bucket> [repo_id] [revision] [name]
#   defaults: Qwen/Qwen2.5-7B-Instruct  a09a35458c702b33eeacc393d103063234e8bc28  qwen2.5-7b-instruct
set -euo pipefail

BUCKET="${1:?usage: $0 <models-bucket> [repo_id] [revision] [name]}"
REPO_ID="${2:-Qwen/Qwen2.5-7B-Instruct}"
REVISION="${3:-a09a35458c702b33eeacc393d103063234e8bc28}"
NAME="${4:-qwen2.5-7b-instruct}"
BASE="https://huggingface.co/${REPO_ID}/resolve/${REVISION}"
PREFIX="${NAME}/${REVISION}"

# File list from the model index: config and tokenizer files plus every safetensors shard.
FILES="config.json generation_config.json merges.txt tokenizer.json tokenizer_config.json vocab.json model.safetensors.index.json LICENSE"
SHARDS="$(curl -fsSL "${BASE}/model.safetensors.index.json" | python3 -c 'import sys,json; print(" ".join(sorted(set(json.load(sys.stdin)["weight_map"].values()))))')"

for f in $FILES $SHARDS; do
  echo "uploading $f"
  curl -fsSL "${BASE}/${f}" | aws s3 cp - "s3://${BUCKET}/${PREFIX}/${f}" --no-progress
done
aws s3 ls "s3://${BUCKET}/${PREFIX}/" --human-readable
echo "done: MODEL_NAME=${NAME} MODEL_PREFIX=${PREFIX}"
