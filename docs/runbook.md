# Runbook

Commands to build, run and tear down the system. Bucket names carry a random suffix: get them with `terraform -chdir=terraform/foundation output` (`tools_bucket`, `models_bucket`). `scripts/stage-k8s.sh` prints the exact sync command for the current tools bucket.

## 1. Build (laptop)
```
cd terraform/bootstrap  && terraform init && terraform apply                          # state bucket
cd ../foundation        && terraform init -backend-config="bucket=<state bucket>" && terraform apply
scripts/mirror-images.sh        # images into ECR (copy big ones from AWS CloudShell: see below)
scripts/stage-tools.sh          # kubectl, helm, k9s, stern for the bastion
scripts/upload-model-stream.sh <models bucket>     # 7B weights, run in CloudShell
cd terraform/platform   && terraform init -backend-config="bucket=<state bucket>" && terraform apply
scripts/stage-k8s.sh            # manifests and config for the bastion
```
- `terraform/platform/terraform.tfvars` (not in git) sets `state_bucket`, `kms_key_arn` and the toggles. See `terraform.tfvars.example`.
- Turn the GPU node on with `enable_gpu_ondemand_nodes = true` (or `enable_gpu_nodes = true` for Spot) and apply.
- **Big image copy from CloudShell:** download `crane`, log in with `aws ecr get-login-password | crane auth login <registry> -u AWS --password-stdin`, then `crane copy --platform linux/amd64 docker.io/vllm/vllm-openai:v0.31.0 <registry>/vllm:v0.31.0` (about 1 minute, against 30+ minutes from a laptop).

## 2. Set up the cluster (bastion)
Connect: AWS console, EC2, select the bastion, Connect, Session Manager. Then:
```
aws s3 sync s3://<tools bucket>/k8s ~/k8s && chmod +x ~/k8s/*.sh
~/k8s/bootstrap.sh              # kubeconfig, Load Balancer Controller, placeholder app behind an internal ALB
~/k8s/bootstrap.sh gpu          # NVIDIA device plugin and an nvidia-smi pod (GPU node must be up)
~/k8s/bootstrap.sh monitoring   # Prometheus, Grafana, DCGM exporter
~/k8s/bootstrap.sh llm          # vLLM from S3 behind an internal ALB, then a chat request
```
Re-run `scripts/stage-k8s.sh` and the `aws s3 sync` line after changing anything under `k8s/`. Use `k9s` or `kubectl` to look around; `stern -n llm vllm` follows logs.

## 3. Use it (bastion)
```
~/k8s/ask.sh "Your question"                                  # prints the answer
~/k8s/bootstrap.sh loadtest                                    # 200 requests, concurrency 8
REQUESTS=600 CONCURRENCY=8 ~/k8s/bootstrap.sh loadtest         # change the numbers (7B does about 4.7 req/s)
```
The load test result is printed as JSON and saved to `~/loadtest-result.json`.

## 4. View Grafana
Grafana is not exposed. On the bastion: `kubectl -n monitoring port-forward svc/grafana 3000:80 --address 127.0.0.1`. On the laptop (needs `session-manager-plugin`):
```
aws ssm start-session --target <bastion instance id> --document-name AWS-StartPortForwardingSession --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'
```
Open `http://localhost:3000`, user `admin`. The password: `kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.password}' | base64 -d`.

## 5. Tear down
`terraform destroy` in `terraform/platform` stops the hourly bill. `terraform/foundation` (S3, ECR) costs cents per month; destroy it last, then `terraform/bootstrap`.

## Known problems and fixes
- `aws eks update-kubeconfig` hangs on the bastion: there is no `eks` VPC endpoint. `bootstrap.sh` writes the kubeconfig itself.
- vLLM crash-loops with `VLLM_PORT ... appears to be a URI`: a Service named `vllm` injects `VLLM_PORT`. The pod sets `enableServiceLinks: false`.
- `nvidia-smi` fails with `libdl.so.2` in a busybox pod: use a glibc image (the test pod uses `aws-cli`).
- GPU node group stays "Creating" with `UnfulfillableCapacity`: Spot has no capacity. Use the On-Demand group.
- New ALB name does not resolve, or returns 503: wait 2 to 4 minutes while it provisions and registers targets.
