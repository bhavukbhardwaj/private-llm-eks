# ADR-004: Authenticate to AWS with IAM Identity Center (SSO), not long-lived access keys

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-000](ADR-000-skeleton-first-scope.md), [task.md](../../task.md) section 2.2 ("Do not put long-lived credentials in the cluster") and section 5 ("Do not commit credentials")

## Context

The exercise runs in a personal AWS account. Terraform, kubectl and helm need AWS credentials from the laptop. The brief assesses security posture and forbids committed credentials. A personal account has no organisation-level controls, so the choice of credential type is the main protection against key leakage and unexpected spend.

## Decision

Use **AWS IAM Identity Center (SSO)** with a permission set assigned to the account, MFA enabled, and a short session duration (4 to 8 hours). On the laptop, use a named profile created with `aws configure sso` and sign in with `aws sso login`. Terraform and CLI tools use that profile via `AWS_PROFILE`; no credentials are written into the repo, tfvars, or environment files.

Supporting rules:
- Root user: MFA on, no access keys, not used for day-to-day work.
- No IAM user access keys (AK/SK) for humans. If one ever becomes unavoidable, it needs a new ADR, MFA, and a deletion date.
- Pods use IRSA (never static keys).
- Account ID is not hard-coded; Terraform reads it with `data.aws_caller_identity`.
- At the end of the exercise, remove the permission set assignment and any leftover resources.

## Alternatives considered

- **IAM user with access key and secret key (AK/SK).** Simpler to set up, but keys are long-lived, sit on disk in `~/.aws/credentials`, can be leaked through git, logs or shell history, and keep working until someone rotates them. Rejected.
- **Root user credentials.** Unrestricted and unauditable; rejected outright.
- **Assume-role from an IAM user with MFA.** Better than raw keys but still depends on a long-lived key for the base user. Rejected in favour of SSO.
- **Fine-grained least-privilege policy instead of Administrator.** Preferred in production, but Terraform for EKS needs broad IAM, KMS, EC2 and VPC rights, and an exact policy is time-consuming for a 3-day sandbox. Deferred; noted as a limitation.

## Consequences

Positive
- Credentials are short-lived and expire on their own; nothing long-lived to leak or commit.
- MFA is enforced at sign-in, and sign-ins are recorded in CloudTrail.
- Matches the brief's no-long-lived-credentials principle at the human level as well as the pod level.
- Easy cleanup: remove the assignment and access is gone.

Negative / risks
- One-time setup of Identity Center (enable in us-east-1, create user and permission set, set a password and MFA).
- Sessions expire mid-work; long `terraform apply` runs may need a fresh `aws sso login` (use a session of at least 8 hours).
- The permission set is `AdministratorAccess`, which is broader than least privilege; accepted for a sandbox and documented as a known limitation.
- Some tools handle SSO profiles poorly; if needed, export short-lived credentials with `aws configure export-credentials --profile <name>`, never saving them to files in the repo.
