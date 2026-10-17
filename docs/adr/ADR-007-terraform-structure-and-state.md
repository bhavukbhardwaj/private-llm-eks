# ADR-007: Two Terraform stacks, per-stack state paths, S3 native locking (no DynamoDB)

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-006](ADR-006-cluster-access-ssm-bastion.md), [ADR-008](ADR-008-cost-optimisation-choices.md), [task.md](../../task.md) section 2.1 (remote state with DynamoDB locking "or document why")

## Context

The sandbox has a hard cost cap and must be torn down between sessions. Some resources are cheap but slow or tedious to recreate (model weights uploaded to S3, mirrored ECR images); others bill hourly (EKS control plane, GPU nodes, interface endpoints, bastion). The brief asks for remote state with locking and pinned versions.

## Decision

1. **Stacks (separate root modules, separate states):**
   - `terraform/bootstrap/`: the state bucket only. Applied once with local state (the local `.tfstate` is gitignored; if lost, the bucket is re-imported).
   - `terraform/foundation/` (persistent, low cost): VPC and subnets, S3 gateway endpoint, ECR repositories, model-weights and tools S3 buckets, optional KMS key.
   - `terraform/platform/` (disposable, hourly cost): interface endpoints, EKS, node groups, bastion, IRSA roles, managed add-ons. Destroying this stack stops essentially all hourly charges.
   - `platform` reads `foundation` outputs through `terraform_remote_state`. Shared logic lives in `terraform/modules/*`.
2. **State layout** in one bucket, one key per stack and environment, not one shared file:
   `s3://<state-bucket>/<project>/<environment>/<stack>/terraform.tfstate`, for example `private-llm/sandbox/foundation/terraform.tfstate` and `private-llm/sandbox/platform/terraform.tfstate`. The bucket name carries a random suffix (no account ID in names).
3. **Locking:** S3 native locking (`use_lockfile = true`, generally available from Terraform 1.11; we pin 1.11 or later) with **no DynamoDB table**. Bucket has versioning, default encryption, and public access blocked.
4. **Versions:** `required_version` and provider versions are pinned in every stack; `.terraform.lock.hcl` is committed. Backend config is partial (bucket passed at `init`) so no environment-specific values are hard-coded.
5. **Simple, uniform file layout and readable code.** Every stack (and module) uses the same small set of files so anyone, human or another AI session, can find things without a guide:

   | File | Contents |
   |---|---|
   | `main.tf` | Resources (or module calls in the stacks); kept as one file unless it passes about 200 lines |
   | `variables.tf` | Inputs with types, descriptions and defaults |
   | `outputs.tf` | Outputs, each with a description |
   | `providers.tf` | `terraform {}` block with `required_version` and provider pins, plus the provider with `default_tags` |
   | `backend.tf` | Remote state config (`foundation` and `platform` only; `bootstrap` uses local state) |

   Plus `terraform.tfvars.example` documenting the inputs. Every `resource`, `data`, `module` and `output` block has a **one-line `#` comment directly above it** saying what it is or why it exists. Structure comes from the modules, not from many small files. Names use the standard plural forms (`variables.tf`, `outputs.tf`, `providers.tf`) because that is what readers expect.
6. **EKS is a hand-written module** (aws_eks_cluster, node groups, launch templates, OIDC, add-ons, access entries) rather than the community `terraform-aws-modules/eks` module: fewer moving parts, no module-version surprises, and every line is reviewable against the brief. Costs more code to maintain.
7. **Kubernetes/Helm resources are not managed from Terraform** (private cluster, see ADR-006); they are applied from the bastion using `k8s/`.

## Terraform version and the features we rely on

| Item | Value |
|---|---|
| Terraform in use | **1.16.6** (installed 2026-10-18, checked against HashiCorp's release check: it is the current release) |
| Pin in code | `required_version = ">= 1.11.0, < 2.0.0"` (1.11 is where S3 native locking became generally available) |
| AWS provider | `~> 6.0`, locked at 6.69.1 in the committed `.terraform.lock.hcl` |
| Random provider | `~> 3.6`, locked at 3.9.1 |

Why this matters: recent Terraform removes the need for a DynamoDB lock table.
- **1.10** added S3 native state locking (experimental) and ephemeral values/resources.
- **1.11** made S3 native locking **generally available** (`use_lockfile = true`), **deprecated the DynamoDB locking arguments**, and added write-only attributes (values that are never stored in state, useful for secrets).
- So our backend sets `use_lockfile = true` and has **no `dynamodb_table`**. The lock is a small `.tflock` object next to the state file, created with an S3 conditional write.
- **1.15** added `deprecated` on variables/outputs, `convert()`, variables and locals in module `source`/`version`, and `terraform validate` now checks the `backend` block.
- **1.16** added `import` blocks inside modules (useful if we need to re-import the bootstrap bucket), and a `store` block on `terraform_data`.
- Release notes read from the HashiCorp changelog on 2026-10-18; features not listed above were not used or checked.

## Alternatives considered

- **One stack with feature toggles.** Simpler to read, but teardown means careful targeted applies, and an accidental destroy would also wipe weights and mirrored images.
- **Stack per component (network, eks, nodes, ...).** Finer control but more remote-state wiring and slower to build for a 3-day exercise.
- **S3 + DynamoDB locking (the brief's default).** Works, but DynamoDB locking is being deprecated in favour of S3 native locking and adds a table to create and destroy. The brief explicitly allows documenting a different choice.
- **Local state.** No setup, but no locking, no versioning, and easy to lose; poor hygiene signal.

## Consequences

Positive
- Uniform five-file layout and one-line comments make the code quick to review and easy for a new session or person to pick up.
- `terraform destroy` in `platform` stops the bill without touching weights or images; recreating the cluster does not re-upload gigabytes.
- Blast radius of each apply is small; state paths are self-describing.
- One fewer AWS resource (no DynamoDB) and nothing to clean up for locks.

Negative / risks
- Cross-stack coupling through `terraform_remote_state`: output names are an interface and must be changed carefully; apply order is foundation, then platform (destroy in the reverse order).
- S3 native locking needs Terraform 1.10+ (we pin 1.16.x) and conditional-write support; if the lockfile gets stuck, `terraform force-unlock` or deleting the `.tflock` object is needed.
- Fewer files means larger `main.tf` files in the stacks; the one-line comments and module boundaries are what keep them readable, and the 200-line guideline is the trigger to split.
- Bootstrap uses local state, so that single file must be kept until the bucket is imported or left alone; losing it does not lose any other stack's state.
