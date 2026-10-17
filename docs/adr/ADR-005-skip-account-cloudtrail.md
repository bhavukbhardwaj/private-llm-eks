# ADR-005: Do not create an account-wide CloudTrail trail in the sandbox

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-004](ADR-004-aws-authentication-sso.md), [task.md](../../task.md) section 2.2 (EKS control-plane logging)

## Context

The Phase 0 hardening list included an account-wide CloudTrail trail. The sandbox is a personal account with a single human user (SSO) and no IAM users or shared access. The brief requires EKS control-plane logging (`api`, `audit`, `authenticator`), which is separate from CloudTrail and is still in scope.

## Decision

Do not create a CloudTrail trail for this exercise. Rely on CloudTrail Event History (management events, 90 days, free, on by default) for any after-the-fact investigation. EKS control-plane logging is a separate toggle, off by default for the PoC (see ADR-008).

## Alternatives considered

- **All-region trail to an S3 bucket.** Better retention and tamper evidence, and the first management-event trail is free, but it adds a bucket (KMS, policy, lifecycle) and cleanup effort for one user. Rejected for the sandbox.

## Consequences

Positive
- Less setup and nothing extra to tear down.

Negative / risks
- No retention beyond 90 days, no data-event or S3-object logging, and no integrity validation.
- The README's law-firm answer must state that a real deployment needs an organisation trail (multi-region, KMS-encrypted, log-file validation, immutable bucket in a separate account).

## Hardening status at decision time
- Root MFA: enabled. Root access keys: none. IAM users: 0 (checked 2026-10-18).
- S3 account-level Block Public Access: all four settings enabled 2026-10-18.
