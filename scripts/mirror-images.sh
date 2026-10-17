#!/usr/bin/env bash
# Copies the images listed in scripts/images.txt into private ECR with `crane copy` (registry to registry, no docker pull/push).
# Usage:  scripts/mirror-images.sh [--dry-run]        env: AWS_REGION (default us-east-1), ONLY="repo1 repo2" to copy a subset
# Needs: crane, aws CLI with working credentials, ECR repositories from the foundation stack.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
LIST="$(dirname "$0")/images.txt"
DRY_RUN="false"
[ "${1:-}" = "--dry-run" ] && DRY_RUN="true"

if [ "$DRY_RUN" = "false" ]; then
  ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
  REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
  # ECR login token (valid 12 hours); crane stores it in its own auth config.
  aws ecr get-login-password --region "$REGION" | crane auth login "$REGISTRY" --username AWS --password-stdin
fi

grep -v '^[[:space:]]*#' "$LIST" | grep -v '^[[:space:]]*$' | while read -r repo tag platform source; do
  if [ -n "${ONLY:-}" ] && ! echo " $ONLY " | grep -q " $repo "; then continue; fi
  platform_args=()
  [ "$platform" != "all" ] && platform_args=(--platform "$platform")

  if [ "$DRY_RUN" = "true" ]; then
    echo "[dry-run] crane copy ${platform_args[*]:-} $source -> <registry>/${repo}:${tag}"
    continue
  fi

  dest="${REGISTRY}/${repo}:${tag}"

  # Tags are immutable in ECR, so skip anything already mirrored.
  if crane digest "$dest" >/dev/null 2>&1; then
    echo "skip   ${repo}:${tag} (already in ECR)"
    continue
  fi

  echo "copy   ${repo}:${tag} (${platform}) from ${source}"
  crane copy "${platform_args[@]}" "$source" "$dest"
  echo "digest ${repo}:${tag} $(crane digest "$dest")"
done
