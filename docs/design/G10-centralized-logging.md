# G10 — Centralized Logging Architecture

Status: DESIGN PROPOSAL — NOT DEPLOYED

Baseline: G09 complete, master 6337cc5
Cluster: kind-forgeops

## Objective

Collect permitted ForgeTasks Kubernetes application logs using
Grafana Alloy, store them in Loki, and query them through the
existing Grafana installation.

Acceptance ID: A-1001.

## Proposed architecture

ForgeTasks API
    |
    | Kubernetes Pod logs
    v
Grafana Alloy
    |
    | Namespace filtering, parsing and redaction
    v
Loki (Monolithic, one replica)
    |
    | LogQL
    v
Existing G09 Grafana

## Isolation boundaries

- Preserve all G06 and G08 application and database resources.
- Preserve G09 metrics and alerting resources.
- Initially collect logs only from forgeops-gitops-rehearsal.
- Do not collect secrets or unrelated namespace logs.
- Prefer Kubernetes API collection over privileged host log mounts.
- Use namespace-scoped RBAC wherever supported.
- Use a dedicated Alloy service account.
- Do not expose Loki or Alloy publicly.

## Logging contract

Desired application fields:

- UTC timestamp
- Log level
- Service name
- Request/correlation ID
- Exception classification
- Sanitized context

Request IDs must remain searchable without becoming
high-cardinality Loki index labels.

Never persist passwords, tokens, authorization headers,
database credentials or personal data.

Existing log format must be inspected before implementation.

## Initial lab sizing proposal

- Loki: Monolithic mode, one replica.
- Storage: Local filesystem, persistent PVC.
- Loki PVC target: 2 GiB initially; validate actual usage.
- Retention target: 24 hours initially; validate compactor behavior.
- Alloy: Lightweight collector, scoped to approved namespaces.
- Disable optional caches and components unless justified.
- Set explicit CPU and memory requests and limits.
- Avoid an additional Grafana deployment.

All sizing values require chart validation and capacity review.

## Hardware constraints

Observed during G10 readiness:

- Kind node memory limit: approximately 7.45 GiB.
- Kind memory usage: approximately 3.81 GiB.
- Existing Kubernetes memory requests: 2354 MiB.
- Windows C: approximately 31 GiB free, 94% used.
- Docker local volumes: approximately 7.1 GB.

The Windows drive is the limiting storage consideration.
Do not interpret WSL filesystem capacity as guaranteed host
capacity.

No Docker volume pruning or cluster recreation is authorized.

## GitOps delivery

- Pin Loki and Alloy chart versions and image versions.
- Validate Helm render and Kubernetes resource inventory.
- Define namespace and AppProject ownership boundaries.
- Use reviewed pull requests.
- Preserve G09 manual-sync and non-pruning behavior.
- Review Grafana datasource provisioning before integration.

## Acceptance

1. Loki is healthy and queryable.
2. Alloy collects only approved application logs.
3. Grafana Loki datasource reports healthy.
4. A deliberate API error is retrievable by service, time and
   request/correlation ID.
5. Sensitive information is absent from inspected logs.
6. Logs survive an approved collector or API Pod replacement.
7. Storage, ingestion and retention limits are evidenced.
8. G06, G08 and G09 remain unaffected.
9. Acceptance results are archived in docs/evidence/G10.

## Deployment gate

Do not install workloads until:

- Log structure and sanitization approach are verified.
- Chart versions are pinned and rendered successfully.
- Effective storage location and capacity are reviewed.
- Loki retention and persistence settings are validated.
- RBAC positive and negative tests are prepared.
- GitOps ownership and rollback plan are approved.

## G10-A2 - Logging Audit

- Spring Boot 4 application.
- Request header: X-Request-ID.
- MDC correlation key: correlationId.
- RequestCorrelationFilter validates or generates IDs.
- MDC is cleared after each request.
- Existing console logging uses a plain-text pattern.
- The pattern already references correlationId.
- No JSON records found in 400 sampled log lines.

### Proposed implementation

- Enable Spring Boot ECS structured JSON console logging.
- Validate compatibility with the existing log pattern.
- Add automated correlation-ID logging tests.
- Keep request IDs out of Loki index labels.
- Exclude passwords, tokens and authorization headers.
- Preserve G06, G08 and G09 workloads and PVCs.
- Deploy Loki and Alloy only after validation.

### Next phase

G10-B: Structured JSON logging and automated tests.
