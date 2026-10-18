# ADR-005: No account-wide CloudTrail trail in the sandbox

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-004](ADR-004-aws-authentication-sso.md), [ADR-011](ADR-011-logging-and-monitoring-defaults.md)

## Context
- Personal account, one human user (SSO), no IAM users, no shared access.
- Hardening checks done 2026-10-18: root MFA on, no root keys, 0 IAM users, S3 Block Public Access on (all four settings).
- CloudTrail Event History (90 days of management events) is on by default and free.

## Decision
- Do not create a CloudTrail trail for this exercise.
- Use Event History for any after-the-fact check.

## Alternatives considered
- **All-region trail to an S3 bucket:** better retention and tamper evidence, and the first trail is free, but it adds a bucket, policy, lifecycle and cleanup for one user.

## Consequences
**Positive**
- Less setup: no bucket, no policy, no cleanup. Saves about 15 minutes and one S3 bucket.

**Negative**
- No retention beyond 90 days, no data events, no log-file integrity validation.
- The law-firm answer must say production needs an organisation trail: multi-region, KMS-encrypted, log validation, immutable bucket in a separate account.
