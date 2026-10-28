# ForgeOps Visual Architecture & System Flow Diagrams

This document contains GitHub-compatible Mermaid diagrams illustrating the architectural components, delivery pipelines, observability telemetry, disaster recovery flows, and security boundaries across the ForgeOps platform.

---

## 1. End-to-End ForgeOps Platform Architecture

```mermaid
flowchart TD
    subgraph Host["Developer Workstation (Linux / WSL2)"]
        subgraph DevLayer["Local Development & Test"]
            AppSrc["Spring Boot 4 / Java 21 LTS Source"]
            Compose["Docker Compose Stack (127.0.0.1:18080)"]
            LocalDB[("PostgreSQL 16 (Local)")]
            AppSrc -->|Build & Test| Compose
            Compose -->|Read / Write| LocalDB
        end

        subgraph KindCluster["Kind Kubernetes Cluster (kind-forgeops)"]
            subgraph NS_Dev["Namespace: forgeops-dev"]
                DevAPI["ForgeTasks API (Vanilla Manifests)"]
                DevPG[("PostgreSQL 16 StatefulSet")]
                DevAPI --> DevPG
            end

            subgraph NS_Rehearsal["Namespace: forgeops-gitops-rehearsal"]
                RehAPI["ForgeTasks API (Helm / Argo CD)"]
                RehPG[("PostgreSQL 16 StatefulSet")]
                RehAPI --> RehPG
            end

            subgraph NS_GitOps["Namespace: argocd"]
                ArgoCD["Argo CD Controller & Server (127.0.0.1:18081)"]
            end

            subgraph NS_Obs["Namespace: forgeops-observability"]
                Prom["Prometheus (Metrics Scraper)"]
                Graf["Grafana Dashboards (127.0.0.1:13000)"]
                AM["Alertmanager (Alert Dispatcher)"]
                Loki["Grafana Loki (Log Chunks)"]
                Alloy["Grafana Alloy (DaemonSet Log Agent)"]
                Tempo["Grafana Tempo (Trace Ingestion)"]

                Prom --> Graf
                Loki --> Graf
                Tempo --> Graf
                Prom --> AM
                Alloy -->|Streams Logs| Loki
            end
        end

        subgraph LocalInfra["Standalone Local Infrastructure"]
            Ansible["Ansible Engine (Controls Ubuntu Guest over SSH)"]
            Terraform["Terraform (Local Docker Lab Fixtures)"]
        end
    end

    subgraph GitHub["GitHub Cloud Infrastructure"]
        GHA["GitHub Actions CI Pipeline"]
        GHCR["GitHub Container Registry (GHCR)"]
        Repo["Git Repository (TM-threemavithana/ForgeOps)"]
    end

    AppSrc -->|git push| Repo
    Repo -->|triggers| GHA
    GHA -->|publishes signed image| GHCR
    GHCR -->|pulls immutable digest| RehAPI
    Repo -->|Argo CD syncs manifests| ArgoCD
    ArgoCD -->|manages| RehAPI

    RehAPI -.->|OTLP Traces| Tempo
    RehAPI -.->|Actuator Metrics| Prom
    RehAPI -.->|Stdout ECS Logs| Alloy
```

---

## 2. GitHub Actions to GHCR to Argo CD Delivery Pipeline

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Platform Engineer
    participant Git as GitHub Repository
    participant CI as GitHub Actions CI (ci.yml)
    participant Pub as GHCR Publish (publish.yml)
    participant GHCR as GitHub Container Registry
    participant Argo as Argo CD Controller
    participant K8s as Kind Cluster (Rehearsal)

    Dev->>Git: git push feature branch
    Git->>CI: Trigger CI Workflow
    activate CI
    CI->>CI: Maven Build & JaCoCo Coverage Gate
    CI->>CI: Docker Multi-Stage Build & Non-Root Check
    CI->>CI: Trivy Vulnerability Scan (Zero CRITICAL/HIGH)
    CI->>CI: Gitleaks Secret Scan (Entire Git History)
    CI->>CI: SRE & DR Hardening Regression Tests
    CI->>CI: Kyverno CLI Policy-as-Code Tests (10 Policies)
    CI->>CI: SOPS / age Encrypted Secrets Validation
    CI-->>Git: All 7 CI Gate Jobs Passed
    deactivate CI

    Dev->>Git: Merge PR to master
    Dev->>Pub: Trigger manual workflow_dispatch with Git SHA
    activate Pub
    Pub->>Pub: Verify trigger ref is master HEAD
    Pub->>Pub: Verify commit ancestry and passing CI gate
    Pub->>Pub: Build candidate image & verify locally with Trivy
    Pub->>GHCR: Push immutable image tag & SHA-256 digest
    Pub->>GHCR: Generate CycloneDX SBOM & SLSA v2 Provenance Attestation
    Pub-->>Dev: Output authoritative image manifest digest
    deactivate Pub

    Dev->>Git: Update values-rehearsal.yaml with new @sha256 digest
    Dev->>Argo: Trigger manual sync in Argo CD UI
    activate Argo
    Argo->>Git: Fetch latest values-rehearsal.yaml
    Argo->>K8s: Execute RollingUpdate (maxSurge=1, maxUnavailable=0)
    activate K8s
    K8s->>GHCR: Pull image by exact SHA-256 digest
    K8s->>K8s: Start new Pod & await readiness probe pass
    K8s->>K8s: Terminate old Pod cleanly
    K8s-->>Argo: Deployment in Sync & Healthy
    deactivate K8s
    deactivate Argo
