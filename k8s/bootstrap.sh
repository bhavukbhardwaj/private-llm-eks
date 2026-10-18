#!/usr/bin/env bash
# Runs ON THE BASTION. Installs the AWS Load Balancer Controller and the placeholder app, then curls the internal ALB.
# Usage: ./bootstrap.sh [kubeconfig|lb|placeholder|all]   (default: all)
# Needs config.env (written by scripts/stage-k8s.sh) in the same folder.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck disable=SC1091
source ./config.env
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION"
STEP="${1:-all}"

render() { sed "s|\${ECR}|${ECR}|g" "$1"; }

kubeconfig() {
  aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
  kubectl get nodes -o wide
}

lb() {
  helm upgrade --install aws-load-balancer-controller ./charts/aws-load-balancer-controller-*.tgz \
    --namespace kube-system -f lb-controller/values.yaml \
    --set clusterName="$CLUSTER_NAME" --set region="$AWS_REGION" --set vpcId="$VPC_ID" \
    --set image.repository="${ECR}/aws-load-balancer-controller" \
    --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${LB_ROLE_ARN}" \
    --wait --timeout 5m
  kubectl -n kube-system get deploy aws-load-balancer-controller
}

placeholder() {
  render placeholder/placeholder.yaml | kubectl apply -f -
  kubectl -n demo rollout status deploy/placeholder --timeout=3m
  echo "waiting for the internal ALB address..."
  for _ in $(seq 1 40); do
    HOST="$(kubectl -n demo get ingress placeholder -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    [ -n "$HOST" ] && break
    sleep 10
  done
  echo "ALB: ${HOST:-not ready}"
  echo "curl from inside the VPC (targets can take 1 to 2 minutes to become healthy):"
  for _ in $(seq 1 20); do
    if curl -fsS -m 5 "http://${HOST}/"; then echo; break; fi
    sleep 10
  done
}

case "$STEP" in
  kubeconfig) kubeconfig ;;
  lb) lb ;;
  placeholder) placeholder ;;
  all) kubeconfig; lb; placeholder ;;
  *) echo "usage: $0 [kubeconfig|lb|placeholder|all]"; exit 1 ;;
esac
