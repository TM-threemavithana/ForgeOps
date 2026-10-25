# ForgeOps Platform Engineering — Kind & Kubernetes Baseline

This directory tree defines the Kubernetes platform architecture for the ForgeOps local DevOps laboratory.

## Directory Layout

```text
platform/
├── kind/
│   └── cluster-config.yaml              # Kind cluster configuration (Kubernetes v1.34.11, loopback 127.0.0.1)
└── k8s/
    ├── namespaces/
    │   ├── forgeops-dev.yaml            # Dev namespace, ResourceQuota, LimitRange
    │   └── forgeops-staging.yaml        # Staging namespace, ResourceQuota, LimitRange
    └── dev/
        ├── postgres/
        │   ├── secret.yaml.example      # Sanitized Secret template
        │   ├── service.yaml             # Headless & ClusterIP database Services
        │   └── statefulset.yaml         # PostgreSQL 16 Alpine StatefulSet (volumeClaimTemplates)
        └── api/
            ├── configmap.yaml           # Spring Boot configuration
            ├── service.yaml             # ClusterIP service on port 8080
            └── deployment.yaml          # ForgeTasks API Deployment (non-root, probes, cgroup limits)
```

## StorageClass Inspection in Kind

Kind deploys `rancher/local-path-provisioner` in the `local-path-storage` namespace by default. It registers a cluster-scoped StorageClass named `standard` marked with `storageclass.kubernetes.io/is-default-class: "true"`.

To inspect the active StorageClass once the cluster is provisioned:

```bash
kubectl --kubeconfig=~/.kube/config-forgeops get storageclass
```

Expected output:
```text
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  1m
```

The PostgreSQL StatefulSet requests storage via `volumeClaimTemplates` without hardcoding `storageClassName`, allowing Kubernetes to automatically bind to the default `standard` StorageClass.

## Security & Storage Ownership

- **PostgreSQL Alpine UID/GID:** In `postgres:16-alpine`, the unprivileged user is `postgres` (`uid=70, gid=70`).
- **Volume Permissions:** The StatefulSet declares `fsGroup: 70` at the pod level and `runAsUser: 70`, `runAsGroup: 70` at the container level.
- **Data Subdirectory:** The environment variable `PGDATA=/var/lib/postgresql/data/pgdata` ensures the PostgreSQL database files reside in a dedicated subpath inside the mounted volume mount root.

## Offline Container Images

To guarantee offline reproducibility and eliminate external registry rate limits during lab execution:
- API image: `forgetasks-api:1.0.0`
- Database image: `postgres:16-alpine`

Images are preloaded into the Kind control-plane node using:
```bash
make cluster-load-images
```
Kubernetes manifests specify `imagePullPolicy: IfNotPresent`, ensuring kubelet resolves images directly from the node's containerd cache without internet pulls.

## Secret Injection (ADR-0006)

Database credentials are never committed to Git or exposed in process arguments (`/proc` table). The injection script [`scripts/cluster/inject-secrets.sh`](file:///C:/Project/ForgeOps/scripts/cluster/inject-secrets.sh) reads credentials from a protected local file (`~/.config/forgeops/secrets/db_password.txt`, `0600`) and provisions `forgetasks-db-secret` via `kubectl create secret --from-file`:
```bash
make k8s-dev-deploy
```

## Verification & Acceptance Testing (Gate G06)

The verification test harness [`scripts/cluster/verify-g06.sh`](file:///C:/Project/ForgeOps/scripts/cluster/verify-g06.sh) provides strict semantic separation:
- `make k8s-dev-verify`: **Read-Only Inspection**. Performs zero mutations. Validates node, system pods, namespaces, quotas, LimitRanges, DB readiness, and API health endpoints (`/actuator/health/readiness`, `/actuator/health/liveness`, `/actuator/prometheus`) via temporary loopback port-forwarding.
- `make k8s-dev-smoke-write`: **Transactional Smoke Test**. Exercises an end-to-end `POST /api/v1/accounts` registration request to verify Flyway migrations, Hibernate JPA constraints, and database commits.
- `make k8s-dev-drill-persistence`: **Stateful Persistence Drill**. Requires `ALLOW_POD_TERMINATION=yes`. Validates resource labels, deletes `forgetasks-db-0`, verifies StatefulSet replacement, and proves data persistence via duplicate account registration collision (`HTTP 409`).
- `make k8s-dev-drill-a602`: **Stateless Self-Healing Drill**. Requires `ALLOW_POD_TERMINATION=yes`. Validates API labels, deletes the API pod, measures ReplicaSet controller recovery time, evaluates single-replica availability impact, and confirms traffic resumption.

## Lifecycle Ownership Boundaries (ADR-0003)

| Component | Gate | Sole Owner | Mechanism |
|---|---|---|---|
| **Kind Cluster Container** | G06 | Shell Automation | `scripts/cluster/create-cluster.sh` |
| **Vanilla Manifests** | G06 | Developer / Operator | `kubectl apply` |
| **Helm Application Chart** | G07 | Helm Chart Authoring | `platform/charts/forgetasks` |
| **Continuous GitOps Sync** | G08 | Argo CD Controller | Out-of-band Git pull & sync |

Direct `kubectl apply` is strictly temporary for Gate G06 acceptance and will be retired once Argo CD GitOps is bootstrapped in Gate G08.
