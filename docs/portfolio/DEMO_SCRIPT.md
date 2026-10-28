# ForgeOps: 3-5 Minute Technical Demonstration Script

## 1. Overview & Objective

This demo script provides a structured, professional 3 to 5-minute technical walkthrough of the ForgeOps platform. It is designed for live portfolio presentations, video recordings, or interactive recruiter technical screenings.

**Key Theme:** "From Git Commit to Distributed Observability, Chaos Resilience, and Zero-Downtime Disaster Recovery without Paid Cloud Services."

---

## 2. Walkthrough Timeline (Total: 4:30)

| Timestamp | Phase | Topic | Interface / Screen |
|:---|:---|:---|:---|
| **0:00 - 0:45** | 1. Introduction | Architecture, Zero-Cloud Problem Statement & Kind Cluster | Terminal (`kubectl get nodes,pods -A`) |
| **0:45 - 1:30** | 2. Supply-Chain & CI | GitHub Actions CI/CD, Kyverno Policy Enforcement, SOPS | GitHub Actions UI / Terminal |
| **1:30 - 2:30** | 3. GitOps & Observability | Argo CD Reconciler, Prometheus Metrics & Tempo Trace-to-Logs | Grafana UI (`:3000`) & Argo CD UI |
| **2:30 - 3:45** | 4. Reliability & Recovery | SRE Chaos Testing (k6) & PostgreSQL Automated DR Rehearsal | Terminal (`scripts/cluster/dr/rehearse-dr.sh`) |
| **3:45 - 4:30** | 5. Conclusion | Evidence Audit, Reproducibility & Engineering Trade-offs | Browser (`docs/audit/REQUIREMENTS_TRACEABILITY_MATRIX.md`) |

---

## 3. Step-by-Step Narration & Execution Guide

### Phase 1: Architecture & Cluster Baseline (0:00 - 0:45)
- **Speaker Narration:**
  > "Hello, I’m walking through ForgeOps, a production-inspired platform engineering lab built to model the full software delivery and operational lifecycle on a local developer workstation without paid cloud dependencies.
  > Here in our Kind Kubernetes cluster, we have our core workloads running across strictly defined namespaces: `forgeops-dev` for the microservice and PostgreSQL, `forgeops-gitops` for Argo CD, and `forgeops-observability` hosting Prometheus, Grafana, Loki, Alloy, and Tempo."
- **Terminal Command:**
  ```bash
  kubectl get nodes -o wide
  kubectl get pods -n forgeops-dev
  kubectl get pods -n forgeops-observability
  ```
- **Key Visual:** All pods in `Running` state, zero restarts, clear separation of namespaces.

---

### Phase 2: Shift-Left Security & CI/CD Pipeline (0:45 - 1:30)
- **Speaker Narration:**
  > "Every commit to ForgeOps goes through our GitHub Actions CI pipeline. Notice our defense-in-depth model:
  > First, we download Kyverno, SOPS, and age binaries, validating each against pinned, authentic SHA-256 release checksums to prevent supply-chain tampering.
  > Next, Kyverno audits our rendered Helm templates against ten Kubernetes security policies—guaranteeing no root containers, no privilege escalation, and read-only filesystems.
  > Finally, SOPS validates encrypted secret integrity using dual asymmetric age key escrow without exposing private keys in CI."
- **Terminal / Browser Command:**
  ```bash
  python3 scripts/test_g14_security.py
  python3 scripts/test_g14_sops.py
  ```
- **Key Visual:** 7/7 Kyverno policy test suites pass; SOPS decrypts dual-recipient ciphertext cleanly.

---

### Phase 3: GitOps & Three-Pillar Correlated Observability (1:30 - 2:30)
- **Speaker Narration:**
  > "Deployment is governed by Argo CD using declarative GitOps. Rather than CI pushing directly to the cluster, Argo CD continuously pulls desired state from Git.
  > In our observability stack, we’ve unified metrics, logs, and traces. When an HTTP request hits our Spring Boot API, OpenTelemetry injects a W3C trace context.
  > Inside Grafana, if an alert fires in Prometheus, an engineer clicks directly from the metric spike into the Tempo distributed trace, and with one click jumps to the exact Loki log lines bearing that `trace_id`."
- **Browser Navigation:**
  1. Open Grafana (`http://localhost:3000`).
  2. Navigate to **Explore -> Tempo**, query recent traces.
  3. Click **Trace to Logs** to reveal the correlated log record in Loki with matching `request_id`.

---

### Phase 4: SRE Chaos Injection & Automated Disaster Recovery (2:30 - 3:45)
- **Speaker Narration:**
  > "In Gate G12, we injected five chaos experiments under k6 load—including worker CPU exhaustion and sudden Pod termination. We recorded 2,275 HTTP requests with zero errors, and measured replica recovery in 52 seconds.
  > In Gate G13, we engineered our PostgreSQL disaster recovery pipeline. Instead of running high-risk restores over production tables, our automation provisions a fresh, isolated database in `forgeops-dr-lab`, executes `pg_restore` with strict error handling, and validates relational integrity and BCrypt authentication.
  > In our verified rehearsal, database restore took 252 milliseconds, achieving full end-to-end API recovery in 89 seconds."
- **Terminal Execution:**
  ```bash
  python3 scripts/test_g13_dr_hardening.py
  ```
- **Key Visual:** All DR verification assertions pass; zero impact on the protected production database.

---

### Phase 5: Handoff & Evidence-Driven Engineering (3:45 - 4:30)
- **Speaker Narration:**
  > "Every claim made in this project is backed by tangible, timestamped execution evidence under `docs/evidence/`. Our Requirements Traceability Matrix traces every single SRS requirement from G00 through G15, accompanied by detailed runbooks and transparent documentation of lab boundaries like Kind single-node persistence.
  > Thank you for reviewing ForgeOps!"
- **Key Visual:** Display `docs/audit/REQUIREMENTS_TRACEABILITY_MATRIX.md` in browser/IDE.

---

## 4. Media & Artifact Capture Checklist

When recording or preparing presentation media for this project, capture the following genuine artifacts:

- [ ] **Artifact 1 (Screenshot):** GitHub Actions CI matrix showing all 7 jobs green (Build, Test, Security, Lint, Helm, Kyverno, SOPS).
- [ ] **Artifact 2 (Screenshot):** Argo CD dashboard showing `forgeops-dev` and `forgeops-gitops-rehearsal` healthy and synchronized.
- [ ] **Artifact 3 (Screenshot):** Grafana Dashboard displaying Prometheus HTTP request rate, p95 latency, and CPU metrics during k6 load.
- [ ] **Artifact 4 (Screenshot):** Tempo trace view showing span breakdown linked to Loki logs via Trace-to-Logs.
- [ ] **Artifact 5 (Screenshot):** Terminal output of `rehearse-dr.sh` showing SHA-256 backup verification, 252 ms restore, and zero PVC impact.
- [ ] **Artifact 6 (Video - Optional):** 3-minute screen recording following the narration steps above.
