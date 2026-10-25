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
	@echo "  make build-api      - [G01] Build ForgeTasks API package"
	@echo "  make test-api       - [G01] Run ForgeTasks API unit & integration tests"
	@echo "  make compose-up     - [G02] Run local Docker Compose API + DB stack"
	@echo "  make compose-down   - [G02] Stop local Docker Compose stack (preserves volumes)"
	@echo "  make ci-local       - [G03] Run full local CI gate (build, test, Docker, Trivy)"
	@echo "  make trivy-scan     - [G03] Run Trivy vulnerability scan on local Docker image"
	@echo "  make actionlint     - [G03] Lint GitHub Actions workflow YAML files"
	@echo "  make cluster-create - [G06] Create Kind Kubernetes cluster (single control plane)"
	@echo "  make cluster-create-dry-run - [G06] Run preflight checks without creating cluster"
	@echo "  make cluster-delete - [G06] Scoped Kind cluster deletion (requires CONFIRM=yes)"
	@echo "  make cluster-status - [G06] Inspect Kind cluster node and pod status"
	@echo "  make cluster-load-images - [G06] Load local Docker images into Kind node offline"
	@echo "  make k8s-dev-deploy - [G06] Deploy vanilla Dev manifests (namespaces, DB, API)"
	@echo "  make k8s-dev-verify - [G06] Run read-only A-601 health verification (non-mutating)"
	@echo "  make k8s-dev-smoke-write - [G06] Run application database write smoke test"
	@echo "  make k8s-dev-drill-persistence - [G06] Run DB restart recovery drill (requires CONFIRM=yes)"
	@echo "  make k8s-dev-drill-a602 - [G06] Run stateless pod kill recovery drill (requires CONFIRM=yes)"
	@echo "  make k8s-dev-teardown - [G06] Teardown Dev manifests cleanly"
	@echo "  make tf-init        - [G05] Initialize Terraform provider with protected local state"
	@echo "  make tf-fmt         - [G05] Check Terraform formatting"
	@echo "  make tf-validate    - [G05] Validate Terraform configuration and provider schema"
	@echo "  make tf-providers   - [G05] List resolved Terraform providers"
	@echo "  make tf-plan        - [G05] Run speculative in-memory Terraform plan (no files created)"
	@echo "  make tf-plan-save   - [G05] Save protected executable plan outside repository"
	@echo "  make ansible-check  - [G04] Run Ansible syntax check and dry-run on lab inventory"


# --- ForgeTasks API Build & Test Targets ---
.PHONY: build-api test-api
build-api:
	@cd apps/forgetasks-api && ./mvnw clean package -DskipTests

test-api:
	@cd apps/forgetasks-api && ./mvnw clean verify

# --- G03 CI Targets ---
.PHONY: ci-local trivy-scan actionlint
ci-local:
	@./scripts/verify_g03_local.sh

trivy-scan:
	@if ! command -v trivy > /dev/null 2>&1; then \
		echo "[FAIL] trivy not installed. See https://aquasecurity.github.io/trivy/latest/getting-started/installation/"; \
		exit 1; \
	fi
	@IMAGE_TAG="forgetasks-api:trivy-scan-local-$$(date +%s)"; \
	 docker build -t "$$IMAGE_TAG" apps/forgetasks-api/ && \
	 trivy image --exit-code 1 --ignore-unfixed --vuln-type os,library \
	             --scanners vuln --severity CRITICAL,HIGH "$$IMAGE_TAG" && \
	 docker rmi "$$IMAGE_TAG" 2>/dev/null || true

