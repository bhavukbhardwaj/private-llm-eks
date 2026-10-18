#!/usr/bin/env bash
# Runs ON THE BASTION. Installs the AWS Load Balancer Controller and the placeholder app, then curls the internal ALB.
# Usage: ./bootstrap.sh [kubeconfig|lb|placeholder|gpu|monitoring|llm|all]   (default: all = kubeconfig, lb, placeholder)
# Needs config.env (written by scripts/stage-k8s.sh) in the same folder.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck disable=SC1091
source ./config.env
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION"
STEP="${1:-all}"

# Fills the ${PLACEHOLDERS} in a manifest from config.env (no account IDs or ARNs are stored in git).
render() {
  sed -e "s|\${ECR}|${ECR}|g" -e "s|\${AWS_REGION}|${AWS_REGION}|g" -e "s|\${MODELS_BUCKET}|${MODELS_BUCKET:-}|g" \
      -e "s|\${MODEL_PREFIX}|${MODEL_PREFIX:-}|g" -e "s|\${MODEL_NAME}|${MODEL_NAME:-}|g" -e "s|\${VLLM_ROLE_ARN}|${VLLM_ROLE_ARN:-}|g" "$1"
}

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

# GPU proof: device plugin DaemonSet, then a pod that runs nvidia-smi on the GPU node. Run only after the GPU node is up.
gpu() {
  render gpu/nvidia-device-plugin.yaml | kubectl apply -f -
  kubectl -n kube-system rollout status ds/nvidia-device-plugin-daemonset --timeout=5m
  echo "GPU allocatable on nodes:"
  kubectl get nodes -l role=gpu -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu
  kubectl delete pod nvidia-smi --ignore-not-found
  render gpu/nvidia-smi-pod.yaml | kubectl apply -f -
  kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/nvidia-smi --timeout=10m || true
  kubectl logs nvidia-smi
  kubectl get pod nvidia-smi -o wide
}

# Monitoring: DCGM exporter, Prometheus, Grafana (dashboard from dashboards/vllm-gpu.json, admin password generated here and kept in a Secret).
monitoring() {
  kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
  if ! kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
    kubectl -n monitoring create secret generic grafana-admin --from-literal=password="$(head -c 18 /dev/urandom | base64 | tr -d '/+=' | cut -c1-20)"
  fi
  kubectl -n monitoring create configmap grafana-dashboards --from-file=dashboards/vllm-gpu.json --dry-run=client -o yaml | kubectl apply -f -
  for f in monitoring/dcgm-exporter.yaml monitoring/prometheus.yaml monitoring/grafana.yaml; do render "$f" | kubectl apply -f -; done
  kubectl -n monitoring rollout status deploy/prometheus --timeout=3m
  kubectl -n monitoring rollout status deploy/grafana --timeout=3m
  kubectl -n monitoring get pods -o wide
  echo "Grafana admin password:  kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.password}' | base64 -d"
}

# LLM: vLLM (S3 init container, GPU) behind an internal ALB, then a chat-completion curl from inside the VPC.
llm() {
  render llm/vllm.yaml | kubectl apply -f -
  echo "waiting for the model to sync and vLLM to start (several minutes on first run)..."
  kubectl -n llm rollout status deploy/vllm --timeout=20m
  for _ in $(seq 1 40); do
    HOST="$(kubectl -n llm get ingress vllm -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    [ -n "$HOST" ] && break
    sleep 10
  done
  echo "ALB: ${HOST:-not ready}"
  for _ in $(seq 1 48); do
    if curl -fsS -m 20 "http://${HOST}/v1/chat/completions" -H 'Content-Type: application/json' \
      -d "{\"model\":\"${MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello in five words.\"}],\"max_tokens\":32}"; then echo; break; fi
    sleep 10
  done
  kubectl -n llm get pods -o wide
}

case "$STEP" in
  kubeconfig) kubeconfig ;;
  lb) lb ;;
  placeholder) placeholder ;;
  gpu) gpu ;;
  monitoring) monitoring ;;
  llm) llm ;;
  all) kubeconfig; lb; placeholder ;;
  *) echo "usage: $0 [kubeconfig|lb|placeholder|gpu|monitoring|llm|all]"; exit 1 ;;
esac