```

---

## 3. Kubernetes Workload and Namespace Ownership

```mermaid
flowchart LR
    subgraph Cluster["kind-forgeops Cluster"]
        subgraph Dev["forgeops-dev Namespace"]
            D1["Deployment: forgetasks-dev-api"]
            D2[("StatefulSet: forgetasks-dev-db")]
            D3["PVC: postgres-storage-...-0 (UID: 84853fb3...)"]
            D2 --- D3
            D1 -->|Internal JDBC| D2
        end

        subgraph Rehearsal["forgeops-gitops-rehearsal Namespace"]
            R1["Deployment: forgetasks-rehearsal-api"]
            R2[("StatefulSet: forgetasks-rehearsal-db")]
            R3["PVC: postgres-storage-...-0 (UID: b5ea8ec9...)"]
            R2 --- R3
            R1 -->|Internal JDBC| R2
        end

        subgraph GitOps["argocd Namespace"]
            A1["Argo CD Server (127.0.0.1:18081)"]
            A2["Argo CD Application Controller"]
            A2 -->|Owns Workloads| R1
            A2 -->|Owns Workloads| R2
        end

        subgraph Obs["forgeops-observability Namespace"]
            O1["Prometheus (UID: cd64e090...)"]
            O2["Grafana (127.0.0.1:13000)"]
            O3["Loki (UID: 23468366...)"]
            O4["Tempo (UID: 092b6655...)"]
            O5["Grafana Alloy (DaemonSet)"]
        end
    end
```

---

## 4. Prometheus & Grafana Monitoring Flow

```mermaid
flowchart TD
    subgraph Targets["Monitored Workloads"]
        API["ForgeTasks API (/actuator/prometheus)"]
        DB["PostgreSQL 16"]
        Node["Kind Node Metrics"]
    end

    subgraph PrometheusServer["Prometheus Instance"]
        Scraper["Prometheus Scraping Engine (15s interval)"]
        TSDB[("Prometheus TSDB (15-day local retention)")]
        Rules["Alerting & Recording Rules Engine"]

        Scraper -->|Pull Metrics| Targets
        Scraper --> TSDB
        TSDB --> Rules
    end

    subgraph Alerting["Alertmanager"]
        AM["Alertmanager Daemon (Port 9093)"]
        Webhook["Local Webhook / Notification Receiver"]
        Rules -->|Dispatches Firing Alerts| AM
        AM --> Webhook
    end

    subgraph Visualization["Grafana Server (Port 3000)"]
        DashJVM["Dashboard: ForgeTasks JVM & HTTP Metrics"]
        DashK8s["Dashboard: Kubernetes Cluster & Node Resources"]
        TSDB -->|PromQL Queries| DashJVM
        TSDB -->|PromQL Queries| DashK8s
    end
```

---

## 5. Grafana Alloy, Loki, and Tempo Unified Telemetry Flow

```mermaid
flowchart LR
    subgraph Workload["ForgeTasks Spring Boot Application"]
        App["REST Request Handler"]
        MDC["SLF4J MDC Logging (X-Request-ID)"]
        OTel["OpenTelemetry Java Agent (W3C traceparent)"]

        App -->|Injects Request-ID| MDC
        App -->|Auto-instruments| OTel
    end

    subgraph TelemetryPipelines["Telemetry Collectors"]
        Alloy["Grafana Alloy DaemonSet Agent"]
        MDC -->|Stdout ECS JSON| Alloy

        TempoEngine["Grafana Tempo Engine (Port 4317 OTLP)"]
        OTel -->|gRPC OTLP Traces| TempoEngine
    end

    subgraph Storage["Storage Backends"]
        LokiChunks[("Loki Chunks (Local Path PVC)")]
        TempoBlocks[("Tempo Trace Blocks (Local Path PVC)")]

        Alloy -->|Push LogQL Streams| LokiChunks
        TempoEngine --> TempoBlocks
    end

    subgraph GrafanaExplore["Grafana Explore UI"]
        UI["Unified Correlation View"]
        LokiChunks -->|LogQL by Request-ID| UI
        TempoBlocks -->|TraceID Lookup| UI
        UI -.->|tracesToLogsV2 Navigation Bridge| UI
    end