actionlint:
	@if command -v actionlint > /dev/null 2>&1; then \
		echo "Linting GitHub Actions workflow files..."; \
		actionlint .github/workflows/*.yml && echo "[PASS] All workflow files valid"; \
	else \
		echo "[WARN] actionlint not installed. Install: https://github.com/rhysd/actionlint"; \
	fi

# --- G04 Ansible Targets ---
.PHONY: ansible-check
ansible-check:
	@./scripts/verify_g04_ansible_syntax.sh

# --- G05 Terraform Targets ---
TF_DIR := infrastructure/terraform/local-docker-lab
TF_STATE_DIR ?= $(HOME)/.local/state/forgeops/g05
TF_PLAN_FILE ?= $(TF_STATE_DIR)/forgeops-g05.tfplan

.PHONY: tf-init tf-fmt tf-validate tf-providers tf-plan tf-plan-save
tf-init:
	@echo "Initializing G05 Terraform lab with protected local state backend..."
	@mkdir -p $(TF_STATE_DIR) && chmod 0700 $(TF_STATE_DIR)
	@cd $(TF_DIR) && umask 0077 && terraform init

tf-fmt:
	@echo "Checking G05 Terraform formatting..."
	@cd $(TF_DIR) && terraform fmt -check -recursive

tf-validate:
	@echo "Validating G05 Terraform configuration..."
	@cd $(TF_DIR) && terraform validate

tf-providers:
	@echo "Inspecting G05 Terraform provider dependencies..."
	@cd $(TF_DIR) && terraform providers

tf-plan:
	@echo "Running G05 Terraform speculative (in-memory) plan review..."
	@cd $(TF_DIR) && terraform plan -no-color

tf-plan-save:
	@echo "Saving protected G05 Terraform execution plan to $(TF_PLAN_FILE)..."
	@mkdir -p $(TF_STATE_DIR) && chmod 0700 $(TF_STATE_DIR)
	@cd $(TF_DIR) && umask 0077 && terraform plan -no-color -out=$(TF_PLAN_FILE)

# --- Docker Compose Lifecycle (G02) ---
.PHONY: setup-secrets compose-build compose-up compose-down compose-ps compose-logs
setup-secrets:
	@./scripts/setup_secrets.sh

compose-build: setup-secrets
	@docker compose build

compose-up: setup-secrets
	@docker compose up -d

compose-down:
	@docker compose down

compose-ps:
	@docker compose ps

compose-logs:
	@docker compose logs

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

# --- Kind Kubernetes Lifecycle (G06) ---
K8S_KUBECONFIG ?= $(HOME)/.kube/config-forgeops

.PHONY: cluster-create cluster-create-dry-run cluster-delete cluster-status cluster-load-images
cluster-create:
	@./scripts/cluster/create-cluster.sh

cluster-create-dry-run:
	@./scripts/cluster/create-cluster.sh --dry-run

cluster-delete: guard-confirm
	@CONFIRM=$(CONFIRM) ./scripts/cluster/delete-cluster.sh

cluster-status:
	@if [ ! -f $(K8S_KUBECONFIG) ]; then \
		echo "Kubeconfig $(K8S_KUBECONFIG) not found. Is cluster created?"; \
		exit 1; \
	fi
	@echo "=== Node Status ==="
	@kubectl --kubeconfig=$(K8S_KUBECONFIG) get nodes -o wide
	@echo "=== Workloads Across All Namespaces ==="
	@kubectl --kubeconfig=$(K8S_KUBECONFIG) get pods,pvc,svc -A

cluster-load-images:
	@./scripts/cluster/load-images.sh

# --- G06 Workload Lifecycle ---
.PHONY: k8s-dev-deploy k8s-dev-verify k8s-dev-teardown
k8s-dev-deploy:
	@if [ ! -f $(K8S_KUBECONFIG) ]; then \
		echo "Kubeconfig $(K8S_KUBECONFIG) not found. Run 'make cluster-create' first."; \
		exit 1; \
	fi
	@echo "Applying namespace manifests and quotas..."
	@kubectl --kubeconfig=$(K8S_KUBECONFIG) apply -f platform/k8s/namespaces/
	@echo "Injecting PostgreSQL database credentials out-of-band..."
	@./scripts/cluster/inject-secrets.sh forgeops-dev
	@echo "Deploying PostgreSQL StatefulSet and Services..."
	@kubectl --kubeconfig=$(K8S_KUBECONFIG) apply -f platform/k8s/dev/postgres/
	@echo "Deploying ForgeTasks Spring Boot API..."
	@kubectl --kubeconfig=$(K8S_KUBECONFIG) apply -f platform/k8s/dev/api/

k8s-dev-verify:
	@./scripts/cluster/verify-g06.sh --read-only

k8s-dev-smoke-write:
	@./scripts/cluster/verify-g06.sh --smoke-write

k8s-dev-drill-persistence: guard-confirm
	@ALLOW_POD_TERMINATION=yes ./scripts/cluster/verify-g06.sh --drill-persistence

k8s-dev-drill-a602: guard-confirm
	@ALLOW_POD_TERMINATION=yes ./scripts/cluster/verify-g06.sh --drill-a602

k8s-dev-teardown:
	@if [ ! -f $(K8S_KUBECONFIG) ]; then \
		echo "Kubeconfig $(K8S_KUBECONFIG) not found. Nothing to tear down."; \
		exit 0; \
	fi
	@echo "Tearing down ForgeTasks API and PostgreSQL in forgeops-dev..."
	@kubectl --kubeconfig=$(K8S_KUBECONFIG) delete -f platform/k8s/dev/api/ --ignore-not-found
	@kubectl --kubeconfig=$(K8S_KUBECONFIG) delete -f platform/k8s/dev/postgres/ --ignore-not-found
	@kubectl --kubeconfig=$(K8S_KUBECONFIG) delete secret forgetasks-db-secret -n forgeops-dev --ignore-not-found
	@kubectl --kubeconfig=$(K8S_KUBECONFIG) delete pvc -l app.kubernetes.io/name=postgres -n forgeops-dev --ignore-not-found
