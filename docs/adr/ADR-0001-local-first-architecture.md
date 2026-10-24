# ADR-0001: Local-First Zero-Cloud Architecture

**Status:** Accepted  
**Date:** 2026-10-22  
**Deciders:** ForgeOps Architecture Review

---

## Context
Engineering portfolio projects often depend on paid public cloud providers (AWS, Azure, GCP), incurring ongoing subscription fees, exposure to unexpected billing spikes, and brittle remote credentials. Furthermore, recruiters and interviewers frequently cannot independently verify or reproduce cloud-hosted infrastructures.

ForgeOps requires a fully verifiable DevOps, Platform Engineering, and SRE portfolio environment that runs locally on commodity developer hardware without requiring cloud credits, credit cards, or proprietary subscriptions.

## Options Considered
1. **Public Cloud Free Tiers (AWS/GCP/Azure):** Provides native cloud services (EKS, RDS, IAM) but introduces billing risk, credit card requirements, free-tier expiration limits, and fragile external dependencies.
2. **Paid VPS/Hetzner Infrastructure:** Requires ongoing monetary spend (~$20–$50/month) and ongoing public network security hardening.
3. **Local-First Containerized & Virtualized Lab:** Runs on Windows 11 / WSL2 using Docker Engine, Kind (Kubernetes in Docker), local Terraform providers, and a localized Linux VM for Ansible.

## Decision
Adopt a **Local-First Architecture** with **Zero Mandatory Paid Cloud Dependency**.
- All compute, networking, persistence, and control planes will execute locally on the developer machine (Windows 11 with WSL2).
- Free public SaaS utilities (GitHub Actions standard runners, GitHub Container Registry for public packages) are used exclusively for supply chain automation and immutable image storage, with a fully offline local fallback path (`make ci` and `kind load docker-image`).
- No credit card or paid cloud account will ever be required to run or review ForgeOps.

## Consequences & Trade-offs
### Positive:
- **Zero Cost Risk:** No unexpected billing or recurring cloud subscriptions.
- **Full Reproducibility:** Any reviewer can clone the repository and run the core stack locally.
- **Fast Feedback Loop:** Local development and testing does not incur cloud provisioning latencies.

### Negative / Limitations:
- **Host Resource Constraints:** Physical memory (16 GB) and storage space (6.62 GB free SSD) restrict concurrent execution; workloads must be staged sequentially.
- **Single Fault Domain:** The local laptop is a single failure domain; no multi-region or true multi-datacenter high availability can be claimed.
- **Loopback Networking:** Services cannot be accessed across the public Internet; all UI access is bound to `127.0.0.1`.

## Verification Tests
- `make doctor` executes successfully without cloud API credentials.
- `docker compose` and `kind` clusters initialize and operate entirely within the local host networking space.
- Absence of cloud provider credentials (e.g., `AWS_ACCESS_KEY_ID`, `GOOGLE_APPLICATION_CREDENTIALS`) verified in all automation scripts.

## Reconsideration Triggers
- If project scope is formally extended to include cloud hybrid networking or multi-cloud IAM benchmarking under an employer-funded sandbox.
