# ADR-012: Two subnets, one working AZ (us-east-1c)

- **Status:** Accepted (2026-10-18)
- **Related:** [ADR-001](ADR-001-instance-type-and-capacity-model.md), [ADR-008](ADR-008-cost-and-sizing-rules.md), [task.md](../../task.md) section 2.1 (private subnets in at least two AZs)

## Context
- EKS and the internal ALB need subnets in at least two AZs.
- Cross-AZ traffic costs $0.01/GB each way.
- Interface endpoints cost about $0.01/hr per AZ each, so every extra AZ doubles that line.
- Spot price is a rough demand signal. g5.xlarge Spot by AZ (EC2 API, last hour, 2026-10-18): 1c $0.429, 1d $0.431, 1f $0.476, 1b $0.485, 1a $0.533.

## Decision
- **Subnets:** `us-east-1c` and `us-east-1d` (the two cheapest g5 Spot AZs). VPC `10.20.0.0/16`, subnets `10.20.1.0/24` and `10.20.2.0/24`.
- **Working AZ: 1c** (variable `primary_az`). All nodes, the bastion, the endpoints and the pods run there.
- 1d is spare capacity for the control-plane ENIs and the ALB, and the fallback if 1c runs short.
- `describe-instance-type-offerings` confirms `t4g.small`, `t4g.micro`, `g5.xlarge`, `g4dn.xlarge` and `g5g.xlarge` exist in both 1c and 1d.
- Operator's view that 1d is less crowded cannot be verified; the choice rests on price.

## Alternatives considered
- **Spread nodes over both AZs:** resilient, but doubles endpoint cost (about $0.09/hr more for 9 endpoints) and adds cross-AZ transfer.
- **us-east-1a and 1b:** the first pick, but 1a is the dearest g5 Spot AZ ($0.533, about $0.10/hr more, about $1 over 10 GPU hours).
- **Single subnet:** not allowed by EKS or the ALB.

## Consequences
**Positive**
- Near-zero cross-AZ cost; one set of endpoints.
- Cheapest observed g5 Spot price.

**Negative**
- No AZ resilience: an AZ outage or no Spot capacity in 1c stops the system.
- One AZ narrows the Spot pool; fallback is `primary_az = us-east-1d` or `g4dn.xlarge`.
- The ALB still has nodes in both AZs, so a little ALB-to-pod traffic can cross AZs. Negligible at load-test volume.
- One hour of price history is a thin sample.
