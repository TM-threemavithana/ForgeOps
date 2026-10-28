# Start Here — ForgeOps Navigation & Reviewer Guide

Welcome to **ForgeOps**, a production-inspired, self-hosted DevOps, DevSecOps, and Platform Engineering demonstration platform.

This repository contains the **complete, implemented, and audited source code, infrastructure, and operational documentation** for all milestones from Gate G00 through Gate G15.

---

## 1. Fast-Track Navigation for Reviewers

Depending on your role or objective, start with the corresponding entry point:

| If you are a... | Recommended Starting Point | Key Artifacts |
|:---|:---|:---|
| **Technical Recruiter / Hiring Manager** | **[README.md](README.md)** | [Project Overview](docs/portfolio/PROJECT_OVERVIEW.md), [Resume Bullets](docs/portfolio/RESUME_BULLETS.md), [Demo Script](docs/portfolio/DEMO_SCRIPT.md) |
| **DevOps / Platform Engineering Interviewer**| **[Architecture Walkthrough](docs/portfolio/ARCHITECTURE_WALKTHROUGH.md)** | [22 Technical Interview Q&As](docs/portfolio/INTERVIEW_QA.md), [Architecture Diagrams](docs/architecture/ARCHITECTURE_DIAGRAMS.md) |
| **Security / DevSecOps Auditor** | **[Final Security & Operational Review](docs/audit/FINAL_SECURITY_AND_OPERATIONAL_REVIEW.md)**| [Kyverno Policies & SOPS Audit](docs/evidence/G14/G14-acceptance-report.md), [Known Limitations](docs/portfolio/KNOWN_LIMITATIONS.md) |
| **SRE / Disaster Recovery Engineer** | **[PostgreSQL DR Runbook](docs/runbooks/POSTGRESQL_DISASTER_RECOVERY_RUNBOOK.md)** | [Gate G12 SRE Evidence](docs/evidence/G12/G12-acceptance-report.md), [Gate G13 DR Evidence](docs/evidence/G13/G13-acceptance-report.md) |
| **Developer / Contributor** | **[Reproducibility Audit](docs/audit/REPRODUCIBILITY_AUDIT.md)** | [Requirements Traceability Matrix](docs/audit/REQUIREMENTS_TRACEABILITY_MATRIX.md), [Master Plan](docs/FORGEOPS_MASTER_IMPLEMENTATION_PLAN.md) |

---

## 2. Core Architectural Invariants

Throughout all 15 implementation gates, the platform strictly maintained the following hard boundaries:
1. **Zero Paid Cloud Dependencies:** Runs 100% on local infrastructure (Linux / WSL2, Docker, Kind) with zero cloud vendor bills.
2. **Single Owner per Resource:** Distinct lifecycle separation between Kind (cluster), Terraform (fixtures), Ansible (Linux host), and Argo CD (workloads).
3. **Zero Secret Leaks:** No private keys, database dumps, or unencrypted secrets are committed to Git.
4. **Zero Production Data Loss:** All 5 baseline PersistentVolumeClaims (PostgreSQL dev, rehearsal DB, Prometheus, Loki, Tempo) remained 100% intact with zero UID churn across all chaos experiments and DR drills.

---

## 3. Quick Local Verification

To run the local automated regression and verification suite:

```bash
# 1. Verify Kyverno Policy-as-Code test suites
python3 scripts/test_g14_security.py

# 2. Verify SOPS + age dual-recipient encryption
python3 scripts/test_g14_sops.py

# 3. Verify PostgreSQL disaster recovery logic
python3 scripts/test_g13_dr_hardening.py

# 4. Verify SRE load-test and port-forward boundaries
python3 scripts/test_g12_hardening.py
```

For complete instructions on running the application locally via Docker Compose or Kubernetes, refer to [README.md](README.md#9-getting-started-with-docker-compose-inner-loop).
