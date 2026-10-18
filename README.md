# Private LLM inference on EKS

A small, reproducible deployment that serves an open-weight model (Qwen2.5, via vLLM) from inside a private VPC on Amazon EKS. Everything is defined in code, nothing is exposed to the internet, and it is observable with Prometheus, the NVIDIA DCGM exporter and Grafana.

- Brief: [task.md](task.md). Plan and progress: [deliverable.md](deliverable.md). Decisions: [docs/adr/](docs/adr/). Commands: [docs/runbook.md](docs/runbook.md).
- Written answer for the law-firm question: [docs/law-firm-answer.md](docs/law-firm-answer.md).
- Evidence (`nvidia-smi`, `kubectl` output, results): [docs/evidence/](docs/evidence/).

## What it does
- Serves `POST /v1/chat/completions` (OpenAI-compatible) from vLLM on one NVIDIA A10G (`g5.xlarge`).
- The endpoint is an **internal ALB**: reachable only from inside the VPC.
- No NAT and no internet gateway. Images come from private ECR and the model weights from S3, through VPC endpoints.
- Pods reach AWS only through IRSA (no long-lived credentials). Humans use SSO. The Kubernetes API is private, reached through an SSM bastion.

## Architecture
```
                     AWS account, us-east-1, VPC 10.20.0.0/16  (no IGW, no NAT)
  ┌──────────────────────────────────────────────────────────────────────────────────┐
  │  private subnets: us-east-1c (working AZ) and us-east-1d                          │
  │                                                                                    │
  │  SSM bastion ──kubectl/helm──▶  EKS control plane (private endpoint only)         │
  │  (Spot t4g.micro,                                                                  │
  │   no inbound ports)        system nodes (2 x t4g.small Spot, arm64)                │
  │        │                    ├─ AWS Load Balancer Controller                        │
  │        │ curl               ├─ Prometheus ──scrapes──┐                             │
  │        ▼                    └─ Grafana ◀─────────────┤                             │
  │   internal ALB ──────────▶  GPU node (g5.xlarge, A10G, tainted)                    │
  │   (scheme internal)         ├─ vLLM  ◀── init container: S3 sync (IRSA)           │
  │                             └─ DCGM exporter, NVIDIA device plugin                 │
  │                                                                                    │
  │  VPC endpoints: S3 (gateway); ecr.api, ecr.dkr, sts, kms, ec2, elb, ssm (interface)│
  └──────────────────────────────────────────────────────────────────────────────────┘
   S3: model weights, tools        ECR: mirrored images        KMS: existing CMK for node EBS
```

## Repository layout
```
terraform/bootstrap/    state bucket (S3 native locking)
terraform/foundation/   VPC, S3 gateway endpoint, ECR, buckets            (persistent)
terraform/platform/     endpoints, EKS, nodes, bastion, IRSA              (disposable)
terraform/modules/      vpc, vpc-endpoints, s3-bucket, ecr, eks, irsa, bastion
k8s/                    manifests, Helm values, bootstrap.sh (runs on the bastion)
dashboards/             Grafana dashboard JSON
scripts/                image mirroring, tool staging, helpers
loadtest/               load test client (Dockerfile + Python)
docs/                   ADRs, security, runbook, evidence, law-firm answer
```

## Prerequisites (done by hand, once)
- An AWS account with IAM Identity Center (SSO) and MFA. No access keys.
- GPU quotas in us-east-1: *Running On-Demand G and VT instances* and *All G and VT Spot Instance Requests*, 4 vCPU each.
- Tools: Terraform >= 1.11, AWS CLI v2, kubectl, helm, crane, docker (buildx).
- An existing customer-managed KMS key for node volumes (this project reuses the Identity Center key). Its ARN goes in the untracked `terraform/platform/terraform.tfvars` as `kms_key_arn`.

