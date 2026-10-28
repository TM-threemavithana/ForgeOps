# ForgeOps Gate G12 Evidence Directory

This directory contains tangible, sanitized evidence and audit artifacts validating the completion of **Gate G12 — SRE Reliability Engineering, Load Testing, Controlled Failure Injection, and Incident Response**.

## Artifacts Inventory

- [`G12-acceptance-report.md`](file:///mnt/c/Project/ForgeOps/docs/evidence/G12/G12-acceptance-report.md): Formal SRE acceptance report documenting live metrics, SLIs/SLOs, experiment results, TTD/TTR measurements, and sign-offs.
- [`acceptance-verification.log`](file:///mnt/c/Project/ForgeOps/docs/evidence/G12/acceptance-verification.log): End-to-end execution log capturing all preflight guards, load tests, resilience experiments, and teardown verification.
- [`pvc-continuity.txt`](file:///mnt/c/Project/ForgeOps/docs/evidence/G12/pvc-continuity.txt): Exact cluster-wide PersistentVolumeClaim table proving zero storage degradation and identical baseline UID continuity.
- [`cluster-inventory.txt`](file:///mnt/c/Project/ForgeOps/docs/evidence/G12/cluster-inventory.txt): Comprehensive post-teardown cluster inventory confirming complete removal of disposable resources and health of permanent platform workloads.
- [`results/`](file:///mnt/c/Project/ForgeOps/docs/evidence/G12/results/): Machine-readable k6 summary JSON exports for all five sequential load testing scenarios:
  - `smoke-summary.json`
  - `baseline-summary.json`
  - `ramp-up-summary.json`
  - `stress-summary.json`
  - `recovery-summary.json`
