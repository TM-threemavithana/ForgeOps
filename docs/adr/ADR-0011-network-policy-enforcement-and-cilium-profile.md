# ADR-0011: Kubernetes NetworkPolicy Enforcement and Cilium Profile

**Status:** Accepted  
**Date:** 2026-10-22  
**Deciders:** ForgeOps Architecture Review

---

## Context
A major misconception in Kubernetes labs is that applying standard Kubernetes `NetworkPolicy` resources (`kind: NetworkPolicy`) to a default Kind cluster enforces network isolation.

In reality, **Kind's default CNI (kindnet) does NOT enforce NetworkPolicies**. A student or engineer who creates NetworkPolicy manifests in basic Kind and claims network isolation has performed security theater: packets continue to flow uninhibited between pods and namespaces regardless of policy rules.

Verifiable NetworkPolicy enforcement requires a policy-enforcing CNI such as Cilium or Calico.

## Options Considered
1. **Rely on Default Kindnet CNI:** Zero configuration effort, but completely fails to enforce NetworkPolicies. Unacceptable for a truthful DevSecOps portfolio.
2. **In-Place CNI Replacement on Running Cluster:** Attempting to install Cilium over an existing running Kind cluster causes network partitioning, DNS failure, and node unreadiness.
3. **Dedicated Clean Cilium Kind Profile:** Define a separate, explicit Kind cluster profile (`platform/kind/cilium.yaml`) that disables default CNI (`disableDefaultCNI: true`) and bootstraps Cilium via Helm before applying any workloads.

## Decision
Adopt a **Dedicated Clean Cilium Profile** for NetworkPolicy Verification:
1. **Truthfulness Baseline:**
   - In the initial Core profile (`platform/kind/core.yaml`), standard Kind networking is used. Documentation will explicitly state that NetworkPolicies are **not enforced** under this basic profile.
2. **Clean Cilium Profile (`platform/kind/cilium.yaml`):**
   - For Phase G11 (Security) and Capstone drills, a fresh, dedicated Kind cluster is instantiated with:
     ```yaml
     networking:
       disableDefaultCNI: true
       kubeProxyMode: "none"
     ```
   - Cilium is installed immediately via Helm as an essential cluster bootstrap step before any application or database workloads are created.
3. **Enforcement Verification Tests:**
   - Security verification mandates running both **positive** (allowed) and **negative** (blocked) network flows using disposable probe pods:
     - Allowed: `forgetasks-api` pod in `forgeops-dev` connecting to PostgreSQL on port 5432.
     - Blocked: unauthorized pod in default namespace attempting to connect to PostgreSQL in `forgeops-dev` (must timeout/drop).
     - Blocked: cross-namespace traffic between `forgeops-dev` and `forgeops-staging`.

## Consequences & Trade-offs
### Positive:
- **Authentic Security Enforcement:** NetworkPolicies are genuinely enforced by eBPF packet filtering in the Linux kernel.
- **Accurate Claims:** The portfolio truthfully distinguishes between declaring policy manifests and actually enforcing them.

### Negative / Limitations:
- Running Cilium requires additional memory (~500 MB RAM for Cilium agents) and eBPF kernel support in WSL2.
- Cannot be applied in-place to the Core cluster; requires a fresh cluster bootstrap.

## Verification Tests
- `cilium status` confirms eBPF datapath is operational and nodes are managed.
- A curl probe from a rogue pod to `forgetasks-db:5432` times out with 100% packet loss under active NetworkPolicy.
- Legitimate API calls succeed with 0% packet loss.

## Reconsideration Triggers
- If WSL2 kernel lacks required eBPF capabilities, Calico or Antrea will be evaluated as an alternative policy-enforcing CNI.
