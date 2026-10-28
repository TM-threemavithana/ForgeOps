# ForgeOps Reproducibility Audit & Reviewer Walkthrough (Gate G15)

| Metadata | Details |
|:---|:---|
| **Author** | Principal Platform Engineer & Technical Reviewer |
| **Project** | ForgeOps — Self-Hosted DevOps & Platform Engineering Lab |
| **Target Audience** | External Reviewers, Technical Evaluators, and Prospective Employers |
| **Prerequisites** | Linux or Windows 11 with WSL2, Docker Desktop/Engine, zero paid cloud accounts |
| **Status** | **VERIFIED REPRODUCIBLE** |

---

## 1. System Requirements & Execution Profiles

To prevent workstation resource exhaustion, ForgeOps is architected around three flexible execution profiles:

| Profile | Target Specifications | Concurrently Active Services | Use Cases |
|:---|:---|:---|:---|
| **Core** | 8 GB RAM, $\ge$ 40 GB SSD | Spring Boot API + PostgreSQL via Docker Compose, Local CI | Fast application iteration, database schema development |
| **Extended** | 16 GB RAM, $\ge$ 60 GB SSD | Single-node Kind cluster, ForgeTasks Helm app, Argo CD, Prometheus | GitOps workflows, metric monitoring, standard deployments |
| **Capstone** | 24–32 GB RAM, $\ge$ 80 GB SSD | Kind cluster + full observability (Prometheus, Loki, Alloy, Tempo) | Full-stack telemetry correlation, SRE load testing, DR drills |

---

## 2. Pinned Tooling & Verification Matrix

All developer and CI tools must meet the following minimum versions:

| Tool | Minimum Version | Pinned CI Version | Purpose |
|:---|:---|:---|:---|
| **Java / JDK** | `21 LTS` (OpenJDK) | `21` (Eclipse Temurin) | ForgeTasks Spring Boot backend |
| **Docker Engine** | `24.0.0+` | `27.x` | Multi-stage image builds, local container runtime |
| **Docker Compose** | `v2.20.0+` | `v2.x` | Local developer environment orchestration |
| **Kind** | `v0.25.0+` | `v0.27.0` | Local single-node Kubernetes cluster lifecycle |
| **kubectl** | `v1.30.0+` | `v1.32.2` | Kubernetes cluster control plane CLI |
| **Helm** | `v3.14.0+` | `v3.17.1` | Application packaging and parameterization |
| **k6** | `v0.49.0+` | `v0.56.0` | SRE arrival-rate load and latency testing |
| **Kyverno CLI** | `v1.19.0+` | `v1.19.2` | Pre-deployment Policy-as-Code manifest validation |
| **Mozilla SOPS** | `v3.9.0+` | `v3.13.3` | GitOps secret envelope encryption |
| **age / age-keygen** | `v1.2.0+` | `v1.2.1` | Asymmetric X25519 cryptography for SOPS |

---

## 3. Step-by-Step Reviewer Walkthrough (Zero Private Credentials Required)

A technical reviewer or prospective employer can reproduce and verify ForgeOps from scratch without needing access to private author credentials or paid cloud accounts.

### Step 1: Preflight Verification
Clone the repository and inspect host prerequisites:
```bash
git clone https://github.com/TM-threemavithana/ForgeOps.git
cd ForgeOps
make doctor
```
*Expected Outcome:* `make doctor` verifies kernel version, virtualization support, Docker access, and tool availability.

### Step 2: Local Application & Database Stack (Docker Compose)
Launch the containerized application stack:
```bash
# Initialize local development secrets from template
cp .env.example .env

# Build and start services in loopback-isolated mode
docker compose up -d --build

# Verify healthy startup
docker compose ps
curl -i http://127.0.0.1:18080/actuator/health/readiness
```
*Expected Outcome:* Returns `HTTP 200 OK` with `{"status":"UP"}` confirming Flyway database migrations executed cleanly.

### Step 3: Run Full CI Hardening & Security Test Suites Locally
Execute the automated regression suites without pushing to GitHub:
```bash
# 1. Execute Kyverno Policy-as-Code static assertions (10 policies, 20 fixtures, Helm audit)
python3 scripts/test_g14_security.py

# 2. Execute SOPS + age cryptographic lifecycle validation (AES-256-GCM, MAC tamper test)
python3 scripts/test_g14_sops.py

# 3. Execute SRE and Disaster Recovery hardening tests
python3 scripts/test_g12_hardening.py
python3 scripts/test_g13_dr_hardening.py
```
*Expected Outcome:* All 4 test suites pass 100% of assertions with zero errors.

### Step 4: Kind Kubernetes Cluster Inspection (Read-Only)
If inspecting an already-provisioned `kind-forgeops` cluster:
```bash
export KUBECONFIG=~/.kube/config-forgeops

# 1. Inspect namespace isolation
kubectl get namespaces

# 2. Inspect permanent storage continuity (5 baseline PVCs)
kubectl get pvc -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase'

# 3. Inspect GitOps rehearsal deployment
kubectl get pods -n forgeops-gitops-rehearsal -o wide

# 4. Inspect observability workloads
kubectl get pods -n forgeops-observability
```
*Expected Outcome:* All pods in `forgeops-gitops-rehearsal` and `forgeops-observability` report `Running` status with zero crash loops.

### Step 5: Observability Dashboards & Telemetry Correlation
Forward ports to access local observability UIs:
```bash
# Access Grafana (Credentials managed via cluster secrets)
kubectl port-forward svc/g09-monitoring-grafana -n forgeops-observability 13000:80 &

# Access Argo CD Web UI
kubectl port-forward svc/argocd-server -n argocd 18081:443 &
```
1. Open `http://127.0.0.1:13000` in a browser.
2. Navigate to **Dashboards -> ForgeTasks JVM & HTTP Metrics** to view live CPU, JVM heap, HikariCP pool usage, and HTTP request rates.
3. Navigate to **Explore -> Loki**: Query `{namespace="forgeops-gitops-rehearsal"}` to view ECS JSON formatted logs.
4. Navigate to **Explore -> Tempo**: Query traces and click **Query with LogQL** to witness the `tracesToLogsV2` navigation bridge.

---

## 4. Disaster Recovery & SRE Reproducibility Runbooks

Detailed operational runbooks are located in `docs/runbooks/`:
- **Disaster Recovery:** [`docs/runbooks/POSTGRESQL_DISASTER_RECOVERY_RUNBOOK.md`](../runbooks/POSTGRESQL_DISASTER_RECOVERY_RUNBOOK.md)
- **Cluster Rebuild:** [`docs/runbooks/KIND_CLUSTER_REBUILD_RUNBOOK.md`](../runbooks/KIND_CLUSTER_REBUILD_RUNBOOK.md)
- **Incident Response Master:** [`docs/runbooks/INCIDENT_RESPONSE_MASTER_RUNBOOK.md`](../runbooks/INCIDENT_RESPONSE_MASTER_RUNBOOK.md)
- **SOPS Secret Lifecycle:** [`docs/runbooks/SOPS_AGE_SECRET_MANAGEMENT_RUNBOOK.md`](../runbooks/SOPS_AGE_SECRET_MANAGEMENT_RUNBOOK.md)

---

## 5. Audit Conclusion

The ForgeOps repository is **100% reproducible on commodity developer hardware** without requiring proprietary credentials, external cloud subscriptions, or undisclosed dependencies.

