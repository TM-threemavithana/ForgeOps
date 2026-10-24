# ADR-0002: Single Modular Application vs. Distributed Microservices

**Status:** Accepted  
**Date:** 2026-10-22  
**Deciders:** ForgeOps Architecture Review

---

## Context
A common failure mode in DevOps portfolio projects is constructing an artificial mesh of 5–10 miniature microservices. This introduces severe local resource bloat (each JVM/container consuming 300–800 MB RAM), complex distributed debugging friction, and synthetic network latency without demonstrating authentic operational depth.

ForgeOps requires a realistic application capable of demonstrating database migrations, concurrency control, REST APIs, health probes, Prometheus metrics, structured logging, and resilience drills, while operating comfortably within host hardware budgets.

## Options Considered
1. **Multi-Service Microservices Mesh (5+ microservices):** Demonstrates distributed tracing across services, but exceeds the 16 GB laptop memory capacity and adds unnecessary operational overhead.
2. **Trivial "Hello World" Container:** Negligible resource usage, but fails to demonstrate stateful persistence, database connection pools, schema migrations, or business error budgets.
3. **Single Modular Spring Boot Service (`ForgeTasks API`) with PostgreSQL:** A well-structured, production-grade monolithic API managing Accounts, Projects, and Tasks, backed by PostgreSQL and Flyway.

## Decision
Implement a **Single Modular Spring Boot Application (`apps/forgetasks-api`) with PostgreSQL**.
- The application will feature distinct domain boundaries (`Account`, `Project`, `Task`), optimistic concurrency locking (HTTP `If-Match` / `409 Conflict`), Flyway migrations, RFC 9457 Problem Details (see ADR-0013), and Spring Boot Actuator with Micrometer metrics.
- All core platform engineering patterns (GitOps, canary digests, rollback, DB backups, alert triggers, k6 load testing) will operate against this single real service.

## Consequences & Trade-offs
### Positive:
- **Low Footprint:** A single JVM process consumes ~350–500 MB RAM, leaving sufficient headroom for Kubernetes control planes and monitoring components on a 16 GB laptop.
- **Realistic Persistence:** True relational schema constraints, foreign keys, indexes, and transactional boundaries are demonstrated.
- **Deep Observability:** Metrics, traces, and logs reflect actual HTTP route timings and database connection pool saturation.

### Negative / Limitations:
- Cross-service distributed tracing across multiple network hops cannot be demonstrated (distributed tracing will trace HTTP ingress to PostgreSQL internal query spans).
- Service mesh routing (e.g., Istio traffic splitting) is out of scope.

## Verification Tests
- Unit and integration tests pass with ≥80% service code coverage.
- Testcontainers PostgreSQL validates Flyway migrations and schema rollback behaviors.
- Health checks (`/actuator/health/liveness`, `/actuator/health/readiness`) accurately reflect database connectivity status.

## Reconsideration Triggers
- Addition of an asynchronous background worker service (e.g., notification worker) if the host hardware profile is upgraded to Capstone (32 GB RAM).
