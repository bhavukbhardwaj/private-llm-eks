# ADR-005: Delivery and Terraform (stacks, state, readable code, image mirroring)

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-003](ADR-003-cost-and-sizing.md), [ADR-004](ADR-004-security.md), [task.md](../../task.md) sections 2.1 and 2.2
- **Index:** D1 stacks and state, D2 locking and versions, D3 readable code, D4 images with `crane copy`

## Context
- Some things are cheap but slow to recreate (model weights, mirrored images). Others bill hourly (EKS, nodes, endpoints, bastion).
- The brief asks for remote state, locking, pinned versions, tags and a private cluster.
- No NAT and no internet gateway, so nodes cannot pull from Docker Hub, quay, nvcr or registry.k8s.io.
- Mixed architecture: arm64 system nodes, x86_64 GPU node.

## Decision
**D1 Three stacks, one state file each**
- `terraform/bootstrap/`: state bucket only, local state, applied once.
- `terraform/foundation/` (persistent): VPC, S3 gateway endpoint, ECR repos, models and tools buckets.
- `terraform/platform/` (disposable): endpoints, EKS, nodes, bastion, IRSA, add-ons. Destroying it stops the hourly bill.
- `platform` reads `foundation` through `terraform_remote_state`. Shared code is in `terraform/modules/*`.
- State key: `<project>/<environment>/<stack>/terraform.tfstate`, e.g. `private-llm/assessment/foundation/terraform.tfstate`. Bucket name has a random suffix, no account ID.
- Kubernetes and Helm resources are applied from the bastion, not by Terraform (private cluster).
- The EKS module is hand-written, not the community module.

**D2 S3 native locking, pinned versions**
- `use_lockfile = true`, **no DynamoDB table**. S3 locking arrived in Terraform 1.10 and became generally available in 1.11, which also deprecated the DynamoDB arguments.
- Terraform `>= 1.11, < 2.0` (installed 1.16.6). AWS provider `~> 6.0` (locked 6.69.1). Random `~> 3.6` (locked 3.9.1). Lock file committed.
- Bucket passed at `init`, so no environment values are hard-coded.
- Tags `Project`, `Environment`, `Owner` come from provider `default_tags`, and are copied onto launch-template resources.

**D3 Same five files everywhere, one-line comment per block**
- Files: `main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`, plus `backend.tf` (foundation, platform) and `terraform.tfvars.example`.
- Every `resource`, `data`, `module` and `output` has a one-line `#` comment above it.
- Split `main.tf` only past about 200 lines.

**D4 Images: `crane copy` into private ECR, never `docker pull` + `docker push`**
- One ECR repo per image (immutable tags, scan on push, keep last 5).
- `crane copy` streams registry to registry, keeps the digest, needs no Docker daemon.
- Platform per image:
  - `linux/arm64`: LB controller, Prometheus stack, Grafana, Loki.
  - `linux/amd64`: vLLM, NVIDIA device plugin, DCGM exporter.
  - All platforms: busybox, node-exporter, aws-cli.
- Only our load-test client is built: `docker buildx build --platform linux/arm64 --push`.
- List and pins: `scripts/images.txt`. Script: `scripts/mirror-images.sh` (`--dry-run`, `ONLY=`, skips existing tags).
- Manifests and Helm values use ECR URLs only.

## Alternatives considered
- **D1 One stack with toggles:** teardown needs targeted applies; a destroy could wipe weights and images.
- **D1 One stack per component:** more wiring, slower in 3 days.
- **D1 Community EKS module:** less code, but opaque and version-sensitive.
- **D2 S3 + DynamoDB locking (brief default):** adds a table and uses the deprecated path.
- **D2 Local state:** no locking or versioning, easy to lose.
- **D4 ECR pull-through cache:** needs upstream credentials for some registries and hides what is pinned.
- **D4 NAT gateway for the first pull:** about $0.045/hr plus data, against the brief.
- **D4 `docker pull/push`:** fetches only the laptop architecture (arm64) and breaks the x86 GPU node.

## Consequences
**Positive**
- `terraform destroy` in `platform` stops the bill and keeps weights and images.
- Small blast radius per apply; one uniform layout that is easy to review.
- One fewer AWS resource (no lock table).
- Pinned, scannable, multi-arch images; no internet path at runtime. Storage about $0.10/GB-month.

**Negative**
- Stack outputs are an interface. Apply order foundation then platform; destroy in reverse.
- A stuck lock needs `terraform force-unlock` or deleting the `.tflock` object.
- Bootstrap's local state file must be kept to destroy the bucket (gitignored).
- More hand-written EKS code to maintain; larger `main.tf` files.
- A manual mirror step on every version bump. Some charts hard-code registries; check values for public references.
- vLLM (9.04 GB) takes about 30 min to copy at 40 Mbit/s from a laptop.
