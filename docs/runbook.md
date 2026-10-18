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
- `bootstrap.sh` does: kubeconfig, `kubectl get nodes`, Load Balancer Controller (Helm), placeholder app, `curl` of the internal ALB.
- One step only: `~/k8s/bootstrap.sh kubeconfig` (or `lb`, or `placeholder`).
- Bucket name now: `private-llm-tools-ded4d08d`. `scripts/stage-k8s.sh` prints the exact command for the current bucket.
- Re-run `scripts/stage-k8s.sh` after changing anything under `k8s/`, then repeat the three bastion commands.

## 3. Day-to-day on the bastion
```
kubectl get nodes -o wide
kubectl get pods -A
kubectl -n demo get ingress
```

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
