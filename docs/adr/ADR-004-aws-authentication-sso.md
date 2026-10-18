# ADR-004: AWS authentication with IAM Identity Center (SSO)

- **Status:** Accepted (2026-10-18)
- **Related:** [task.md](../../task.md) sections 2.2 and 5 (no long-lived or committed credentials)

## Context
- Personal AWS account with no organisation-level guardrails.
- Terraform, kubectl and helm need credentials from the laptop.
- The brief assesses security posture and forbids committed credentials.

## Decision
- Use **IAM Identity Center (SSO)** with MFA and an 8-hour session.
- Laptop: `aws configure sso`, then `aws sso login`, selected with `AWS_PROFILE`.
- Root user: MFA on, no access keys, not used day to day.
- No IAM user access keys (AK/SK) for people. An exception needs a new ADR and an expiry date.
- Pods use IRSA only.
- Account ID is read with `data.aws_caller_identity`, never hard-coded.
- Temporary credentials pasted in chat are used as environment variables only and never saved in the repo.

## Alternatives considered
- **IAM user with AK/SK:** long-lived, sits on disk, easy to leak. Rejected.
- **Root credentials:** unrestricted and unauditable. Rejected.
- **Assume-role from an IAM user:** still depends on a long-lived key. Rejected.
- **Least-privilege policy instead of Administrator:** better for production, but EKS needs broad IAM, KMS, EC2 and VPC rights and a 3-day sandbox cannot afford the tuning. Deferred.

## Consequences
**Positive**
- Short-lived, MFA-protected credentials with nothing to leak or commit.
- Matches the brief's no-long-lived-credentials rule for people and for pods.
- Cleanup is removing one assignment.

**Negative**
- One-time Identity Center setup (about 15 minutes: enable, user, permission set, MFA).
- Sessions expire mid-work: temporary credentials expired three times in the first 10 hours, each needing a fresh login.
- `AdministratorAccess` is broader than least privilege; accepted for a sandbox and listed as a limitation.
