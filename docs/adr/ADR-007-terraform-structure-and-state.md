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
3. **Locking:** S3 native locking (`use_lockfile = true`, Terraform 1.10 or later) with **no DynamoDB table**. Bucket has versioning, default encryption, and public access blocked.
4. **Versions:** `required_version` and provider versions are pinned in every stack; `.terraform.lock.hcl` is committed. Backend config is partial (bucket passed at `init`) so no environment-specific values are hard-coded.
5. **Kubernetes/Helm resources are not managed from Terraform** (private cluster, see ADR-006); they are applied from the bastion using `k8s/`.

## Alternatives considered

- **One stack with feature toggles.** Simpler to read, but teardown means careful targeted applies, and an accidental destroy would also wipe weights and mirrored images.
- **Stack per component (network, eks, nodes, ...).** Finer control but more remote-state wiring and slower to build for a 3-day exercise.
- **S3 + DynamoDB locking (the brief's default).** Works, but DynamoDB locking is being deprecated in favour of S3 native locking and adds a table to create and destroy. The brief explicitly allows documenting a different choice.
- **Local state.** No setup, but no locking, no versioning, and easy to lose; poor hygiene signal.

## Consequences

Positive
- `terraform destroy` in `platform` stops the bill without touching weights or images; recreating the cluster does not re-upload gigabytes.
- Blast radius of each apply is small; state paths are self-describing.
- One fewer AWS resource (no DynamoDB) and nothing to clean up for locks.

Negative / risks
- Cross-stack coupling through `terraform_remote_state`: output names are an interface and must be changed carefully; apply order is foundation, then platform (destroy in the reverse order).
- S3 native locking needs Terraform 1.10+ (we pin 1.16.x) and conditional-write support; if the lockfile gets stuck, `terraform force-unlock` or deleting the `.tflock` object is needed.
- Bootstrap uses local state, so that single file must be kept until the bucket is imported or left alone; losing it does not lose any other stack's state.
