# End-to-End Data & Promotion Flows — ForgeOps

**Document Version:** 1.0  
**Effective Date:** 2026-10-22  
**Baseline Gate:** G00 Architecture Review

---

## 1. Continuous Delivery & GitOps Promotion Flow

The software delivery lifecycle follows an immutable, pull-based GitOps pipeline. No hosted runner ever reaches into the local laptop.

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Developer
    participant Git as GitHub Repository
    participant GHA as GitHub Actions
    participant GHCR as GitHub Container Registry
    participant Argo as Argo CD (Local Kind)
    participant K8s as forgeops-dev Namespace

    Dev->>Git: Push feature branch & open PR
    Git->>GHA: Trigger pr-checks.yml (read-only token)
    Note over GHA: Run lint, unit/integration tests,<br/>Gitleaks, Trivy scan, dry Docker build
    GHA-->>Git: Report PR check status (Green)
    
    Dev->>Git: Review & merge PR to main
    Git->>GHA: Trigger release.yml (packages:write)
    Note over GHA: Multi-stage Docker build, generate SBOM,<br/>scan image with Trivy
    GHA->>GHCR: Publish tagged image (git-SHA)
    GHCR-->>GHA: Return immutable sha256:... digest
    GHA->>Git: Auto-create promotion PR updating values-dev.yaml
    
    Dev->>Git: Review & merge promotion PR to main
    Note over Argo: Outbound poll (every 3m or refresh)
    Argo->>Git: Fetch desired state commit
    Argo->>GHCR: Pull image by sha256:... digest
    Argo->>K8s: Apply updated Deployment manifest
    Note over K8s: Rolling update: start new pod, check readiness,<br/>terminate old pod
    K8s-->>Argo: Workload Synced & Healthy
```

---

## 2. Observability & Telemetry Signal Flow

Observability signals are segregated into metrics, alerts, and structured logs, correlated by common dimensional labels and request IDs.

```mermaid
flowchart LR
    subgraph Workload ["App Workload (forgeops-dev)"]
        API["ForgeTasks API Pod"]
        AppLog["stdout / JSON formatted"]
        Actuator["/actuator/prometheus"]
    end

    subgraph ObservabilityStack ["Observability Namespace"]
        Prom["Prometheus Server"]
        Alerts["Alertmanager"]
        Alloy["Grafana Alloy (DaemonSet)"]
        Loki["Grafana Loki"]
        Grafana["Grafana Server"]
    end

    subgraph Operator ["Developer / SRE"]
        Browser["Grafana UI (127.0.0.1:3000)"]
        LocalAlert["Local Alert Receiver"]
    end

    %% Metrics flow
    Prom -->|"Scrape interval (15s)"| Actuator
    Prom -->|"Evaluate rules (HighErrorRate, Latency)"| Alerts
    Alerts -->|"Fire notification webhook"| LocalAlert

    %% Log flow
    AppLog -->|"Read /var/log/pods"| Alloy
    Alloy -->|"Process, parse JSON, filter"| Alloy
    Alloy -->|"Batch push HTTP /api/v1/push"| Loki

    %% Correlation
    Grafana -->|"PromQL query"| Prom
    Grafana -->|"LogQL query with requestId"| Loki
    Browser -->|"Inspect dashboards & traces"| Grafana
```

### Telemetry Correlation Contract:
1. Every incoming HTTP request is assigned a unique `requestId` (UUID) via an HTTP filter.
2. The `requestId` is injected into the SLF4J MDC (Mapped Diagnostic Context) and appended to all structured JSON application log lines.
3. Errors returned to the client (RFC 7807) include the exact same `requestId`.
4. An operator triaging a 5xx spike in Grafana can copy the `requestId` from the HTTP response and immediately retrieve the matching stack trace from Loki via LogQL:
   ```logql
   {namespace="forgeops-dev", app="forgetasks"} |= "550e8400-e29b-41d4-a716-446655440000"
   ```

---

## 3. Database Migration & Lifecycle Flow

PostgreSQL schema state evolves strictly through Flyway relational migrations executed during application startup.

```mermaid
sequenceDiagram
    autonumber
    participant K8s as Kubernetes Kubelet
    participant API as ForgeTasks Container
    participant Flyway as Embedded Flyway Engine
    participant DB as PostgreSQL Database

    K8s->>API: Start container (SIGTERM handler registered)
    API->>DB: Open HikariCP connection pool (using injected Secret)
    Note over API: Run Flyway migration check
    API->>Flyway: Validate schema history table (flyway_schema_history)
    Flyway->>DB: Check pending V*__*.sql migration scripts
    alt Pending Migrations Exist
        Flyway->>DB: Execute DDL transactions (Expand/Contract schema)
        Flyway->>DB: Record migration checksum, author, timestamp
    end
    API->>API: Initialize Spring ApplicationContext
    Note over API: Expose /actuator/health
    K8s->>API: Probe /actuator/health/readiness
    API->>DB: SELECT 1 (Database connectivity check)
    DB-->>API: Healthy (200 OK)
    API-->>K8s: Ready (Route traffic to pod)
```

---

## 4. Disaster Recovery & Backup Flow

Host-side database backups protect state against accidental Kind cluster destruction.

```mermaid
sequenceDiagram
    autonumber
    actor Operator as Operator / Cron
    participant Make as Makefile / Host Script
    participant KindDB as Running PostgreSQL (Kind Pod)
    participant HostFS as Host Filesystem (~/.config/forgeops/backups/)
    participant ScratchDB as Temporary Scratch DB Container

    Note over Operator: Routine Backup or Pre-Reset Drill
    Operator->>Make: make backup-db
    Make->>HostFS: Verify available disk space >= 1 GB
    Make->>KindDB: pg_dump --format=custom (via kubectl exec)
    KindDB-->>Make: Binary stream
    Make->>HostFS: Write forgeops_db_YYYYMMDD_HHMMSS.dump.gz
    Make->>HostFS: Compute & write SHA256 checksum file
    Make-->>Operator: Backup created successfully

    Note over Operator: Backup Verification (Drill DR-07)
    Operator->>Make: make verify-backup
    Make->>HostFS: Read latest dump & verify SHA256 integrity
    Make->>ScratchDB: Spin up disposable PostgreSQL container
    Make->>ScratchDB: pg_restore dump into scratch database
    Make->>ScratchDB: Run integrity queries (COUNT accounts, projects, tasks)
    ScratchDB-->>Make: Verification queries match expected schemas
    Make->>ScratchDB: Destroy temporary scratch container
    Make-->>Operator: Backup verification PASSED
```
