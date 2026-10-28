# Runbook: High Request Latency & Resource Saturation

## Symptoms & Detection
- Alert: `HighRequestLatency` (p95 latency > 250ms for 5m) or `HighCPUThrottling`.
- k6 stress test reports elevated p95/p99 response times or threshold abort.
- Grafana dashboard shows elevated HikariCP active connection counts or CPU saturation.

## Diagnostic Steps

### 1. Identify Latency Bottleneck Layer
Using Grafana Tempo / OpenTelemetry traces:
1. Navigate to Grafana > Explore > Tempo datasource.
2. Filter by service `forgetasks-api` or tag `error=true`.
3. Select an affected trace and inspect span durations:
   - **Controller Dispatch Span**: High duration indicates thread pool saturation.
   - **Database / JPA Span**: High duration indicates slow SQL queries, locks, or connection wait times.
   - **GC Pauses**: Inspect JVM garbage collection pause metrics in Prometheus.

### 2. Inspect HikariCP Connection Pool Saturation
Run PromQL in Grafana:
```promql
hikaricp_connections_active{pool="ForgeTasksHikariCP"}
/
hikaricp_connections_max{pool="ForgeTasksHikariCP"}
```
If ratio $\ge 0.90$, threads are blocking waiting for available database connections.

### 3. Check CPU & Memory Throttling
```bash
kubectl top pods -n <target-namespace>
```
Inspect cgroup throttling via Prometheus:
```promql
sum(rate(container_cpu_cfs_throttled_periods_total{namespace="<target-namespace>"}[5m]))
/
sum(rate(container_cpu_cfs_periods_total{namespace="<target-namespace>"}[5m]))
```

## Mitigation & Recovery Procedures

### Scenario A: Connection Pool Starvation
1. If client load exceeds pool capacity, scale deployment horizontally:
   ```bash
   kubectl scale deployment/<name> -n <namespace> --replicas=<N+1>
   ```
2. Each replica maintains an independent HikariCP pool (default: 10 connections).

### Scenario B: Transient Load Spike
1. k6 tests include automatic abort thresholds to prevent uncontrolled saturation.
2. Allow load test cooldown period; verify latency returns to baseline $\le 50\text{ms}$.

## Post-Recovery Verification
1. Run k6 recovery check:
   ```bash
   k6 run tests/load/k6/recovery.js
   ```
2. Verify p95 latency $\le 200\text{ms}$ under low concurrency (2 VUs).
3. Confirm 0 pod restarts and healthy connection pool.
