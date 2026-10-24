# ADR-0012: Lab SLI/SLO Framework and Resilience Chaos Drills

**Status:** Accepted  
**Date:** 2026-10-22  
**Deciders:** ForgeOps Architecture Review

---

## Context
A critical differentiator between an amateur DevOps project and senior SRE engineering practice is the shift from passive monitoring to active reliability engineering. Amateur projects claim "99.99% high availability" on a single laptop node—a claim that is technically false and easily discredited by interviewers.

ForgeOps requires a disciplined reliability engineering framework rooted in reality:
- Establishing authentic local Service Level Objectives (SLOs) and Service Level Indicators (SLIs).
- Defining measurable error budgets appropriate for single-host lab environments.
- Executing controlled, reproducible resilience drills (chaos experiments) with verifiable telemetry evidence.

## Options Considered
1. **Fictitious Production SLA Claims:** Claiming 99.99% availability with multi-region failover on Kind. Rejected as dishonest and technically flawed.
2. **Passive Uptime Monitoring:** Simply checking if pods are running without load testing or failure injection. Insufficient to demonstrate SRE competency.
3. **Formal Lab SLI/SLO Framework with Scoped Chaos Drills:** Establish realistic local learning SLOs, generate measurable k6 load, and execute a structured 10-drill resilience matrix with captured incident runbooks.

## Decision
Adopt a **Formal Lab SLI/SLO Framework** and the **ForgeOps 10-Drill Resilience Matrix**:

### 1. Lab SLIs & Objectives (Local Learning Targets):
- **Availability SLI:** Percentage of successful HTTP requests (`2xx`/`3xx`/`4xx` vs `5xx`) over a rolling 10-minute window during load testing.
  - *Lab Objective:* ≥99.0% availability under baseline k6 load (50 virtual users for 2 minutes).
- **Latency SLI:** 95th percentile (p95) HTTP request latency measured via Prometheus histogram (`http_server_requests_seconds_bucket`).
  - *Lab Objective:* p95 latency <500 ms on a warmed machine under baseline load.
- **Recovery Time Objective (RTO):** Measured time to recover from a complete local database loss + cluster reset.
  - *Lab Objective:* RTO ≤60 minutes using automated runbooks and verified host backups.
- **Recovery Point Objective (RPO):** Maximum age of recovered data.
  - *Lab Objective:* RPO ≤24 hours (governed by host backup schedule).

### 2. The 10-Drill Resilience Matrix (Scoped Lab Injections):

| Drill ID | Injected Failure Event | Detection Signal | Recovery Action | Target Proof |
|---|---|---|---|---|
| **DR-01** | Delete 1 stateless API pod | Pod restart / event | Kubernetes Deployment recreates pod | Zero downtime if 2 replicas; brief interruption on 1 replica |
| **DR-02** | Deploy nonexistent image digest to dev | `ImagePullBackOff` | Git revert to known-good digest | Rollout restored to healthy state within 5 min |
| **DR-03** | Induce 5xx HTTP responses via fault endpoint | Prometheus 5xx rate | Remove fault toggle | Alert transitions `pending` → `firing` → `resolved` |
| **DR-04** | Pause PostgreSQL container/process | Readiness probe fails | Resume process / restart container | API reconnects; no data corruption |
| **DR-05** | k6 CPU & load pressure (50 VUs) | p95 latency curve rises | Load completes / autoscaling | Grafana latency graph correlates with k6 report |
| **DR-06** | Manual out-of-band annotation edit | Argo CD `OutOfSync` | Argo auto-sync self-heal | Annotation reverted automatically to Git state |
| **DR-07** | Delete disposable DB records | HTTP 404 / error | Host backup restore to scratch DB | Row count & referential integrity matched |
| **DR-08** | Unauthorized cross-namespace probe | Connection timeout | Policy blocks bad flow | Negative test table verified under Cilium |
| **DR-09** | Corrupt Nginx configuration on VM | Config syntax error | Idempotent Ansible re-run | `changed=1`, second run `changed=0` |
| **DR-10** | Manual drift on Terraform lab fixture | `terraform plan` diff | Approved `terraform apply` | State matches real fixture without collateral damage |

## Consequences & Trade-offs
### Positive:
- **Truthful Engineering:** Metrics and incident timelines reflect real measurements on local hardware rather than fabricated uptime.
- **Runbook Provenance:** Incident runbooks are authored and validated against actual injected failures.
- **Portfolio Impact:** Demonstrates genuine incident diagnosis, telemetry correlation, and post-mortem analysis.

### Negative / Limitations:
- Running load drills (DR-05) temporarily elevates laptop CPU and fan activity.
- Database restore drills (DR-07) require disk space for scratch databases.

## Verification Tests
- Every drill produces a timestamped incident report in `docs/evidence/G12/` with alert links, PromQL queries, and Grafana screenshots.
- RTO/RPO exercise logs document exact elapsed seconds from failure injection to healthy readiness probe verification.

## Reconsideration Triggers
- Modification of load test profiles if host CPU throttling occurs during k6 test execution.
