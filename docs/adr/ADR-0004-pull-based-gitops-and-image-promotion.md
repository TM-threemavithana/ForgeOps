# ADR-0004: Pull-Based GitOps and Immutable Digest Image Promotion

**Status:** Accepted  
**Date:** 2026-10-22  
**Deciders:** ForgeOps Architecture Review

---

## Context
Deploying from continuous integration pipelines directly to a local development machine requires either exposing the local machine to the public Internet (via ngrok, Cloudflare tunnels, or dynamic DNS) or hosting self-hosted GitHub Actions runners on the laptop with persistent root privileges. Both approaches introduce severe security risks and firewall vulnerabilities.

Furthermore, deploying mutable tags (such as `:latest` or `:dev`) prevents deterministic rollbacks and breaks auditability.

## Options Considered
1. **Push-Based Deployment from GitHub Actions:** Hosted runners run `kubectl apply` against an exposed local Kubernetes endpoint. Rejected due to severe host security exposure.
2. **Local Self-Hosted GitHub Runner:** Runner executes on Windows/WSL2 with cluster access. Rejected to prevent untrusted PR workflows from gaining shell execution on the host machine.
3. **Pull-Based GitOps with Immutable Digests via Argo CD:** Argo CD runs inside Kind, polls the Git repository over outbound HTTPS, and reconciles manifests. Workload updates occur via reviewed Git Pull Requests modifying the immutable `sha256:...` container digest.

## Decision
Adopt **Pull-Based GitOps with Argo CD** and **Immutable Digest Promotion**:
1. **Outbound-Only Connectivity:** Argo CD initiates outbound TLS connections to GitHub to pull desired state. No inbound ports are opened on the host firewall.
2. **Immutable Image Digests:** Builds published to GitHub Container Registry (GHCR) produce an immutable `sha256:...` digest. Mutable tags (`:latest`) are forbidden in Helm values.
3. **PR-Driven Promotion:**
   - On merge to `main`, CI publishes the image and automatically proposes a PR updating `values-dev.yaml` with the new image digest.
   - Merging the PR triggers Argo CD to reconcile `forgeops-dev`.
   - Promoting to `staging` requires a separate reviewed PR updating `values-staging.yaml`.

## Consequences & Trade-offs
### Positive:
- **Zero Inbound Attack Surface:** The laptop and Kind cluster remain completely hidden from the public Internet.
- **Deterministic Auditing:** Git commit history represents an exact record of every deployed artifact version.
- **Clean Separation of Concerns:** CI builds and tests; GitOps controller reconciles runtime state.

### Negative / Limitations:
- Latency between merging an image update PR and Argo CD synchronizing (default poll interval is 3 minutes, unless manually triggered via UI/CLI).
- Promotion between `dev` and `staging` requires an explicit Git commit/PR rather than an automated push script.

## Verification Tests
- External port scanning verifies zero open inbound listening ports on the external network adapter.
- Argo CD synchronizes `forgeops-dev` within 180 seconds of merging an image digest commit to `main`.
- Reverting a desired-state Git commit causes Argo CD to immediately revert the running container to the previous image digest.

## Reconsideration Triggers
- Transitioning to Webhook-driven synchronization if an internal Git forge (e.g., Gitea) is deployed locally inside Kind.