```

---

## 6. G13 PostgreSQL Backup & Disposable Lab Recovery Flow

```mermaid
sequenceDiagram
    autonumber
    participant Op as Disaster Recovery Automation
    participant Source as Source DB (forgeops-dr-lab)
    participant Storage as Local Backup Archive
    participant Target as Fresh Disposable Target DB
    participant API as Rehearsal ForgeTasks API

    Note over Op,Source: Step 1: Baseline & Preflight Safety Checks
    Op->>Op: Assert all 5 permanent PVCs are Bound & protected
    Op->>Source: Execute Flyway migrations & seed synthetic accounts/tasks

    Note over Op,Storage: Step 2: Custom Format Backup Creation
    Op->>Source: pg_dump -Fc (Custom Format Archive)
    Source-->>Storage: Output dump file (measured: 273 ms)
    Op->>Storage: Compute SHA-256 integrity checksum

    Note over Op,Target: Step 3: Strict Target Isolation & Freshness Guard
    Op->>Target: Verify target pod UID != source pod UID
    Op->>Target: Verify target database is 100% empty (ON_ERROR_STOP=1)

    Note over Op,Target: Step 4: Atomic Restoration
    Op->>Target: pg_restore --exit-on-error (measured: 252 ms)
    Target-->>Op: Exit Code 0 (All database objects restored)

    Note over Op,API: Step 5: Service Recovery & Authenticated Smoke Test
    Op->>API: Roll out ForgeTasks API attached to restored DB
    API->>API: Await readiness probe HTTP 200 (measured total RTO: 89.29s)
    Op->>API: Test positive authentication (BCrypt synthetic password)
    Op->>API: Test resource retrieval (Project and Task counts match)
    Op->>API: Test 401 guard on invalid credentials

    Note over Op,Source: Step 6: Clean Teardown & Invariant Verification
    Op->>Op: Delete disposable namespace forgeops-dr-lab
    Op->>Op: Re-audit all 5 permanent PVCs (100% identical baseline UIDs)
```

---

## 7. G14 Kyverno Policy-as-Code & SOPS Encrypted Secret Lifecycle

```mermaid
flowchart TD
    subgraph DevOpsWorkstation["Developer Workstation / CI Runner"]
        subgraph SecretsFlow["Mozilla SOPS + age Workflow"]
            PlainSecret["Cleartext Manifest Source"]
            AgeKeys["age Public Recipients: Primary + Escrow"]
            SOPSConfig[".sops.yaml (encrypted_regex: '^(data|stringData)$')"]
            EncSecret["Encrypted Manifest: synthetic-secrets.enc.yaml"]

            PlainSecret -->|sops --encrypt| EncSecret
            AgeKeys -->|Public Key Encryption| EncSecret
            SOPSConfig -->|Restricts to Payload Data| EncSecret
        end

        subgraph PolicyFlow["Kyverno Policy-as-Code Workflow"]
            Manifests["Kubernetes Workload Manifests"]
            Policies["10 Kyverno ClusterPolicies (security/policies/kyverno/)"]
            CLI["Kyverno CLI v1.19.2 (Pinned with SHA-256 Checksum)"]
            Results["Validation Report (20 Positive/Negative Test Cases)"]

            Manifests --> CLI
            Policies --> CLI
            CLI --> Results
        end
    end

    subgraph GitRepo["Version Control (Git / GitHub)"]
        GitCommit["Committed to Git (Zero Plaintext Secrets / Zero Private Keys)"]
        EncSecret --> GitCommit
        Policies --> GitCommit
    end

    subgraph Decryption["Decryption Operations"]
        PrivPrimary["Primary Operational Key (~/.forgeops/keys/)"]
        PrivEscrow["Offline Air-Gapped Escrow Key (Cold Storage Vault)"]

        GitCommit -->|Authorized CI / Deploy| PrivPrimary
        PrivPrimary -->|Decrypts stringData| K8sSecret["In-Memory Kubernetes Secret"]

        GitCommit -->|Emergency DR Recovery| PrivEscrow
        PrivEscrow -->|Independent Decryption| K8sSecret
    end
```
