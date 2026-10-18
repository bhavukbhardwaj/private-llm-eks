# ADR-010: Encrypt node EBS volumes with the existing customer-managed KMS key

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-008](ADR-008-cost-and-sizing-rules.md), [task.md](../../task.md) section 2.2 ("Encrypt EBS volumes used by nodes with a customer-managed KMS key")

## Context
- The brief requires a customer-managed key (CMK) for node EBS volumes.
- A new CMK costs $1/month plus $0.03 per 10,000 requests, and has a 7 to 30 day deletion window.
- The account already has one CMK, created by IAM Identity Center, so its $1/month is paid regardless.
- Its policy gives the account root `kms:*`, so IAM can delegate use without editing the key policy.
- Account-level EBS default encryption is **off** (checked 2026-10-18).

## Decision
- **Reuse the existing key.** Terraform only references it by ARN (`kms_key_arn`), never creates, edits or destroys it. `terraform destroy` leaves it untouched.
- **ARN is kept out of git:** it contains the account ID, so it goes in the untracked `terraform.tfvars`.
- **Used for:** system and GPU node root volumes (`encrypted = true`, `kms_key_id = <key>`).
- **One extra resource:** an `aws_kms_grant` for the Auto Scaling service-linked role (which exists), so node groups can launch encrypted volumes.
- **Not used for:** S3 (SSE-S3, TLS-only policy, public access blocked), EKS secrets (EKS default), ECR (AES256), and the bastion volume (AWS-managed `aws/ebs`).
- **Why not the bastion volume:** a persistent Spot request would need another grant for the EC2 Spot service-linked role, which does not exist yet.
- Every volume sets `encrypted = true` explicitly.
- `kms_key_arn = null` falls back to AWS-managed encryption.
- The `kms` interface endpoint stays in the list (the brief names it). EBS does not call KMS through it, so it is an idle $0.01/hr.

## Alternatives considered
- **New dedicated CMK:** own policy and rotation, but about $1/month more and one more key to delete.
- **AWS-managed `aws/ebs` only:** free, but does not meet the brief's CMK line.
- **Edit the Identity Center key policy:** more direct, but risks breaking SSO. Rejected; the grant needs no edit.
- **Use the CMK for S3, EKS secrets and ECR too:** adds per-request cost and IAM wiring that the brief does not ask for.

## Consequences
**Positive**
- Meets the brief's CMK line at $0 extra (requests are tens, under one cent).
- Nothing is created, so nothing is left behind after destroy.
- Switching back to AWS-managed is one variable.

**Negative**
- **Shared key:** it belongs to Identity Center. Deleting or changing it would break SSO and encrypted node volumes.
- Key rotation is **off** (not required by the brief). Production needs a dedicated key per purpose with rotation, in a separate account (law-firm answer).
- A missing or wrong grant makes node groups fail to launch, visibly at apply.
- Only EBS is covered; S3 and EKS secrets use default encryption.
