# ForgeTasks Reusable Helm Chart

This directory contains the official Kubernetes Helm chart for **ForgeTasks**, packaging the Spring Boot REST API and dedicated PostgreSQL 16 database.

## Architecture & Workload Layout

The chart packages two core workloads matching the verified Gate G06 runtime architecture:

1. **ForgeTasks API (`apps/v1:Deployment`):**
   - Java 21 / Spring Boot 4.x REST API.
   - Non-root runtime identity (`runAsUser: 10001`, `runAsGroup: 10001`, `fsGroup: 10001`).
   - High-reliability probe architecture: `startupProbe` (60s total cold-start budget), `readinessProbe` (3s period), `livenessProbe` (10s period).
   - CPU and memory bounds (`requests: 200m/256Mi`, `limits: 1000m/512Mi`).
   - ClusterIP Service routing internal traffic on port 8080.
   - Dedicated ServiceAccount with disabled API token automount (`automountServiceAccountToken: false`).

2. **PostgreSQL Database (`apps/v1:StatefulSet`):**
   - PostgreSQL 16 Alpine single-replica database.
   - Non-root runtime identity (`runAsUser: 70`, `runAsGroup: 70`, `fsGroup: 70`).
   - Subpath data directory (`PGDATA=/var/lib/postgresql/data/pgdata`).
   - Stateful persistent storage via `volumeClaimTemplates` (1Gi ReadWriteOnce, binding to default `standard` StorageClass).
   - Strict retention policy: `persistentVolumeClaimRetentionPolicy.whenDeleted: Retain` and `whenScaled: Retain`.
   - Headless governing Service (`clusterIP: None`) for network identity and ClusterIP Service for application queries.

## Secret Management (ADR-0006)

In compliance with **Rule 5** (No Secret Leaks) and **ADR-0006**:
- **Zero Plaintext Secrets:** Passwords are never committed to Git, stored in Helm values files, or embedded in Helm release objects.
- **External Secret Decoupling:** The chart references an existing Kubernetes Secret (`forgetasks-db-secret`) via `postgresql.auth.existingSecretName`.
- **Out-of-Band Provisioning:** Secrets are provisioned prior to deployment using dedicated out-of-band scripts:

  **Sandbox Deployment (`forgeops-helm-sandbox`):**
  ```bash
  # Step 1: Validate credential source without cluster mutations
  ./scripts/cluster/inject-sandbox-secrets.sh --validate-only

  # Step 2: Inject secret atomically into forgeops-helm-sandbox (atomic create-only)
  ./scripts/cluster/inject-sandbox-secrets.sh --confirm
  ```
  > [!IMPORTANT]
  > The `--confirm` flag performs an atomic create-only operation. It will fail if `forgetasks-db-secret` already exists and must **not** be rerun against an existing Secret.
  > This check is enforced by the provisioning script at the orchestration layer and does not configure the Kubernetes API-level `immutable: true` field.

  **Development Baseline (`forgeops-dev`):**
  ```bash
  ./scripts/cluster/inject-secrets.sh --namespace forgeops-dev
  ```

  **Staging Environment (`forgeops-staging`):**
  Staging credentials must be provisioned via the dedicated Gate G08 staging secrets pipeline. Do **not** inject local development (G06) or sandbox credentials into staging.

## Parameters Reference

| Parameter | Description | Default |
|---|---|---|
| `environment` | Deployment tier label (`dev` or `staging`) | `dev` |
| `nameOverride` | Override chart base name | `""` |
| `fullnameOverride` | Override fully-qualified release name | `""` |
| `api.replicaCount` | Desired replicas for API Deployment | `1` |
| `api.image.repository` | API container image repository | `forgetasks-api` |
| `api.image.tag` | API container image tag | `1.0.0` |
| `api.image.digest` | Immutable OCI image digest (`sha256:...`) | `""` |
| `api.image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `api.configMapAnnotations` | Annotations attached to API ConfigMap metadata | `{}` |
| `api.service.type` | Kubernetes Service type | `ClusterIP` |
| `api.service.port` | Internal TCP listening port | `8080` |
| `api.resources.requests.cpu` | Minimum requested CPU | `200m` |
| `api.resources.requests.memory` | Minimum requested memory | `256Mi` |
| `api.resources.limits.cpu` | Maximum CPU limit | `1000m` |
| `api.resources.limits.memory` | Maximum memory limit | `512Mi` |
| `api.probes.startup.failureThreshold` | Startup probe failure count (3s period) | `20` |
| `postgresql.enabled` | Whether to deploy in-tree PostgreSQL | `true` |
| `postgresql.image.repository` | PostgreSQL container image | `postgres` |
| `postgresql.image.tag` | PostgreSQL image tag | `16-alpine` |
| `postgresql.auth.existingSecretName` | Pre-provisioned Kubernetes Secret | `forgetasks-db-secret` |
| `postgresql.auth.secretKeys.passwordKey` | Key within Secret containing password | `postgres-password` |
| `postgresql.auth.database` | Database name | `forgetasks` |
| `postgresql.auth.username` | Database application user | `forgeuser` |
| `postgresql.persistence.size` | Storage request size | `1Gi` |
| `postgresql.persistence.accessMode` | Volume access mode | `ReadWriteOnce` |
| `test.enabled` | Enable `helm test` connection hook | `true` |
| `test.image.repository` | Test hook container image | `postgres` |
| `test.image.tag` | Test hook image tag | `16-alpine` |

## Values Profiles

- **`values.yaml`:** Central base specification with schema defaults.
- **`values-dev.yaml`:** Profile for development and sandbox validation using local offline images.
- **`values-staging.yaml`:** Profile for staging promotion requiring an immutable SHA-256 digest published by CI.

## Static Linting & Dry-Run Verification

```bash
# Lint the chart against base values
helm lint platform/charts/forgetasks

# Lint against development values
helm lint platform/charts/forgetasks -f platform/charts/forgetasks/values-dev.yaml

# Lint against staging validation input (with valid digest)
helm lint platform/charts/forgetasks -f platform/charts/forgetasks/values-staging.yaml \
  --set api.image.digest=sha256:26aad76a827e94fbcff9900eecc1f08c9096732386345914fa65b058a74e0d91

# Render manifests locally
helm template forgetasks-test platform/charts/forgetasks -f platform/charts/forgetasks/values-dev.yaml
```
