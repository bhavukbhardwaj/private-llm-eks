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

# Writes ~/.kube/config WITHOUT calling the EKS API (there is no eks VPC endpoint, so `aws eks update-kubeconfig` would hang).
# Token generation (`aws eks get-token`) only signs an STS request, which works through the sts endpoint.
kubeconfig() {
  mkdir -p "$HOME/.kube"
  cat > "$HOME/.kube/config" <<KC
apiVersion: v1
kind: Config
clusters:
  - name: ${CLUSTER_NAME}
    cluster:
      server: ${EKS_ENDPOINT}
      certificate-authority-data: ${EKS_CA}
contexts:
  - name: ${CLUSTER_NAME}
    context:
      cluster: ${CLUSTER_NAME}
      user: ${CLUSTER_NAME}
current-context: ${CLUSTER_NAME}
users:
  - name: ${CLUSTER_NAME}
    user:
      exec:
        apiVersion: client.authentication.k8s.io/v1beta1
        command: aws
        args: [eks, get-token, --cluster-name, ${CLUSTER_NAME}, --region, ${AWS_REGION}, --output, json]
KC
  chmod 600 "$HOME/.kube/config"
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
  echo "curl from inside the VPC (the ALB needs 2 to 5 minutes to become active and its targets healthy):"
  for _ in $(seq 1 48); do
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
