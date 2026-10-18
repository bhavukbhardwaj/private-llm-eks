# ADR-007: Terraform layout, state and versions

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-008](ADR-008-cost-and-sizing-rules.md), [task.md](../../task.md) section 2.1 (S3 state with DynamoDB locking, or document why)

## Context
- Some things are cheap but slow to recreate (model weights, mirrored images).
- Others bill hourly (EKS, nodes, endpoints, bastion).
- The brief asks for remote state, locking, pinned versions and tags.

## Decision
**Stacks and state**
- `terraform/bootstrap/`: state bucket only, local state, applied once.
- `terraform/foundation/` (persistent): VPC, S3 gateway endpoint, ECR repos, models and tools buckets.
- `terraform/platform/` (disposable): endpoints, EKS, nodes, bastion, IRSA, add-ons.
- `platform` reads `foundation` through `terraform_remote_state`. Shared code is in `terraform/modules/*`.
- State key: `<project>/<environment>/<stack>/terraform.tfstate`, for example `private-llm/assessment/foundation/terraform.tfstate`.
- Bucket name has a random suffix, no account ID.

**Locking and versions**
- **S3 native locking** (`use_lockfile = true`), **no DynamoDB table.**
- Terraform pinned `>= 1.11, < 2.0` (installed 1.16.6). AWS provider `~> 6.0` (locked 6.69.1). Random `~> 3.6` (locked 3.9.1). `.terraform.lock.hcl` is committed.
- Bucket is passed at `init`, so no environment values are hard-coded.
- Why no DynamoDB: S3 native locking was added in 1.10 and became generally available in 1.11, and the DynamoDB arguments were deprecated.

**Readable code**
- Every stack and module has the same files: `main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`, plus `backend.tf` in foundation and platform, and `terraform.tfvars.example`.
- Every `resource`, `data`, `module` and `output` has a one-line `#` comment above it.
- `main.tf` is split only if it passes about 200 lines.
- Tags `Project`, `Environment`, `Owner` come from provider `default_tags`, and are copied onto launch-template resources.

**Other**
- The EKS module is hand-written, not the community module (fewer moving parts, fully reviewable).
- Kubernetes and Helm resources are applied from the bastion, not by Terraform (private cluster, ADR-006).

## Alternatives considered
- **One stack with toggles:** teardown needs targeted applies, and a destroy could also wipe weights and images.
- **One stack per component:** more wiring, slower for 3 days.
- **S3 + DynamoDB locking (brief default):** works, but adds a table and uses the deprecated path.
- **Local state:** no locking or versioning, easy to lose.
- **Community EKS module:** less code, but opaque and version-sensitive.

## Consequences
**Positive**
- `terraform destroy` in `platform` stops the bill and keeps weights and images.
- Small blast radius per apply; state paths are self-describing.
- One uniform layout, easy for a new person or session to read.
- One fewer AWS resource (no lock table).

**Negative**
- Cross-stack outputs are an interface. Apply order is foundation then platform; destroy in reverse.
- A stuck lock needs `terraform force-unlock` or deleting the `.tflock` object.
- Larger `main.tf` files, kept readable by comments and modules.
- The bootstrap local state file must be kept to destroy the bucket (gitignored).
- More hand-written EKS code to maintain.
