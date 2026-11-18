# ForgeOps Gate G09.3 — Application Security & DAST Readiness Report

**Milestone:** G09.3 — Application Security & DAST  
**Repository:** `TM-threemavithana/ForgeOps`  
**Feature Branch:** `feature/g09-application-security` (stacked on `feature/g09-iac-container-security`)  
**Base Commit:** `d796d26`  
**Execution Environment:** Windows 11 / WSL2 (Ubuntu), Docker Desktop, kind cluster (`kind-forgeops`), GitHub Actions (`ubuntu-latest`)  
**Status:** READY FOR REVIEW (Stacked PR targeting `feature/g09-iac-container-security`)

---

## 1. Executive Summary & Scope

Gate **G09.3 — Application Security & DAST** establishes application-level security hardening, developer-side secret prevention, and reproducible Dynamic Application Security Testing (DAST) for the ForgeOps platform.

### Core Deliverables Implemented:
1. **Developer-Side Secret Prevention (Pre-Commit Gitleaks Hook)**:
   - Configured reproducible Git hook setup in `.githooks/pre-commit` managed via `git config core.hooksPath .githooks`.
   - Provided cross-platform automated installer scripts: [`scripts/setup-pre-commit.sh`](file:///c:/Project/ForgeOps/scripts/setup-pre-commit.sh) (WSL2/Linux) and [`scripts/setup-pre-commit.ps1`](file:///c:/Project/ForgeOps/scripts/setup-pre-commit.ps1) (Windows PowerShell).
   - Utilizes Gitleaks v8.24.3 supported staged scanning command interface (`gitleaks git --staged --verbose --redact` with fallback to `protect --staged`).
   - Verified that ordinary commits succeed cleanly, staged synthetic secrets are rejected, and missing scanner executables fail closed with exit status `1`.
2. **Application Security Hardening & CSRF Defense ([`apps/forgetasks-api`](file:///c:/Project/ForgeOps/apps/forgetasks-api))**:
   - Explicit HTTP Security Headers in [`SecurityConfig.java`](file:///c:/Project/ForgeOps/apps/forgetasks-api/src/main/java/com/forgeops/forgetasks/security/SecurityConfig.java):
     - `Content-Security-Policy`: `default-src 'self'; frame-ancestors 'none'; object-src 'none'; base-uri 'self'; form-action 'self'`
     - `X-Frame-Options`: `DENY`
     - `X-Content-Type-Options`: `nosniff`
     - `Referrer-Policy`: `strict-origin-when-cross-origin`
     - `Permissions-Policy`: `geolocation=(), camera=(), microphone=(), payment=()`
   - Controlled Cross-Origin Resource Sharing (CORS):
     - Configured `CorsConfigurationSource` restricting allowed origins to trusted local development patterns (`http://localhost:[*]`, `https://localhost:[*]`, `http://127.0.0.1:[*]`, `https://forgeops.local`).
     - Restricted allowed methods (`GET`, `POST`, `PUT`, `DELETE`, `OPTIONS`) and allowed headers (`Authorization`, `Content-Type`, `If-Match`, `X-Correlation-ID`, `Accept`).
     - Exposed headers (`ETag`, `Location`, `X-Correlation-ID`) with credentials enabled.
   - Fail-Closed CSRF Protection & Built-in Token Architecture:
     - Configured `CookieCsrfTokenRepository.withHttpOnlyFalse()` and `CsrfTokenRequestAttributeHandler`.
     - Omission of `WWW-Authenticate: Basic` header in `problemAuthenticationEntryPoint()` prevents browsers from prompting or caching HTTP Basic credentials in the user agent vault.
     - Strict `SessionCreationPolicy.STATELESS` ensures zero ambient session cookies (`JSESSIONID`).
     - **Fail-Closed State-Changing Protection**: Removed all heuristic header bypasses. Missing browser-context headers (`Origin`, `Referer`, `Cookie`, `Sec-Fetch-*`) are no longer assumed to prove non-browser origin. Every state-changing operation (`POST`, `PUT`, `PATCH`, `DELETE`) on protected business endpoints strictly enforces CSRF token validation, regardless of whether `Authorization: Basic` credentials are provided.
     - **API Client Token Discovery**: Added public endpoint `GET /api/v1/csrf` ([`CsrfController.java`](file:///c:/Project/ForgeOps/apps/forgetasks-api/src/main/java/com/forgeops/forgetasks/security/CsrfController.java)) and registered `CsrfCookieFilter` (`OncePerRequestFilter` placed after `BasicAuthenticationFilter`). This allows legitimate API clients and SPAs to fetch anti-CSRF token metadata (`token`, `headerName`, `parameterName`) and receive the `XSRF-TOKEN` cookie via standard HTTP requests.
     - **Double Submit Cookie Validation**: State-changing requests submit the token in the `X-XSRF-TOKEN` header alongside the `XSRF-TOKEN` cookie, verified by Spring Security's built-in `CsrfFilter`.
     - **Strict Exemptions**: Only public unauthenticated registration (`POST /api/v1/accounts`) and strictly read-only observability probes (`GET /actuator/**`) are exempted from CSRF requirements. All state-changing operations (`POST`, `PUT`, `PATCH`, `DELETE`) on `/actuator/**` and `/api/v1/**` strictly enforce CSRF protection.
     - **Information Disclosure Elimination in 403 Problem Details**: In `problemAccessDeniedHandler()`, replaced dynamic exception class name and message interpolation (`accessDeniedException.getClass().getSimpleName() + ": " + accessDeniedException.getMessage()`) with a constant, client-safe detail message (`"You do not possess the required permissions to access this resource."`). This eliminates internal Java class name and framework stack leakage on access denials and CSRF failures while preserving RFC 7807 structure, correlation IDs, and timestamps.
3. **Application Security Integration Testing ([`ApplicationSecurityIntegrationTest.java`](file:///c:/Project/ForgeOps/apps/forgetasks-api/src/test/java/com/forgeops/forgetasks/ApplicationSecurityIntegrationTest.java))**:
   - Verified security headers presence and policy directives.
   - Verified CORS preflight acceptance for allowed origins and rejection for unauthorized origins.
   - Verified CSRF rejection (403 Forbidden) on state-changing requests lacking API authorization or CSRF tokens, and verified token acceptance.
   - Added regression test `shouldRejectAuthenticatedBasicRequestLackingBrowserHeadersAndCsrfToken`: confirms that authenticated Basic requests lacking `Origin`, `Referer`, cookies, and `Sec-Fetch-*` headers are strictly rejected with `403 Forbidden` if they lack a CSRF token.
   - Added regression test `shouldAllowApiClientToObtainAndSubmitCsrfToken`: verifies end-to-end API client workflow where a client retrieves the token via `GET /api/v1/csrf` and submits `X-XSRF-TOKEN` and `XSRF-TOKEN` cookie on `POST /api/v1/projects` with `Authorization: Basic`, succeeding with `201 Created`.
   - Added regression test `shouldEnforceCsrfOnStateChangingActuatorRequests`: confirms that state-changing requests (`POST /actuator/loggers`) without CSRF tokens are rejected with `403 Forbidden` and do not leak exception class names.
   - Retained regression test `shouldRejectBrowserStyleAuthenticatedRequestLackingCsrfToken`: confirms browser-credential replay rejection.
   - Retained companion test `shouldAcceptBrowserStyleAuthenticatedRequestWithValidCsrfToken`: confirms browser request with valid CSRF token succeeds.
   - Updated core mutating integration tests (`ProjectApiIntegrationTest`, `TaskApiIntegrationTest`, and BOLA/IDOR test) to supply valid CSRF tokens (`.with(csrf())`).
   - Verified Broken Object-Level Authorization (BOLA/IDOR) tenant isolation: User B receives 404 with RFC 7807 problem details when attempting GET, PATCH, or DELETE on User A's projects and tasks.
   - Verified input validation against XSS script tags, malformed usernames, and short passwords.
   - Verified information disclosure prevention on malformed UUID paths (zero stack trace or internal package leakage).
4. **OWASP ZAP Dynamic Application Security Testing (DAST) in Safe Baseline Mode**:
   - Authored complete OpenAPI 3.0.3 specification [`security/dast/zap/openapi.yaml`](file:///c:/Project/ForgeOps/security/dast/zap/openapi.yaml) defining all API paths and methods (`/api/v1/accounts`, `/api/v1/projects`, `/api/v1/tasks`, `/actuator/**`).
   - Configured custom ZAP baseline/API rules file [`security/dast/zap/zap-rules.conf`](file:///c:/Project/ForgeOps/security/dast/zap/zap-rules.conf) mapping threat model risks to actions (FAIL on high-risk missing headers/misconfigurations, IGNORE on stateless REST anti-CSRF).
   - Created reproducible runner script [`scripts/run_dast_zap.sh`](file:///c:/Project/ForgeOps/scripts/run_dast_zap.sh) targeting strictly ephemeral test containers on isolated bridge network `zap-net` using `zap-api-scan.py` with Safe Mode (`-S`) enabled.
   - Safe Mode (`-S`) enforces passive-only baseline inspection, avoiding destructive payload injection.
   - Infrastructure Isolation: Scans run only against disposable containers (`zap-test-app` and `zap-test-db`), never touching production or kind cluster workloads.
   - Endpoint Coverage Truth: OpenAPI 3.0.3 provides route exploration for all paths. Public endpoints (`/api/v1/accounts`, `/actuator/**`) are exercised unauthenticated; protected routes (`/api/v1/projects/**`, `/api/v1/tasks/**`) are inspected in their unauthenticated boundary condition (verifying RFC 7807 Problem Details and security headers on 401). We do not claim 100% authenticated state-machine coverage by automated ZAP crawl (which is verified via integration tests).
   - Pinned official ZAP container: `ghcr.io/zaproxy/zaproxy:2.16.0@sha256:391f66efa53b30de40d4a1c6e28146477263552fc828bc7613c9cd11a2949908`.
   - Created synthetic compliant, insecure, malformed, empty, and incomplete fixtures to prove automated risk-based gate enforcement.
5. **CI/CD Integration ([`.github/workflows/ci.yml`](file:///c:/Project/ForgeOps/.github/workflows/ci.yml))**:
   - Added `dast-zap-scan` job executing ephemeral PostgreSQL + ForgeTasks API + ZAP API scanner in safe mode (`-S`) with OpenAPI route discovery.
   - Enforces report integrity (non-empty, valid JSON, analyzed target hosts) and zero HIGH / MEDIUM DAST findings.
   - Uploads HTML, Markdown, and JSON reports as build artifacts.
   - Updated `ci-gate` aggregator to require `dast-zap-scan`.

---

## 2. API Threat Model & Risk Assessment

| Threat / Risk Vector | OWASP API Top 10 | Existing State | Hardening Applied in G09.3 | Verification Mechanism |
| :--- | :--- | :--- | :--- | :--- |
| **Accidental Secret Commits** | CI/CD Supply Chain | GitHub Actions Gitleaks scanned post-push, but developers could commit secrets locally. | Pre-commit hook in `.githooks/pre-commit` scanning staged changes with Gitleaks v8.24.3, failing closed when binary is missing. | `test_precommit_hook_and_secret_rejection` in `scripts/test_g09_security.py`. |
| **Cross-Site Request Forgery & Browser Credential Replay** | API8: Security Misconfiguration | CSRF was disabled; browser contexts could theoretically replay cached credentials or ambient state. | Omitted `WWW-Authenticate: Basic` to prevent user-agent caching; implemented fail-closed `CookieCsrfTokenRepository` enforcing CSRF for all mutating operations regardless of Basic Auth or missing headers; added `GET /api/v1/csrf` and `CsrfCookieFilter` for API clients. | `shouldRejectStateChangingRequestWithoutCsrfTokenWhenLackingApiAuthorization`, `shouldRejectAuthenticatedBasicRequestLackingBrowserHeadersAndCsrfToken`, `shouldAllowApiClientToObtainAndSubmitCsrfToken`, `shouldRejectBrowserStyleAuthenticatedRequestLackingCsrfToken`, and `shouldAcceptBrowserStyleAuthenticatedRequestWithValidCsrfToken` in `ApplicationSecurityIntegrationTest.java`. |
| **Missing Security Headers** | API8: Security Misconfiguration | Relied on default Spring Security headers without explicit CSP, Referrer, or Permissions policy. | Added explicit CSP, Frame-Options DENY, Referrer-Policy, and Permissions-Policy. | `shouldEnforceSecurityHeaders` in `ApplicationSecurityIntegrationTest.java` & ZAP rule 10038/10021. |
| **Uncontrolled CORS** | API8: Security Misconfiguration | No explicit CORS filter; default behavior varied across reverse proxies. | Configured `CorsConfigurationSource` bean with origin patterns restricted to trusted dev/local origins. | `shouldEnforceControlledCorsForAllowedOrigin` and `shouldRejectCorsForDisallowedOrigin`. |
| **Broken Object-Level Authorization (BOLA/IDOR)** | API1: Broken Object Level Auth | Enforced in domain logic via `findByIdAndOwner`, but lacked dedicated integration test coverage. | Created multi-tenant security integration tests verifying cross-tenant GET/PATCH/DELETE isolation. | `shouldEnforceObjectLevelAccessControl_BOLA_IDOR_Isolation` in `ApplicationSecurityIntegrationTest.java`. |
| **Information Disclosure** | API8: Security Misconfiguration | Handled known exceptions, but malformed UUIDs or unhandled errors could expose framework traces. | Validated GlobalExceptionHandler RFC 7807 problem details with zero stack trace leakage. | `shouldPreventInformationDisclosureOnMalformedInputs`. |
| **Dynamic Runtime Vulnerabilities & Incomplete DAST** | All OWASP Top 10 | Web crawlers only hit root HTML; static analysis alone left dynamic runtime risks uninspected. | Authored OpenAPI 3.0.3 specification (`openapi.yaml`) covering all routes; integrated `zap-api-scan.py` in Safe/Passive Mode (`-S`) against ephemeral containers, with fail-closed report integrity validation. | `dast-zap-scan` job in CI, `test_zap_report_evaluation_and_negative_rejection`, and `scripts/run_dast_zap.sh`. |

---

## 3. Inventory of Files Modified & Added

| File Path | Status | Purpose |
| :--- | :---: | :--- |
| [`.githooks/pre-commit`](file:///c:/Project/ForgeOps/.githooks/pre-commit) | Added | Pre-commit Git hook executing Gitleaks staged secret scanning with fail-closed behavior. |
| [`scripts/setup-pre-commit.sh`](file:///c:/Project/ForgeOps/scripts/setup-pre-commit.sh) | Added | POSIX/WSL2 installer configuring `core.hooksPath` and installing pinned Gitleaks binary. |
| [`scripts/setup-pre-commit.ps1`](file:///c:/Project/ForgeOps/scripts/setup-pre-commit.ps1) | Added | Windows PowerShell setup script configuring Git pre-commit hooks. |
| [`apps/forgetasks-api/src/main/java/com/forgeops/forgetasks/security/SecurityConfig.java`](file:///c:/Project/ForgeOps/apps/forgetasks-api/src/main/java/com/forgeops/forgetasks/security/SecurityConfig.java) | Modified | Added explicit security headers (CSP, FrameOptions, Referrer, Permissions), CORS bean, and fail-closed CSRF protection with CsrfCookieFilter. |
| [`apps/forgetasks-api/src/main/java/com/forgeops/forgetasks/security/CsrfController.java`](file:///c:/Project/ForgeOps/apps/forgetasks-api/src/main/java/com/forgeops/forgetasks/security/CsrfController.java) | Added | Public anti-CSRF token endpoint (`GET /api/v1/csrf`) providing token metadata and cookie initialization for API clients and SPAs. |
| [`apps/forgetasks-api/src/test/java/com/forgeops/forgetasks/ApplicationSecurityIntegrationTest.java`](file:///c:/Project/ForgeOps/apps/forgetasks-api/src/test/java/com/forgeops/forgetasks/ApplicationSecurityIntegrationTest.java) | Added | Security integration tests: headers, CORS, CSRF rejection/acceptance, BOLA/IDOR, input validation, info disclosure. |
| [`security/dast/zap/openapi.yaml`](file:///c:/Project/ForgeOps/security/dast/zap/openapi.yaml) | Added | Complete OpenAPI 3.0.3 specification covering all ForgeTasks API endpoints for dynamic security scanning. |
| [`security/dast/zap/zap-rules.conf`](file:///c:/Project/ForgeOps/security/dast/zap/zap-rules.conf) | Added | OWASP ZAP baseline/API rules configuration and risk action mappings. |
| [`security/dast/zap/fixtures/report-pass.json`](file:///c:/Project/ForgeOps/security/dast/zap/fixtures/report-pass.json) | Added | Synthetic compliant DAST report fixture for positive gate evaluation. |
| [`security/dast/zap/fixtures/report-fail.json`](file:///c:/Project/ForgeOps/security/dast/zap/fixtures/report-fail.json) | Added | Synthetic insecure DAST report fixture (High CSP alert) for negative gate evaluation. |
| [`security/dast/zap/fixtures/report-malformed.json`](file:///c:/Project/ForgeOps/security/dast/zap/fixtures/report-malformed.json) | Added | Synthetic malformed JSON DAST fixture to verify fail-closed parser handling. |
| [`security/dast/zap/fixtures/report-empty.json`](file:///c:/Project/ForgeOps/security/dast/zap/fixtures/report-empty.json) | Added | Synthetic empty (0 bytes) DAST fixture to verify fail-closed empty file handling. |
| [`security/dast/zap/fixtures/report-incomplete.json`](file:///c:/Project/ForgeOps/security/dast/zap/fixtures/report-incomplete.json) | Added | Synthetic incomplete (`site: []`) DAST fixture to verify fail-closed completeness check. |
| [`scripts/run_dast_zap.sh`](file:///c:/Project/ForgeOps/scripts/run_dast_zap.sh) | Added | Ephemeral local/CI runner script for OWASP ZAP API container scan with OpenAPI specification. |
| [`scripts/test_g09_security.py`](file:///c:/Project/ForgeOps/scripts/test_g09_security.py) | Modified | Extended security test suite to 16 automated checks covering CSRF, Gitleaks fail-closed, and ZAP OpenAPI report integrity. |
| [`.github/workflows/ci.yml`](file:///c:/Project/ForgeOps/.github/workflows/ci.yml) | Modified | Added `dast-zap-scan` job with OpenAPI mapping, report integrity verification, pinned actions/containers, and updated `ci-gate`. |
| [`apps/forgetasks-api/src/main/resources/application.yml`](file:///c:/Project/ForgeOps/apps/forgetasks-api/src/main/resources/application.yml) | Modified | Configured OTLP tracing endpoint default to prevent container startup failure in standalone/ephemeral test environments. |
| [`docs/evidence/G09/g09-3-readiness.md`](file:///c:/Project/ForgeOps/docs/evidence/G09/g09-3-readiness.md) | Added | This readiness, threat model, audit, and verification report. |

---

## 4. Test Execution & Evidence

### 4.1 Gate G09 DevSecOps Automated Suite (`test_g09_security.py`)
```text
===================================================================
 ForgeOps Gate G09 DevSecOps Security & Action Pinning Test Suite
===================================================================
--> Test 1: Verifying full 40-character commit SHA pinning for all GitHub Actions...
  [PASS] Verified 53 action references across workflows; 100% pinned to 40-char SHAs with version comments.
--> Test 2: Auditing workflow permissions and least-privilege security boundaries...
  [PASS] Least-privilege permissions and workflow trust boundaries verified.
--> Test 3: Validating Semgrep SAST ruleset syntax and schema...
  [PASS] All 5 SAST rules validated with schema, CWE, and OWASP mapping.
--> Test 4: Running Semgrep positive baseline compliance checks...
  [PASS] Compliant pass-sample.java passed with 0 findings.
  [PASS] Production codebase clean: 0 blocking SAST findings.
--> Test 5: Running Semgrep synthetic negative rejection tests...
  [PASS] Synthetic rejection verified for fail-sqli.java (triggered forgeops.java.security.sql-injection).
  [PASS] Synthetic rejection verified for fail-command-injection.java (triggered forgeops.java.security.command-injection).
  [PASS] Synthetic rejection verified for fail-weak-crypto.java (triggered forgeops.java.security.weak-crypto).
  [PASS] Synthetic rejection verified for fail-path-traversal.java (triggered forgeops.java.security.path-traversal).
--> Test 6: Verifying dependency scanner synthetic negative fixture isolation...
  [PASS] Dependency test fixture correctly isolated from production application pom.xml.
--> Test 7: Running Checkov IaC security scan on Terraform modules...
  [PASS] Production Terraform modules passed Checkov security scan with 0 blocking failures.
--> Test 8: Verifying Checkov synthetic negative rejection on insecure fixture...
  [PASS] Checkov correctly detected insecure Terraform configuration and enforced non-zero exit code.
--> Test 9: Running Hadolint linter on production application Dockerfile...
  [PASS] Production Dockerfile passed Hadolint with 0 warnings or errors.
--> Test 10: Verifying Hadolint synthetic negative rejection on insecure Dockerfile...
  [PASS] Hadolint correctly detected insecure Dockerfile practices and enforced non-zero exit code.
--> Test 11: Verifying immutable base image digest pinning in production Dockerfile...
  [PASS] All 2 multi-stage base images pinned to verified immutable SHA-256 digests.
--> Test 12: Auditing Dependabot automated dependency configuration...
  [PASS] Dependabot configuration verified for ecosystems: ['docker', 'github-actions', 'maven'].
--> Test 13: Verifying Gitleaks pre-commit hook installation and synthetic secret rejection...
  [PASS] Pre-commit hook verified: clean commits permitted, staged synthetic secrets blocked.
--> Test 14: Validating OWASP ZAP baseline rules configuration and risk actions...
  [PASS] ZAP rules configuration validated (16 active rule mappings).
--> Test 15: Verifying OWASP ZAP DAST report evaluation and synthetic rejection...
  [PASS] Compliant ZAP report passes DAST gate (0 High/Medium); insecure fixture triggers gate rejection.
--> Test 16: Auditing application security controls, HTTP headers & CORS configuration...
  [PASS] Application security configuration, security headers, CORS, and BOLA/IDOR tests verified.
===================================================================
 [PASS] All Gate G09 security engineering checks completed successfully!
===================================================================
```

### 4.2 Non-Regression Verification Suites (G12, G13, G14)
- **Gate G12 SRE Reliability & Hardening**: 5/5 test suites passed.
- **Gate G13 Disaster Recovery & Database Rehearsal**: 10/10 test suites passed.
- **Gate G14 Kyverno Policy-as-Code**: 7/7 test suites passed.
- **Gate G14 SOPS + age Encrypted Secrets**: 6/6 test suites passed.

### 4.3 Remote CI Verification (GitHub Actions Run 44230769615 on PR #60)
All 12 CI jobs executed and passed 100% on Pull Request [#60](https://github.com/TM-threemavithana/ForgeOps/pull/60) (Commit: [`cb66b3d`](https://github.com/TM-threemavithana/ForgeOps/commit/cb66b3d)):
- **Build and Test (Java 21)**: `pass` (58s) — Surefire unit/integration tests and JaCoCo line/branch coverage gates (including 12 AppSec tests verifying headers, CORS, fail-closed CSRF, and BOLA/IDOR).
- **Docker Build Validation**: `pass` (54s) — Multi-stage build and non-root execution verification.
- **Secret Leak Detection (Gitleaks)**: `pass` (6s) — Clean scan across full Git history.
- **Trivy Security Scan**: `pass` (1m41s) — Zero HIGH/CRITICAL vulnerabilities in container filesystem.
- **Maven Dependency Scan (Trivy)**: `pass` (30s) — Zero vulnerable library dependencies.
- **Semgrep SAST Security Scan**: `pass` (1m16s) — Zero security violations across application source.
- **Checkov IaC Security Scan**: `pass` (38s) — Zero blocking findings on Terraform modules.
- **Hadolint Dockerfile Linter**: `pass` (6s) — Strict container best-practice compliance.
- **SRE & DR Hardening Validation**: `pass` (24s) — G12 and G13 automation suites.
- **Security Policy & Secrets Validation**: `pass` (25s) — Kyverno CLI and SOPS/age decryption test suites.
- **OWASP ZAP Baseline DAST Scan**: `pass` (1m58s) — Ephemeral PostgreSQL + API + ZAP container scan in Safe Mode (`-S`) with OpenAPI 3.0.3 route discovery, fail-closed report integrity validation, and 0 HIGH/MEDIUM alerts.
- **CI Gate**: `pass` (2s) — Aggregated status gate permitting pull request merge.

---

## 5. OWASP ZAP DAST Findings & Remediation Decisions

| Rule ID | Alert Description | ZAP Risk Code | Action in ForgeOps | Technical Justification |
| :---: | :--- | :---: | :---: | :--- |
| `10020` | Anti-CSRF Tokens Check | Medium | `IGNORE` | ForgeTasks API enforces fail-closed double-submit cookie CSRF validation (`CookieCsrfTokenRepository` with `GET /api/v1/csrf`) for all state-changing operations across browser clients and SPAs. In ZAP passive API baseline crawling, unauthenticated GET endpoints do not require anti-CSRF tokens, and ambient browser sessions (`JSESSIONID`) are disabled (`SessionCreationPolicy.STATELESS`), with `WWW-Authenticate: Basic` suppressed to prevent browser credential caching. Active CSRF defense is verified by `ApplicationSecurityIntegrationTest`. |
| `10021` | X-Content-Type-Options Header Missing | Low | `FAIL` | Enforced `nosniff` via Spring Security header writer. Prevents MIME-sniffing attacks. |
| `10038` | Content Security Policy (CSP) Header Not Set | Medium | `FAIL` | Enforced strict `default-src 'self'; frame-ancestors 'none'; object-src 'none'` in `SecurityConfig.java`. Mitigates XSS and UI redress. |
| `10049` | Storable and Cacheable Content | Low | `IGNORE` | API responses include resource-specific cache semantics (e.g. ETag and versioning). Static global no-cache on all endpoints conflicts with HTTP conditional validation. |
| `10063` | Permissions-Policy Header Not Set | Low | `WARN` | Enforced explicit `geolocation=(), camera=(), microphone=(), payment=()` policy. |
| `10096` | Timestamp Disclosure - Unix / RFC | Low | `IGNORE` | RFC 7807 problem details deliberately include an ISO-8601 `timestamp` property for client debugging and correlation. |
| `10202` | Absence of Anti-clickjacking Header | Medium | `FAIL` | Enforced `X-Frame-Options: DENY` and CSP `frame-ancestors 'none'`. Protects REST API error/actuator pages from iframe embedding. |

---

## 6. Pre-Commit Hook Installation, Usage & Bypass Notice

### Installation
- **Linux / WSL2**:
  ```bash
  chmod +x scripts/setup-pre-commit.sh
  ./scripts/setup-pre-commit.sh
  ```
- **Windows PowerShell**:
  ```powershell
  .\scripts\setup-pre-commit.ps1
  ```

### Usage
Once installed, `git commit` automatically invokes `.githooks/pre-commit`, running `gitleaks git --staged --verbose --redact` (with fallback to `protect --staged`).
- If staged files contain credentials (API keys, private keys, tokens), the commit is blocked with an actionable remediation guide.
- If no secrets are staged, the commit proceeds without delay.

### Bypass Risks & Limitations
1. Developers can bypass client-side hooks using `git commit --no-verify` or by not configuring `core.hooksPath`.
2. **Defense-in-Depth**: Because client-side hooks cannot be forcibly guaranteed across all contributor workstations, ForgeOps enforces mandatory server-side Gitleaks scanning (`gitleaks-scan` job) in GitHub Actions CI as a required status check on every pull request.

---

## 7. Known Limitations & Operating Notes

1. **Local Testcontainers Execution**: Integration tests running against PostgreSQL Testcontainers require an active Docker engine. In environments where Docker Desktop is stopped, unit and static security tests execute cleanly, while full integration tests run natively in CI (`ubuntu-latest`).
2. **Local DAST Execution**: [`scripts/run_dast_zap.sh`](file:///c:/Project/ForgeOps/scripts/run_dast_zap.sh) safely checks for Docker availability. If Docker is offline, it issues an informative warning without throwing errors or altering persistent state.
3. **OWASP ZAP DAST Scanning Behavior & Scope**:
   - **Passive-Only Safe Mode (`-S`)**: The scan executes in safe mode (`-S`), disabling active payload injection while passively analyzing HTTP security headers, cookie flags, and information disclosures.
   - **Infrastructure Isolation**: All DAST tests execute strictly against isolated ephemeral containers (`zap-test-app` with disposable PostgreSQL on bridge network `zap-net` / `zap-test-net`), completely decoupled from kind cluster nodes and production environments.
   - **Coverage Truth**: OpenAPI 3.0.3 discovery exercises all route schemas. Public endpoints (`/api/v1/accounts`, `/actuator/**`) are inspected in active runtime paths, while protected endpoints (`/api/v1/projects/**`, `/api/v1/tasks/**`) are inspected at their unauthenticated perimeter (validating RFC 7807 Problem Details and security headers on 401). We do not claim 100% authenticated state-machine coverage by automated ZAP crawl; business logic and tenant isolation are verified by the 10 automated test cases in `ApplicationSecurityIntegrationTest.java`.

---

## 8. Rollback Instructions

If Gate G09.3 needs to be reverted:
1. Switch back to base branch `feature/g09-iac-container-security`:
   ```bash
   git checkout feature/g09-iac-container-security
   git branch -D feature/g09-application-security
   ```
2. Reset local Git hook path if desired:
   ```bash
   git config --unset core.hooksPath
   ```
3. Delete the remote branch if pushed:
   ```bash
   git push origin --delete feature/g09-application-security
   ```
4. Base G09.1 and G09.2 capabilities, cluster workloads, and persistent volumes remain untouched.
