# Runbook: commands to run

Copy-paste commands for operating the stack. Names with a random suffix (buckets) differ on a fresh deploy; the current values are shown.

## 1. Connect to the bastion (browser)
- AWS console, region **us-east-1**, EC2, Instances.
- Select `private-llm-assessment-bastion`, Connect, **Session Manager**, Connect.

## 2. Set up the cluster from the bastion (first time, and after a rebuild)
Run on the **laptop** first, so the files and `config.env` are in S3:
```
scripts/stage-k8s.sh
```
Then on the **bastion**:
```
aws s3 sync s3://private-llm-tools-ded4d08d/k8s ~/k8s
chmod +x ~/k8s/bootstrap.sh
~/k8s/bootstrap.sh
```
- Do not use `aws eks update-kubeconfig` or `kube-setup` on the bastion: they call the EKS API, there is no `eks` VPC endpoint, and the command hangs. `bootstrap.sh kubeconfig` writes the kubeconfig from `config.env` instead.
- `bootstrap.sh` does: kubeconfig, `kubectl get nodes`, Load Balancer Controller (Helm), placeholder app, `curl` of the internal ALB.
- One step only: `~/k8s/bootstrap.sh kubeconfig` (or `lb`, or `placeholder`).
- Bucket name now: `private-llm-tools-ded4d08d`. `scripts/stage-k8s.sh` prints the exact command for the current bucket.
- Re-run `scripts/stage-k8s.sh` after changing anything under `k8s/`, then repeat the three bastion commands.

## 2b. Install k9s and stern on the bastion
Stage them from the laptop once (`scripts/stage-tools.sh`, skips what is already there), then on the **bastion**:
```
sudo aws s3 sync s3://private-llm-tools-ded4d08d/bin/ /usr/local/bin/ --region us-east-1
sudo chmod +x /usr/local/bin/*
k9s
```
- **k9s:** terminal UI. `:pods`, `:nodes`, `:ns`; `l` logs, `s` shell into a pod, `d` describe, `ctrl-d` delete, `?` help, `:q` quit.
- **stern:** tail logs of many pods: `stern -n llm vllm`.
- **jq, yq and others:** `sudo dnf install -y jq` works without internet (Amazon Linux repos are served through the S3 endpoint).

## 2c. GPU proof (after the GPU node is on, see section 5)
Stage on the laptop (`scripts/stage-k8s.sh`), then on the bastion:
```
aws s3 sync s3://private-llm-tools-ded4d08d/k8s ~/k8s
~/k8s/bootstrap.sh gpu
```
- Installs the NVIDIA device plugin, waits for `nvidia.com/gpu: 1` on the GPU node, runs a pod that prints `nvidia-smi`, then shows the pod on the GPU node.
- Save the output in `docs/evidence/`.
- The test pod uses the `aws-cli` image (glibc). A busybox image fails with `libdl.so.2: cannot open shared object file`.

## 2d. Serve the model and load test (GPU node on)
On the **bastion**, after the GPU node is up and `bootstrap.sh monitoring` has run once:
```
aws s3 sync s3://private-llm-tools-ded4d08d/k8s ~/k8s && chmod +x ~/k8s/bootstrap.sh
~/k8s/bootstrap.sh llm            # vLLM (S3 sync, GPU), internal ALB, chat-completion curl
~/k8s/bootstrap.sh loadtest       # 200 requests at concurrency 8 from a pod; JSON result
~/k8s/bootstrap.sh session        # both of the above in one go
REQUESTS=300 CONCURRENCY=4 ~/k8s/bootstrap.sh loadtest
```
- The load-test result is printed and saved to `~/loadtest-result.json`. Copy it into the README with the model name.

## 3. Day-to-day on the bastion
```
kubectl get nodes -o wide
kubectl get pods -A
kubectl -n demo get ingress
```

## 3b. GPU checks (after the GPU node is on)
```
kubectl get nodes -l role=gpu -o wide
kubectl describe node -l role=gpu | grep -A8 "Allocatable"        # shows nvidia.com/gpu: 1
kubectl run smi --rm -it --restart=Never --image=<ecr>/busybox:1.38.0 ...   # see k8s/gpu/ for the nvidia-smi pod
kubectl -n llm exec -it deploy/vllm -- nvidia-smi
kubectl -n llm exec -it deploy/vllm -- nvidia-smi dmon -c 5        # utilisation, memory, temperature over time
kubectl -n monitoring port-forward svc/dcgm-exporter 9400:9400     # then curl localhost:9400/metrics | grep DCGM_FI_DEV_GPU_UTIL
```
- GPU tools run inside pods on the GPU node (`nvidia-smi` is in the vLLM and CUDA images), not on the bastion, which has no GPU.

## 4. View Grafana in the laptop browser
- Bastion: `kubectl -n monitoring port-forward svc/grafana 3000:80 --address 127.0.0.1`
- Laptop: `aws ssm start-session --target <bastion-instance-id> --document-name AWS-StartPortForwardingSession --parameters '{"portNumber":["3000"],"localPortNumber":["3000"]}'`
- Browser: `http://localhost:3000`

## 5. Terraform (laptop)
```
terraform -chdir=terraform/bootstrap output -raw state_bucket
terraform -chdir=terraform/platform init -backend-config="bucket=<state bucket>"
terraform -chdir=terraform/platform plan
terraform -chdir=terraform/platform apply
terraform -chdir=terraform/platform destroy      # stops the hourly billing
```
- `terraform/platform/terraform.tfvars` (untracked) holds `state_bucket`, `kms_key_arn` and the toggles.
- Turn the GPU node on with `enable_gpu_nodes = true` and apply.
- Ask the owner before any apply or destroy.

## 6. Images and model
```
scripts/mirror-images.sh --dry-run      # then without --dry-run; ONLY="vllm" for one image
scripts/stage-tools.sh                   # kubectl and helm for the bastion
scripts/copy-progress.sh                 # progress of a running crane copy
```
- Big images: run `crane copy` in AWS CloudShell (about 1 minute for vLLM, 30+ minutes from a laptop). See ADR-005.

## 7. Credentials
- Not stored. Use a fresh SSO login or pasted environment variables.
- Never write them to a file in this repo.
