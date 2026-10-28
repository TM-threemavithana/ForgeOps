# Runbook: API Pod CrashLoopBackOff & Unexpected Termination

## Symptoms & Detection
- Alert: `KubePodCrashLooping` or `KubePodNotReady`
- `kubectl get pods` shows pod status `CrashLoopBackOff` or `Error` with restart count incrementing.
- HTTP requests return 502 Bad Gateway or 503 Service Unavailable if all replicas are down.

## Diagnostic Steps

### 1. Identify Failing Pods
```bash
kubectl get pods -n <target-namespace> -l app.kubernetes.io/name=sre-api
```

### 2. Inspect Termination Reason and Exit Code
```bash
kubectl get pod <pod-name> -n <target-namespace> -o jsonpath='{.status.containerStatuses[0].lastState.terminated}' | jq .
```
- **Exit Code 137**: Process terminated by SIGKILL (commonly Linux OOMKiller due to container memory limit breach).
- **Exit Code 143**: Process terminated by SIGTERM (graceful shutdown or liveness probe failure).
- **Exit Code 1**: General application exception during Spring Boot bootstrap.

### 3. Retrieve Application Crash Logs
```bash
kubectl logs <pod-name> -n <target-namespace> --previous --tail=100
```
Search for:
- `FlywayMigrationException` / `CannotCreateTransactionException` (database connectivity or migration issue).
- `OutOfMemoryError: Java heap space` (JVM heap exhaustion).
- `BeanCreationException` (missing environment variables or secret misconfiguration).

## Mitigation & Recovery Procedures

### Scenario A: Out Of Memory (OOMKilled - Exit Code 137)
1. Verify memory limits in deployment spec:
   ```bash
   kubectl get deployment <name> -n <namespace> -o jsonpath='{.spec.template.spec.containers[0].resources}'
   ```
2. If temporary burst, adjust limits or optimize JVM `-XX:MaxRAMPercentage` settings.
3. Restart pod:
   ```bash
   kubectl rollout restart deployment/<name> -n <namespace>
   ```

### Scenario B: Database Connection Failure
1. Check database pod status in target namespace:
   ```bash
   kubectl get pods -n <namespace> -l app.kubernetes.io/name=sre-db
   ```
2. Verify database logs and readiness:
   ```bash
   kubectl logs deployment/sre-db -n <namespace> --tail=50
   ```
3. Once database recovers, Spring Boot HikariCP pool automatically re-establishes connections.

## Post-Recovery Verification
1. Verify pods reach 1/1 Ready:
   ```bash
   kubectl rollout status deployment/<name> -n <namespace>
   ```
2. Check Actuator health:
   ```bash
   kubectl exec -it <pod-name> -n <namespace> -- wget -qO- http://localhost:8080/actuator/health/readiness
   ```
3. Verify all 5 protected PVCs remain intact.
