# ForgeOps: Engineering Lessons Learned & Architectural Postmortems

This document details four pivotal operational lessons and architectural postmortems encountered during the implementation and evolution of ForgeOps. Each case study documents the problem context, root cause, blast radius, engineering remediation, and long-term architectural takeaway.

---

## Case Study 1: The OCI Attestation vs. Runnable Image Digest Incident (Gate G10)

### 1. Problem Statement
During deployment testing in Gate G10, a newly referenced container image digest deployed via Helm caused the `forgetasks-api` Pod to enter a `CreateContainerError` / `CrashLoopBackOff` state. The container runtime failed with:
```text
failed to create containerd task: failed to create shim task: OCI runtime create failed:
container_linux.go: executable file not found in $PATH: unknown
```

### 2. Root Cause Analysis (RCA)
Modern container registries (GHCR, Docker Hub) using Sigstore Cosign or GitHub Actions Docker Buildx push multiple OCI artifact manifests under the same repository tag:
- The actual runnable Linux container image.
- OCI Attestation bundles (SBOM, SLSA provenance documents) formatted as `application/vnd.oci.image.manifest.v1+json` or `application/vnd.in-toto+json`.

In the automated release script, a command querying the registry for the latest tag's digest captured the OCI attestation manifest digest rather than the container image digest. When Kubernetes instructed containerd to pull and execute the digest, containerd pulled an attestation JSON blob instead of a runnable container filesystem layer.

### 3. Blast Radius & Containment
- **Impact:** Zero downtime in the rehearsal environment.
- **Why it was contained:**
  1. Kubernetes Deployment used `strategy: RollingUpdate` with `maxUnavailable: 0`. The old, healthy replica continued serving traffic because the new replica never passed readiness.
  2. Argo CD automated sync was disabled, preventing the corrupted manifest from cascading across other environments.

### 4. Remediation & Long-Term Controls
1. **Digest Verification Script:** Created `scripts/test_publish_hardening.py` to inspect the MIME type of image manifests before updating Helm values.
2. **Type Assertion:** Releases must verify that the manifest contains `mediaType: application/vnd.docker.distribution.manifest.v2+json` or `config.mediaType: application/vnd.oci.image.config.v1+json`. Attestation layers are explicitly filtered out.

---

## Case Study 2: SRE Resilience Under High-Concurrency Load (Gate G12)

### 1. Problem Statement
In early iterations of Gate G12, running unconstrained k6 load tests caused high latency spikes and intermittent connection timeouts on local port-forwarded endpoints.

### 2. Root Cause Analysis (RCA)
- **Local Host TCP Exhaustion:** Single-node Kind clusters share the host machine's networking stack. Opening hundreds of concurrent ephemeral TCP connections through `kubectl port-forward` quickly exhausts local socket buffers.
- **Port-Forward Single-Stream Bottleneck:** `kubectl port-forward` operates over a single multiplexed SPDY or WebSocket connection. When subjected to bursty load, the port-forward process itself becomes a CPU bottleneck before traffic ever reaches the Kubernetes pod.

### 3. Remediation & Long-Term Controls
1. **Arrival-Rate Throttling:** Configured k6 scenarios with an explicit rate ceiling: maximum 20 requests/second and a cap of 25 Virtual Users (VUs).
2. **Dedicated Target Verification:** Updated `tests/load/run-k6.sh` to mandate an explicit port-forward on port `8082` pointing exclusively to `forgeops-sre-lab`. The script checks endpoint headers to ensure load is never inadvertently directed at the production database or active dev microservice.
3. **Results:** After rate governance was applied, the system processed **2,275 HTTP requests across 5 scenarios with zero errors (0.00% error rate)** and a median p50 latency of 2.1 ms.

---

## Case Study 3: The Danger of `pg_restore --clean` in Automated DR (Gate G13)

### 1. Problem Statement
Early disaster recovery automation utilized standard `pg_restore` commands containing `--clean` and `--if-exists` flags to restore databases over existing instances.

### 2. Root Cause Analysis (RCA)
- **Destructive Pre-action:** The `--clean` flag instructs `pg_restore` to issue `DROP TABLE` commands for all objects in the archive before recreating them.
- **Catastrophic Failure Mode:** If the restore script is executed against an active database due to a typo or misconfigured Kubernetes context, or if the archive file is corrupted, `pg_restore` drops existing tables before failing, resulting in irreversible data loss.
- **Exit Code Masking:** Scripts chained with `|| true` hid restore errors, falsely marking failed drills as successful.

### 3. Remediation & Long-Term Controls
1. **Strict Target Isolation:** Replaced restores against existing instances with a **disposable target pattern** (`forgeops-dr-lab`). Restores are permitted only against fresh, ephemeral databases containing zero pre-existing application tables.
2. **Strict Error Trapping:** Stripped all `--clean` flags and mandated `--exit-on-error`. If any SQL statement fails during restore, `pg_restore` immediately halts with a non-zero exit code.
3. **Full Relational & Auth Verification:** Restores are considered successful only after schema migrations are verified and an automated smoke test authenticates against real BCrypt password hashes in the restored database.

---

## Case Study 4: Client-Side Policy Enforcement vs. In-Cluster Admission Controllers (Gate G14)

### 1. Problem Statement
When designing Gate G14 Policy-as-Code, the initial proposal considered deploying the Kyverno admission controller directly inside the local Kind cluster.

### 2. Architectural Trade-off Analysis
- **Dynamic Admission Overhead:** Running Kyverno in-cluster requires running a webhook server with CA certificates, listening on port 9443, and intercepting every Kubernetes API mutation request.
- **Failure Risk on Local Workstations:** In a resource-constrained single-node environment (WSL2), an admission controller can easily experience CPU throttling or OOM kills. When a validating webhook with `failurePolicy: Fail` crashes, the Kubernetes API server blocks all pod scheduling and cluster operations, effectively bricking the lab.

### 3. Remediation & Long-Term Controls
1. **Shift-Left Static Validation:** Decoupled Kyverno from the Kubernetes runtime. We integrated the Kyverno CLI (`kyverno apply`) directly into the GitHub Actions CI pipeline and local test scripts.
2. **Complete Coverage:** Kyverno audits 100% of Helm-rendered Kubernetes manifests across 10 security policies prior to code merge.
3. **Outcome:** Achieved 100% policy enforcement against CIS benchmarks without consuming a single megabyte of cluster RAM or introducing cluster-deadlock failure modes.
