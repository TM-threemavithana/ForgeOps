# ADR-0013: Optimistic Concurrency, RFC 9457 Problem Details, and Multi-Tenant Isolation

**Status:** Accepted  
**Date:** 2026-10-22  
**Deciders:** Senior Java Backend Engineer, DevOps Architect, Security Reviewer

---

## Context
As the ForgeTasks API enters implementation design for Gate G01, four key architectural contracts require formal definition:
1. **Concurrency Control:** Concurrent web clients modifying the same project or task must not overwrite each other's changes silently (lost update problem). Pessimistic database row locks (`SELECT ... FOR UPDATE`) introduce latency, deadlocks, and connection pool saturation under k6 load testing.
2. **Standardized Error Representation:** RFC 7807 (Problem Details for HTTP APIs) was formally superseded by **RFC 9457** in 2023. Error responses must conform to modern standards and integrate seamlessly with Spring Boot 3/4 `ProblemDetail` abstractions.
3. **Multi-Tenant Information Disclosure:** When User A attempts to access or modify a resource owned by User B, returning HTTP `403 Forbidden` confirms to an attacker that the resource exists and is private, enabling user/resource UUID harvesting and timing analysis.
4. **Database Migration vs. Seed Data Purity:** Combining test/sample data with structural DDL schema migrations in Flyway risks accidental leakage of test users, default passwords, and mock tasks into production databases.

## Options Considered
- **Concurrency:**
  - *Option A:* Pessimistic locking. Rejected due to poor concurrency throughput and deadlock risk.
  - *Option B:* Optimistic concurrency with `@Version` and HTTP `If-Match` / `ETag`. Selected.
- **Error Format:**
  - *Option A:* Custom JSON error wrapper. Rejected; breaks API standardization.
  - *Option B:* RFC 9457 Problem Details (`application/problem+json`). Selected.
- **Tenant Isolation:**
  - *Option A:* Return `403 Forbidden` on cross-tenant access. Rejected; leaks resource existence.
  - *Option B:* Return `404 Not Found` for any cross-tenant project or task access. Selected.
- **Data Seeding:**
  - *Option A:* Monolithic Flyway scripts (`V1__schema`, `V2__seed`). Rejected; pollutes production.
  - *Option B:* Strict segregation: `db/migration` (DDL only) vs. `db/dev-data` / `@Profile("dev")` seeders. Selected.

## Decision

### 1. Standards-Aligned Optimistic Concurrency Contract (RFC 7232 / RFC 9110)
- Entities (`Project`, `Task`) contain an integer version field (`version BIGINT NOT NULL DEFAULT 0`) annotated with `@Version`.
- Resource representation endpoints (`GET /api/v1/projects/{id}`, `GET /api/v1/tasks/{id}`) return a strong `ETag` response header containing the quoted entity version: `ETag: "0"`.
- All mutating operations requiring conditional updates or deletions (`PATCH /api/v1/projects/{id}`, `DELETE /api/v1/projects/{id}`, `PATCH /api/v1/tasks/{id}`, `DELETE /api/v1/tasks/{id}`) **strictly mandate** the `If-Match` request header:
  1. **Missing `If-Match` Header:** Returns **HTTP 428 Precondition Required** (`urn:forgeops:error:precondition-required`). The API refuses blind updates and does not fall back to unverified payload fields.
  2. **Stale / Mismatched `If-Match` Value:** If the `If-Match` header does not match the current database entity version, the API returns **HTTP 412 Precondition Failed** (`urn:forgeops:error:precondition-failed`), preventing lost updates before database lock acquisition.
  3. **Concurrent Transaction Collision:** If two concurrent requests satisfy `If-Match` simultaneously, the atomic JPA `@Version` check triggers an `OptimisticLockingFailureException` during transaction commit. The global exception handler translates this race condition into **HTTP 409 Conflict** (`urn:forgeops:error:conflict`).
- On successful update, the API returns **HTTP 200 OK** with the updated resource representation and the new incremented version in the response header: `ETag: "<version+1>"`. Successful deletion returns **HTTP 204 No Content**.

### 2. RFC 9457 Problem Details Standard
- All error responses (4xx and 5xx) use Content-Type `application/problem+json`.
- Standard attributes:
  - `type`: URI identifying the problem type (e.g., `urn:forgeops:error:validation`, `urn:forgeops:error:not-found`, `urn:forgeops:error:conflict`).
  - `title`: Short human-readable summary of problem type.
  - `status`: HTTP status code matching the response header.
  - `detail`: Human-readable explanation specific to this occurrence.
  - `instance`: URI of the request endpoint (e.g., `/api/v1/projects/123`).
  - `requestId`: Unique correlation UUID extracted from SLF4J MDC.
  - `timestamp`: UTC ISO-8601 timestamp.
  - `invalidParams`: Array of field validation errors (`field`, `reason`, `rejectedValue`).

### 3. Anti-Enumeration Tenant Isolation
- A user authenticated with `ROLE_USER` possesses access strictly to projects where `owner_account_id == principal.id` and tasks belonging to their owned projects.
- Any attempt by User A to read (`GET`), modify (`PATCH`), or delete (`DELETE`) a resource owned by User B shall return **HTTP `404 Not Found`** with a standard generic Problem Details payload (`Resource not found`).
- Users with `ROLE_ADMIN` retain global administrative visibility where explicitly required for audit.

### 4. Production vs. Dev/Test Migration Segregation
- `src/main/resources/db/migration/`: Contains only production-grade DDL schema migrations (`V1__init_schema.sql`, subsequent `V2__*.sql`). Contains **zero** default accounts, passwords, or mock tasks.
- `src/main/resources/db/dev-data/`: Contains development sample projects and tasks, loaded only when `spring.profiles.active=dev` by overriding Flyway locations:
  ```yaml
  spring.flyway.locations: classpath:db/migration,classpath:db/dev-data
  ```
- Test suites (`@ActiveProfiles("test")`) use Testcontainers and dedicated test fixtures (`data-test.sql`), ensuring tests never execute against seeded development state.

## Consequences & Trade-offs
### Positive:
- **Zero Lost Updates:** Concurrent client modifications are safely serialized without pessimistic lock timeouts.
- **Hardened Privacy:** Malicious users cannot brute-force UUIDs to discover existing project names or team IDs.
- **Production Safety:** Production databases remain completely free of mock accounts and test fixtures.
- **Standardized Client Integration:** Frontend and API consumers interact with standardized RFC 9457 payloads and HTTP `ETag` / `If-Match` headers.

### Negative / Limitations:
- Clients must capture `ETag` / `version` on GET requests and send `If-Match` on updates.
- Clients receiving 409 Conflict must reload the resource, re-apply changes, and retry.

## Verification Tests
- `ConcurrencyLockingTest`: Concurrent threads attempting to modify the same task version assert that exactly one succeeds with 200 and the other receives 409 Conflict with RFC 9457 body.
- `ProjectSecurityTest`: User B attempting to GET or PATCH User A's project asserts HTTP 404 Not Found.
- `MigrationTest`: Clean Flyway execution in `prod` profile verifies `accounts`, `projects`, and `tasks` tables contain 0 rows initially.

## Reconsideration Triggers
- Introduction of collaborative real-time editing (Operational Transformation / CRDTs) if requirements expand beyond standard REST.
