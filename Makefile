# ForgeOps Automation Makefile
# Safe, non-destructive defaults; strict target scoping

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# --- Help Target ---
.PHONY: help
help:
	@echo "ForgeOps Management Commands:"
	@echo "  make doctor         - Inspect environment, toolchain, hardware & execution profile"
	@echo "  make lint           - Lint manifests, shell scripts, and documentation"
	@echo "  make g00-evidence   - Verify G00 preflight evidence files and integrity"
	@echo "  make compose-up     - [G02] Run local Docker Compose API + DB stack"
	@echo "  make compose-down   - [G02] Stop local Docker Compose stack (preserves volumes)"
	@echo "  make cluster-create - [G06] Create Kind Kubernetes cluster"
	@echo "  make cluster-delete - [G06] Scoped Kind cluster deletion (requires CONFIRM=yes)"
	@echo "  make tf-plan        - [G05] Run Terraform plan for local Docker lab"
	@echo "  make ansible-check  - [G04] Run Ansible syntax check and dry-run on lab inventory"

# --- Doctor / Diagnostics ---
.PHONY: doctor
doctor:
	@echo "=== ForgeOps Diagnostic Preflight ==="
	@FAILURES=0; \
	WARNINGS=0; \
	if git --version >/dev/null 2>&1; then \
		echo "[PASS] Git: $$(git --version)"; \
	else \
		echo "[FAIL] Git is not installed or not in PATH"; \
		FAILURES=$$((FAILURES + 1)); \
	fi; \
	if which javac >/dev/null 2>&1; then \
		JAVA_VER=$$(javac -version 2>&1 | awk '{print $$2}'); \
		case "$$JAVA_VER" in \
			21*) echo "[PASS] Java Compiler: JDK $$JAVA_VER" ;; \
			*)   echo "[FAIL] Java Compiler: $$JAVA_VER detected, but JDK 21 LTS is required" ; \
			     FAILURES=$$((FAILURES + 1)) ;; \
		esac; \
	else \
		echo "[FAIL] Java Compiler (javac) is not installed"; \
		FAILURES=$$((FAILURES + 1)); \
	fi; \
	if docker info >/dev/null 2>&1; then \
		echo "[PASS] Docker Engine: connected ($$(docker version --format '{{.Server.Version}}' 2>/dev/null))"; \
	else \
		echo "[FAIL] Docker Engine: unreachable from this shell (check daemon / WSL integration)"; \
		FAILURES=$$((FAILURES + 1)); \
	fi; \
	if terraform version >/dev/null 2>&1; then \
		echo "[PASS] Terraform: $$(terraform version | head -n1)"; \
	else \
		echo "[WARNING] Terraform not in PATH (Required for G05, optional for G01)"; \
		WARNINGS=$$((WARNINGS + 1)); \
	fi; \
	if ansible --version >/dev/null 2>&1; then \
		echo "[PASS] Ansible: $$(ansible --version | head -n1)"; \
	else \
		echo "[WARNING] Ansible not in PATH (Required for G04, optional for G01)"; \
		WARNINGS=$$((WARNINGS + 1)); \
	fi; \
	if kubectl version --client >/dev/null 2>&1; then \
		echo "[PASS] kubectl: $$(kubectl version --client 2>/dev/null | head -n1)"; \
	else \
		echo "[WARNING] kubectl not in PATH (Required for G06, optional for G01)"; \
		WARNINGS=$$((WARNINGS + 1)); \
	fi; \
	echo "[NOT CHECKED] Helm, Kind, Argo CD, Prometheus (Deferred to G06-G14)"; \
	echo "======================================"; \
	echo "Diagnostic Summary: $$FAILURES Failure(s), $$WARNINGS Warning(s)"; \
	if [ $$FAILURES -gt 0 ]; then \
		echo "Status: FAIL - Mandatory prerequisites are missing. Resolve before proceeding."; \
		exit 1; \
	else \
		echo "Status: PASS - Mandatory prerequisites for current phase satisfied."; \
		exit 0; \
	fi

# --- Safety Guard for Destructive Targets ---
.PHONY: guard-confirm
guard-confirm:
	@if [ "$${CONFIRM:-no}" != "yes" ]; then \
		echo "ERROR: Destructive target aborted. Re-run with CONFIRM=yes to proceed."; \
		exit 1; \
	fi

.PHONY: cluster-delete
cluster-delete: guard-confirm
	@echo "Explicit Kind cluster deletion requested..."
	@if which kind >/dev/null 2>&1; then \
		kind delete cluster --name forgeops; \
	else \
		echo "Kind is not installed."; \
	fi