## Deploy from scratch
```
# 1. State bucket, then foundation (VPC, ECR, buckets)
cd terraform/bootstrap  && terraform init && terraform apply
cd ../foundation        && terraform init -backend-config="bucket=<state bucket>" && terraform apply

# 2. Copy images into ECR and stage tools (laptop; use AWS CloudShell for the 9 GB vLLM image)
scripts/mirror-images.sh
scripts/stage-tools.sh

# 3. Model weights to S3 (pinned Hugging Face revision)
scripts/upload-model.sh

# 4. Platform: EKS, nodes, endpoints, bastion (hourly billing starts here)
cd ../platform && terraform init -backend-config="bucket=<state bucket>" && terraform apply

# 5. Stage cluster files, then on the bastion (Session Manager):
scripts/stage-k8s.sh
aws s3 sync s3://<tools bucket>/k8s ~/k8s && chmod +x ~/k8s/bootstrap.sh
~/k8s/bootstrap.sh            # kubeconfig, Load Balancer Controller, placeholder
~/k8s/bootstrap.sh gpu        # NVIDIA device plugin, nvidia-smi pod
~/k8s/bootstrap.sh monitoring # Prometheus, Grafana, DCGM exporter
~/k8s/bootstrap.sh llm        # vLLM behind the internal ALB, chat curl
```
Turn the GPU node on with `enable_gpu_ondemand_nodes = true` (or the Spot variant `enable_gpu_nodes`) and apply. Destroy with `terraform destroy` in `terraform/platform`.

## How to run the load test
On the bastion: `~/k8s/bootstrap.sh loadtest` (200 requests, concurrency 8). Override with `REQUESTS=300 CONCURRENCY=4`. The result is printed and saved to `~/loadtest-result.json`.

## Load test results
_To be filled after the run (model, requests, concurrency, throughput, p50, p95, errors)._

## Probes: readiness vs liveness
- **Readiness** (`/health`): is the pod ready to take traffic? If it fails, Kubernetes removes the pod from the Service and the ALB, but does not restart it. Used while the model is loading or when the server is overloaded.
- **Liveness** (`/health`): is the process still working? If it keeps failing, Kubernetes restarts the container. Used to recover a hung server.
- **Startup probe**: gives vLLM up to 15 minutes to load the model before liveness starts, so a slow load is not mistaken for a hang.

## vLLM arguments
| Argument | Value | Why |
|---|---|---|
| `--model` (first argument) | `/models` | Weights synced from S3 at pod start; no internet download |
| `--served-model-name` | `qwen2.5-0.5b-instruct` | Stable API name, independent of the path |
| `--max-model-len` | `8192` | Caps context so the KV cache fits beside the weights on 24 GB |
| `--gpu-memory-utilization` | `0.90` | Headroom for CUDA graphs and overhead |
| `--tensor-parallel-size` | `1` | One A10G |

Model and revision: Qwen2.5-0.5B-Instruct, Hugging Face commit `7ae557604adf67be50417f59c2c2f167def9a775` (Apache-2.0). Resources: 1 GPU, 2 CPU, 6 GiB memory requested, 12 GiB limit.

## Observability
- Prometheus scrapes every pod annotated `prometheus.io/scrape` (vLLM `/metrics`, DCGM exporter on 9400). This is the "equivalent scrape config" to a ServiceMonitor (no Prometheus Operator).
- Grafana dashboard [dashboards/vllm-gpu.json](dashboards/vllm-gpu.json): tokens per second, latency p50 and p95, requests in flight, GPU utilisation, GPU memory, temperature, time to first token, KV cache.
- View it through the SSM tunnel (see [docs/runbook.md](docs/runbook.md)). Dashboard screenshot under load: _to add_.

## Cost
- Plan: about USD 15 for the exercise (budget cap 150). Platform without GPU about $0.24/hr; GPU adds $1.01/hr On-Demand (Spot $0.43 to $0.53 when available). See [ADR-001](docs/adr/ADR-001-instance-type-and-capacity-model.md) and [ADR-003](docs/adr/ADR-003-cost-and-sizing.md).
- Everything that bills by the hour is a Terraform toggle, off by default.

## Known limitations and deviations from the brief
- **GPU capacity:** Spot `g5.xlarge` had no capacity (`UnfulfillableCapacity`, also after widening to g6 and g4dn and a second AZ), so the GPU node ran On-Demand. The Spot group stays in code behind `enable_gpu_nodes`.
- **EKS control-plane logging off by default** and **no `logs` endpoint** (CloudWatch cost). Supported by `enable_eks_control_plane_logs`. No CloudTrail trail.
- **Locking:** S3 native locking instead of DynamoDB (Terraform >= 1.11).
- **Encryption:** node volumes use the existing customer-managed KMS key (shared with Identity Center, rotation off). S3, EKS secrets and the bastion volume use default encryption.
- **Model:** dev model is Qwen2.5-0.5B. A 7B run is optional (see ADR-006).
- **Single working AZ** (us-east-1c) and single replica: no high availability.
- **No `eks` VPC endpoint:** `aws eks update-kubeconfig` does not work on the bastion; `k8s/bootstrap.sh` writes the kubeconfig itself.
- Plain HTTP inside the VPC, no authentication in front of vLLM (see the law-firm answer for production).
