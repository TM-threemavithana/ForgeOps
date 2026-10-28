# Runbook: Image Rollout Failure & Rollback (ImagePullBackOff)

## 1. Overview & Real Incident Reference

This runbook addresses failed container image rollouts, non-existent image tags, or registry authentication failures during Kubernetes deployments.

> [!NOTE]
> **Historical Incident Reference (G10-B Incident)**: This procedure is directly derived from and validated by the actual Gate G10-B failed-image incident, where an invalid image tag triggered an `ImagePullBackOff` event during a deployment update, successfully mitigated via rollout undo without impacting persistent database storage.

---

## 2. Detection & Alert Investigation

### Symptoms
- Pods enter `ImagePullBackOff` or `ErrImagePull`.
- `kubectl rollout status` hangs indefinitely.
- Deployment shows desired replicas > ready replicas.
- Prometheus / Alertmanager triggers `KubeDeploymentRolloutStuck`.

### Diagnostic Commands
```bash
# 1. Identify unready pods and container state
kubectl get pods -n <target-namespace> -l app.kubernetes.io/name=sre-api

# 2. Inspect exact failure reason in pod status
kubectl describe pod <failing-pod-name> -n <target-namespace>
```
Look for Events:
- `Failed to pull image "...": rpc error: code = NotFound desc = failed to pull and unpack image ...: not found`
- `Error: ErrImagePull`
- `Error: ImagePullBackOff`

---

## 3. Impact Assessment

Kubernetes Deployments configured with `maxUnavailable: 0` prevent outage during failed rollouts:
- **Zero Traffic Outage**: Existing healthy pods continue running and receiving traffic.
- **Rollout Stall**: The new replica cannot achieve readiness, halting the rollout progression.
- **Service Endpoints**: Kubernetes EndpointSlice excludes the unready pod; only healthy pods remain active in the Service.

Verify active endpoints:
```bash
kubectl get endpoints sre-api -n <target-namespace>
```

---

## 4. Timeline Reconstruction & Root-Cause Analysis (RCA)

1. **Verify Image Tag & Registry**:
   Check if the image tag was mistyped, not published by CI, or removed from GHCR:
   ```bash
   crane digest <image-reference> || docker manifest inspect <image-reference>
   ```
2. **Review Deployment Event Log**:
   ```bash
   kubectl get events -n <target-namespace> --field-selector reason=Failed --sort-by='.metadata.creationTimestamp'
   ```

---

## 5. Recovery & Post-Recovery Verification

### Step 1: Immediate Imperative Rollback
Revert the deployment to the previous known good revision:
```bash
kubectl rollout undo deployment/<deployment-name> -n <target-namespace>
```

### Step 2: Monitor Rollout Completion
```bash
kubectl rollout status deployment/<deployment-name> -n <target-namespace> --timeout=120s
```

### Step 3: Verify Restored Image
```bash
kubectl get deployment <deployment-name> -n <target-namespace> -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Step 4: Verify Protected State
Verify that the 5 protected PVCs across the cluster are unaffected:
```bash
KUBECONFIG=/home/tharuka/.kube/config-forgeops kubectl get pvc -A
```

---

## 6. Prevention & Follow-up Actions
1. **Immutable Digests**: Promote images only via immutable SHA256 digests rather than mutable tags.
2. **CI Provenance**: Enforce GitHub Actions build-and-push checks before committing image references to Git.
3. **Argo CD Health Checks**: Configure Argo CD wave hooks and rollback health assessments.
