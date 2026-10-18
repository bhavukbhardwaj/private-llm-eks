# Private LLM inference on EKS

Serves **Qwen2.5-7B-Instruct** with vLLM on one NVIDIA A10G, inside a private VPC on Amazon EKS. Everything is Terraform and Kubernetes manifests. The model is reachable only from inside the VPC, and it is monitored with Prometheus, the NVIDIA DCGM exporter and Grafana.

- API: OpenAI-compatible `POST /v1/chat/completions` behind an **internal ALB**.
- No internet gateway, no NAT gateway, no public ingress. Images come from private ECR and the weights from S3, through VPC endpoints.
- Pods reach AWS only through IRSA. People use SSO. The EKS API is private, reached through an SSM bastion.

**What is running** (AWS console, EC2): two system nodes (`t4g.small`), the SSM bastion (`t4g.micro`) and the GPU node (`g5.xlarge`), all in us-east-1c, with **no public IP or DNS on any of them**.

![EC2 instances](docs/evidence/ec2-instances.png)

## Architecture
![AWS architecture](docs/architecture/aws-architecture.png)

![Deploy, operate, request and observe paths](docs/architecture/request-and-ops-flow.png)

## Repository
```
terraform/   bootstrap (state), foundation (VPC, ECR, S3), platform (EKS, nodes, bastion), modules
k8s/         manifests and bootstrap.sh (runs on the bastion)
dashboards/  Grafana dashboard JSON
scripts/     image mirroring, tool staging, model upload
loadtest/    load test client
docs/        adr (decisions), architecture, evidence, runbook, security, law-firm answer
```

## Deploy from scratch
Needs an AWS account with SSO, GPU quota (4 vCPU) in us-east-1, Terraform 1.11 or newer, AWS CLI, kubectl, helm, crane and docker. Full commands: [docs/runbook.md](docs/runbook.md).

| Step | Command |
|---|---|
| 1. State bucket and foundation | `terraform apply` in `terraform/bootstrap`, then `terraform/foundation` |
| 2. Images and tools | `scripts/mirror-images.sh`, `scripts/stage-tools.sh` (big images from AWS CloudShell) |
| 3. Model weights | `scripts/upload-model-stream.sh <models-bucket>` (from CloudShell) |
| 4. Platform (hourly billing starts) | `terraform apply` in `terraform/platform` (set `enable_gpu_ondemand_nodes = true` for the GPU) |
| 5. Cluster files | `scripts/stage-k8s.sh`, then on the bastion `~/k8s/bootstrap.sh` |
| 6. GPU, monitoring, model | on the bastion: `bootstrap.sh gpu`, `bootstrap.sh monitoring`, `bootstrap.sh llm` |

**Destroy:** `terraform destroy` in `terraform/platform` stops the hourly bill. `foundation` (S3, ECR) costs cents per month.

## Try it
On the bastion (the endpoint is internal, so it works only from inside the VPC):
```
~/k8s/ask.sh "Explain why private networking matters"      # prints the answer
~/k8s/bootstrap.sh loadtest                                  # 200 requests, concurrency 8, from a pod
REQUESTS=600 CONCURRENCY=4 ~/k8s/bootstrap.sh loadtest
```

## Results (Qwen2.5-7B-Instruct, one A10G)
Load test from a pod in the cluster, through the internal ALB, 128 max output tokens:

| Requests / concurrency | Throughput | Latency p50 / p95 | Errors |
|---|---|---|---|
| 200 / 8 | 4.7 req/s, 228 tokens/s | 1.69 s / 1.86 s | 0 |

GPU memory in use: 19.8 GiB of 22.5 GiB. Raw output: [docs/evidence/phase5-7b-and-loadtest.txt](docs/evidence/phase5-7b-and-loadtest.txt). Proof the GPU runs: [docs/evidence/phase3-nvidia-smi.txt](docs/evidence/phase3-nvidia-smi.txt).

Grafana dashboard during the 200-request run on the 7B model (about 14:24): requests in flight reach 8, GPU utilisation hits 100%, GPU memory stays at about 19 GiB, latency p50 and p95 are about 1.75 s and 1.97 s, temperature peaks at 48 °C.

![Grafana dashboard under load](docs/evidence/grafana-dashboard-under-load.png)

## vLLM settings
| Argument | Value | Why |
|---|---|---|
| `--model` | `/models` | weights synced from S3, no internet download |
| `--served-model-name` | `qwen2.5-7b-instruct` | stable API name |
| `--max-model-len` | `8192` | KV cache fits beside 15 GB of weights on 24 GB |
| `--gpu-memory-utilization` | `0.90` | headroom for CUDA graphs |
| `--tensor-parallel-size` | `1` | one A10G |

Pod resources: 1 GPU, 2 CPU and 8 GiB requested, 13 GiB memory limit.

## Probes: readiness vs liveness
- **Readiness** asks "can it take traffic now?". On failure the pod leaves the Service and the ALB, but is not restarted.
- **Liveness** asks "is it still alive?". On failure the container is restarted.
- A **startup probe** gives vLLM up to 15 minutes to load the model before liveness starts.

## Known limitations and deviations
- **GPU is On-Demand:** Spot `g5.xlarge` had no capacity (`UnfulfillableCapacity`), even with g6 and g4dn and a second AZ. The Spot group is in code behind `enable_gpu_nodes`. [ADR-001](docs/adr/ADR-001-instance-type-and-capacity-model.md)
- **EKS control-plane logging and the `logs` endpoint are off by default** to avoid CloudWatch cost. `enable_eks_control_plane_logs` turns logging on. No CloudTrail trail. [ADR-004](docs/adr/ADR-004-security.md)
- **S3 native state locking** instead of DynamoDB (Terraform 1.11 or newer). [ADR-005](docs/adr/ADR-005-delivery-and-terraform.md)
- **Node disks use an existing customer-managed KMS key** shared with Identity Center (rotation off). Other storage uses default encryption.
- **Single replica, one working AZ, plain HTTP inside the VPC, no authentication in front of vLLM:** fine for a PoC. See [docs/law-firm-answer.md](docs/law-firm-answer.md) for what production needs.
- There is no `eks` VPC endpoint, so `aws eks update-kubeconfig` does not work on the bastion. `bootstrap.sh` writes the kubeconfig itself.

## More
[Decisions (ADRs)](docs/adr/) · [Security controls](docs/security.md) · [Runbook](docs/runbook.md) · [Law-firm answer](docs/law-firm-answer.md) · [Status](deliverable.md)
