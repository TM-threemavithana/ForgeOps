# Gate G14 Evidence Directory: Policy-as-Code & Encrypted Secrets Management

This directory contains verified execution logs, cluster audits, and acceptance reports for **ForgeOps Gate G14 (Advanced Platform Engineering: Policy-as-Code & Encrypted Secrets Management)**.

## Contents

- **`G14-acceptance-report.md`**: Canonical acceptance report detailing both merged PRs (#49 and #50), exact commit SHAs, the 10 Kyverno security policies, positive/negative fixture results, Helm-rendered application workload tests, SOPS dual-recipient intended-identity decryption, tool integrity verification, hard boundaries, and operational limitations.
- **`security-audit.log`**: Console execution log from `scripts/test_g14_security.py` and direct `kyverno test` runs, capturing the verification of all 10 Kyverno policies, 20 test fixtures, Helm-rendered `forgetasks-api` application workload validation, and fail-closed error handling.
- **`sops-verification.log`**: Console execution log from `scripts/test_g14_sops.py`, capturing SOPS v3.13.3 and age v1.2.1 version checks, `.sops.yaml` configuration audit, committed fixture structure verification, intended-identity decryption (Primary and Recovery), dynamic dual-recipient recovery, wrong-key refusal, missing-key refusal, MAC tamper detection, and git leak scan.
- **`pvc-continuity.txt`**: Cluster audit verifying 100% data continuity and identical baseline UIDs across all 5 pre-existing PersistentVolumeClaims (`forgeops-dev`, `forgeops-gitops-rehearsal`, and `forgeops-observability`).

## Key Summary Metrics

| Metric | Measured Value | Requirement / Target | Status |
|:---|:---|:---|:---:|
| **Kyverno Policies Implemented** | 10 policies | 10 distinct security controls | PASSED |
| **Kyverno Native Test Cases** | 20 / 20 assertions | 10 positive, 10 negative | PASSED |
| **Helm Application Workload Validation** | 9 / 9 applicable controls | Pod template passes | PASSED |
| **Tool Checksum Verification** | 3 / 3 binaries | Authentic release SHA-256 | PASSED |
| **Intended-Recipient Decryption** | Primary + Recovery | Independent recovery verified | PASSED |
| **Secret Leaks Detected (Gitleaks)** | 0 leaks (89 commits) | Zero private keys in Git | PASSED |
| **In-Cluster Admission Controllers** | 0 installed | Pure client-side/CI execution | PASSED |
| **Live Secret Modifications** | 0 mutated | Synthetic demonstration only | PASSED |
| **Protected PVC UIDs Preserved** | 5 / 5 (100%) | 100% Intact | PASSED |
| **CI Gate Jobs Passed** | 7 / 7 jobs | Full CI pipeline pass | PASSED |

