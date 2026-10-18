# ADR-011: No CloudWatch Logs by default; EKS audit logging is a toggle

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-005](ADR-005-skip-account-cloudtrail.md), [ADR-008](ADR-008-cost-and-sizing-rules.md), [task.md](../../task.md) section 2.2 ("Enable control-plane logging ... `api`, `audit`, `authenticator`")

## Context
- EKS control-plane logs can only be delivered to CloudWatch Logs: about $0.50/GB ingested plus storage.
- The brief asks for them, but the PoC budget does not justify the spend.
- Loki and Promtail see pod and node logs only. They cannot replace the EKS audit log.

## Decision
- **Code supports it, default is off:**
  - `enable_eks_control_plane_logs = false`.
  - `eks_control_plane_log_types = ["api", "audit", "authenticator"]` (used only when on).
  - `eks_log_retention_days = 3`.
- With the toggle off, no log types are enabled and **no log group is created**.
- Turning it on is a deliberate step that needs the owner's approval.
- **Everything else stays absent:** no VPC flow logs, no Container Insights or CloudWatch agent, no Session Manager session logging, no CloudWatch alarms.
- **No `logs` VPC endpoint** by default (it would cost $0.01/hr for nothing). Add `logs` to `interface_endpoints` if CloudWatch is ever used.
- **Operational logs:** Loki + Promtail (or Grafana Alloy) in Grafana, stored on node disk or S3.
- Metrics are Prometheus (vLLM, DCGM, node-exporter) in Grafana.

## Alternatives considered
- **Always on:** meets the brief literally. A small idle cluster is cents per day, but it adds CloudWatch cost for no PoC benefit.
- **Never implement:** saves code, but removes the audit capability that production needs.
- **Ship logs to S3 or Loki instead:** EKS cannot deliver control-plane logs anywhere except CloudWatch.

## Consequences
**Positive**
- $0 CloudWatch spend in the default run.
- The required setting is one variable away, so it can be demonstrated for a short window.

**Negative**
- **Default run deviates from brief 2.2:** no EKS audit log and no `logs` endpoint. The README must say so.
- No audit trail of Kubernetes API calls in the default run.
- The law-firm answer must say production needs the audit log on and shipped to an immutable store.
- Debugging control-plane issues is harder with logs off.
