# ForgeOps: Known Limitations & Architectural Boundaries

## 1. Purpose & Honesty Invariant

In alignment with the core engineering principles of ForgeOps, this document provides an honest, transparent accounting of the architectural boundaries, environmental constraints, and intentional design limitations of the platform.

ForgeOps is a **production-inspired local platform engineering lab**, not an enterprise multi-region production deployment. Understanding what a platform cannot do is just as critical as knowing what it can do.

---

## 2. Infrastructure & Orchestration Limitations

### 2.1 Single-Node Kind (Kubernetes in Docker)
- **Constraint:** The Kubernetes cluster runs as a single Docker container on a single host operating system (Windows 11 with WSL2).
- **Impact:** While the cluster logically separates control plane and worker components, it shares the underlying Linux kernel, CPU scheduling, and physical memory.
- **What is NOT Tested:** Physical node hardware failures, split-brain network partitions between separate physical hypervisors, and cross-datacenter WAN latency cannot be tested.

### 2.2 Kindnet CNI & NetworkPolicy Enforcement
- **Constraint:** The cluster utilizes Kind's default `kindnet` Container Network Interface.
- **Impact:** `kindnet` handles basic host-local IPAM and iptables NAT masquerading, but **does not enforce Kubernetes `NetworkPolicy` ingress or egress packet filtering**.
- **Mitigation:** NetworkPolicy manifests exist in the repository as architectural references and design specifications. True kernel-level packet dropping would require replacing `kindnet` with an eBPF-based CNI such as Cilium or Calico.

---

## 3. Storage & Disaster Recovery Limitations

### 3.1 Local HostPath Volume Persistence
- **Constraint:** PersistentVolumeClaims for PostgreSQL, Prometheus, Loki, and Tempo utilize local `HostPath` storage bound to the host filesystem.
- **Impact:** If the underlying Docker host container or WSL virtual disk (`ext4.vhdx`) suffers catastrophic corruption, local volumes are destroyed.
- **Mitigation:** Storage retention policies are set to `Retain`, and automated database dumps are exported outside the cluster namespace via `rehearse-dr.sh`.

### 3.2 Backup Storage & Continuous Archiving
- **Constraint:** Database disaster recovery relies on discrete point-in-time logical backups (`pg_dump -Fc`) executed periodically.
- **Impact:** Recovery Point Objective (RPO) is bounded by the backup interval (e.g., 1 hour or 24 hours). Uncommitted transactions occurring between snapshots cannot be recovered.
- **What is NOT Implemented:** Continuous Write-Ahead Log (WAL) archiving to remote object storage (e.g., via pgBackRest or Barman) is deferred because it requires external S3-compatible cloud storage.

---

## 4. Security & Policy Enforcement Limitations

### 4.1 Client-Side Kyverno Enforcement vs. Dynamic Admission
- **Constraint:** Kyverno policies are evaluated client-side via the `kyverno` CLI in GitHub Actions CI and local developer scripts.
- **Impact:** Manifests that pass through CI are guaranteed to be compliant. However, if a developer with direct `kubectl` access manually applies an unverified manifest directly to the Kind cluster, there is no in-cluster dynamic admission controller to intercept and reject the API request.
- **Rationale:** Avoids control-plane memory bloat and API server deadlock on resource-constrained local workstations.

### 4.2 Offline Asymmetric Secret Key Custody
- **Constraint:** SOPS encryption uses local `age` identity files stored on the operator's filesystem.
- **Impact:** Private keys are not backed by a Hardware Security Module (HSM), cloud Key Management Service (AWS KMS, GCP KMS), or HashiCorp Vault.
- **Mitigation:** The repository utilizes a dual-recipient scheme (`Primary Operational` + `Recovery Escrow`), value-only encryption (`encrypted_regex: '^(data|stringData)$'`), and guarantees zero private keys or plaintext secret payloads are ever committed to Git.

---

## 5. Continuous Delivery & GitOps Limitations

### 5.1 Disabled Argo CD Automatic Synchronization
- **Constraint:** Argo CD automatic synchronization is intentionally disabled in the rehearsal environment (`G08`).
- **Impact:** Desired-state Git merges do not automatically apply to the cluster in real time; an operator must trigger manual sync via the Argo CD UI or CLI.
- **Rationale:** Disabling auto-sync was a deliberate safety invariant established after Gate G08 to prevent automated reconciliation loops during rollback drills and chaos injection experiments.

---

## 6. Summary Matrix of Architectural Boundaries

| Feature Domain | Production Enterprise Target | ForgeOps Lab Implementation | Rationale for Difference |
|:---|:---|:---|:---|
| **Cloud Hosting** | Multi-AZ AWS EKS / GCP GKE | Single-node Kind in WSL2 | Zero cloud costs; 100% offline reproducibility. |
| **Network Security** | eBPF packet filtering (Cilium) | Manifest specification (kindnet) | Eliminates high kernel memory overhead in local dev. |
| **Secret Management**| Cloud KMS / HashiCorp Vault | Mozilla SOPS + age | Value-only encryption without cloud provider lock-in. |
| **Database DR** | Multi-AZ replica + continuous WAL | Periodic `pg_dump` to disposable target | Models DR verification without multi-terabyte storage. |
| **Policy-as-Code** | In-cluster validating webhooks | Shift-left CI CLI validation | Eliminates cluster-deadlock and OOM failure modes. |
| **Ingress & TLS** | Public DNS + Let's Encrypt / ALB | Localhost port-forwards / NodePort | Secures lab from Internet scanning; loopback only. |
