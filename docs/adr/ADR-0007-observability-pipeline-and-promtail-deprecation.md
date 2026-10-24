# ADR-0007: Observability Architecture and Promtail Deprecation

**Status:** Accepted  
**Date:** 2026-10-22  
**Deciders:** ForgeOps Architecture Review

---

## Context
A complete SRE observability stack requires the correlation of metrics, logs, and alerts. In historical Kubernetes observability stacks, Promtail was used as the daemon to ship container logs to Grafana Loki.

However, **Grafana officially deprecated Promtail, declaring its End-of-Life (EOL) effective March 2, 2026**. Using Promtail in a modern 2026 platform architecture violates version support standards and represents technical debt.

Additionally, running full observability stacks with high retention periods on a 16 GB laptop with 6.62 GB free SSD risks catastrophic out-of-memory (OOM) failures and disk exhaustion.

## Options Considered
1. **Use Legacy Promtail:** Simple copy-paste tutorials exist, but Promtail is officially unsupported, lacks security patches after March 2026, and is rejected by the Master Plan.
2. **Grafana Alloy + Loki + Prometheus + Alertmanager:** Grafana Alloy is the official, actively supported OpenTelemetry Collector distribution and logging agent, natively supporting `loki.*` components for Kubernetes pod log collection.
3. **Elasticsearch / Fluentd / Kibana (EFK):** Extreme JVM and memory consumption (3–6 GB RAM baseline), completely incompatible with host hardware constraints.

## Decision
Adopt **Prometheus + Grafana + Alertmanager** for Metrics/Alerting and **Grafana Alloy + Loki** for Logging:
1. **Promtail Sunset Enforcement:** Promtail will **not** be deployed anywhere in ForgeOps. All log harvesting from Kind pod containers will be executed by **Grafana Alloy** using its native `loki.source.podlogs`, `loki.process`, and `loki.write` pipelines.
2. **Metrics Pipeline:**
   - Spring Boot Actuator with Micrometer exposes Prometheus-formatted metrics at `/actuator/prometheus` (internal scrape access only).
   - Prometheus server scrapes application and Kubernetes state targets with bounded scrape intervals (15s–30s).
   - Prometheus alerting rules route directly to local Alertmanager demo receivers.
3. **Structured JSON Logs & Trace Correlation:**
   - The application outputs structured JSON logs containing timestamp (UTC), level, service, namespace, and contextual `requestId`.
   - Grafana dashboards correlate metric spikes with log streams filtered by service and `requestId`.
4. **Strict Retention Caps for Local Hardware:**
   - Metrics retention: capped at 24 hours (Core) / 3 days (Extended).
   - Loki log retention: capped at 24 hours / 500 MB disk limit.
   - Storage limits prevent runaway disk consumption on the 6.62 GB free host drive.

## Consequences & Trade-offs
### Positive:
- **Up-to-Date Architecture:** Adheres to current 2026 Grafana ecosystem standards by adopting Alloy.
- **Unified Correlation:** Grafana acts as a single pane of glass querying both Prometheus and Loki.
- **Resource Protection:** Aggressive retention limits protect host SSD space and memory budgets.

### Negative / Limitations:
- Grafana Alloy configuration syntax (Alloy / River syntax) requires learning distinct declarative component syntax compared to legacy Promtail YAML.
- Distributed tracing (Tempo) is deferred to the Capstone phase to prevent memory starvation.

## Verification Tests
- `alloy` pod runs cleanly as a DaemonSet/Deployment in Kind without crashing.
- An intentional 500 Internal Server Error request produces an Alloy-ingested log line visible in Grafana Loki filtered by `requestId`.
- Prometheus metrics show `up{job="forgetasks"}` == 1.
- Alert transitions (`pending` → `firing` → `resolved`) verified using a deliberate failure injection.

## Reconsideration Triggers
- Introduction of OpenTelemetry Collector + Tempo (G14) if hardware is expanded.
