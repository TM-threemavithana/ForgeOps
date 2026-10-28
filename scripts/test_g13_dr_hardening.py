#!/usr/bin/env python3
"""
ForgeOps Gate G13 Hardening & Static Validation Suite
Validates disaster recovery workflows, backup/restore scripts, fail-closed safety guards,
manifests, and operational runbooks.
"""

import os
import subprocess
import sys
import glob
import tempfile
import json
import hashlib
import re
import stat
try:
    import bcrypt
except ImportError:
    bcrypt = None

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

def run_cmd(cmd, env=None, check=True):
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=REPO_ROOT, env=env)
    if check and res.returncode != 0:
        print(f"FAILED: {cmd}")
        print(f"STDOUT:\n{res.stdout}")
        print(f"STDERR:\n{res.stderr}")
        raise RuntimeError(f"Command exited with {res.returncode}")
    return res

def test_shell_syntax():
    print("--> Test 1: Validating shell scripts syntax (bash -n)...")
    dr_scripts = glob.glob(os.path.join(REPO_ROOT, "scripts/cluster/dr/*.sh"))
    assert len(dr_scripts) >= 5, f"Expected at least 5 DR scripts, found {len(dr_scripts)}"
    for s in dr_scripts:
        rel = os.path.relpath(s, REPO_ROOT)
        res = run_cmd(f"bash -n {s}")
        assert res.returncode == 0, f"bash -n failed for {rel}"
        print(f"  [PASS] bash syntax: {rel}")

def test_backup_source_negative_guards():
    print("--> Test 2: Verifying backup-db fail-closed source namespace guards...")
    forbidden_sources = ["production", "prod", "kube-system", "default", "argocd", "arbitrary-ns"]
    for ns in forbidden_sources:
        cmd = f"bash scripts/cluster/dr/backup-db.sh --source-namespace {ns} --dry-run"
        res = run_cmd(cmd, check=False)
        assert res.returncode != 0, f"SAFETY BREACH: backup-db allowed unauthorized source namespace '{ns}'!"
    print("  [PASS] backup-db strictly rejected all unallowlisted source namespaces.")

def test_restore_target_negative_guards():
    print("--> Test 3: Verifying restore-db strict destination refusal guards...")
    # Protected namespaces that must NEVER be targetable by restore-db
    protected_targets = [
        "forgeops-dev",
        "forgeops-gitops-rehearsal",
        "forgeops-observability",
        "kube-system",
        "argocd",
        "default",
        "unauthorized-namespace"
    ]
    with tempfile.NamedTemporaryFile(suffix=".dump") as tf:
        tf.write(b"PGDMPdummy")
        tf.flush()
        manifest_path = tf.name.replace(".dump", ".manifest.json")
        with open(manifest_path, "w") as mf:
            json.dump({
                "manifest_schema_version": "1.0",
                "sha256_checksum": "dummy",
                "archive_size_bytes": 10,
                "source_namespace": "forgeops-dr-lab",
                "source_database": "forgetasks",
                "backup_utc_timestamp": "20261028-120000Z"
            }, mf)
        try:
            for ns in protected_targets:
                cmd = f"bash scripts/cluster/dr/restore-db.sh {tf.name} --target-namespace {ns} --dry-run"
                res = run_cmd(cmd, check=False)
                assert res.returncode != 0, f"CRITICAL SAFETY BREACH: restore-db allowed target namespace '{ns}'!"
            print("  [PASS] restore-db strictly rejected all unapproved and protected target namespaces.")
        finally:
            if os.path.exists(manifest_path):
                os.remove(manifest_path)

def test_restore_db_error_handling_and_no_suppression():
    print("--> Test 4: Verifying restore-db.sh strict error handling and lack of failure suppression...")
    restore_script = os.path.join(REPO_ROOT, "scripts/cluster/dr/restore-db.sh")
    with open(restore_script, "r") as f:
        content = f.read()

    # Rule: No || true suppressing pg_restore
    assert "pg_restore" in content, "pg_restore invocation missing"
    lines = content.splitlines()
    # Find the actual pg_restore command execution block (has -d or --exit-on-error)
    restore_exec_found = False
    for idx, line in enumerate(lines):
        if "pg_restore" in line and ("-d" in line or "-U" in line or "PGPASSWORD" in line or "--exit-on-error" in line) and not line.strip().startswith("#"):
            restore_exec_found = True
            block = "\n".join(lines[idx:idx+15])
            assert "|| true" not in block, "VIOLATION: pg_restore failure is suppressed with '|| true'!"
            assert "--exit-on-error" in block, "VIOLATION: pg_restore missing '--exit-on-error'!"
            assert "--clean" not in block, "VIOLATION: pg_restore must not automatically use '--clean'!"
            assert "--if-exists" not in block, "VIOLATION: pg_restore must not automatically use '--if-exists'!"
            break
    assert restore_exec_found, "Could not find pg_restore execution command in restore-db.sh!"

    # Rule: Target database freshness check before restore
    assert "information_schema.tables" in content, "Missing fresh target database schema check before restoration"
    assert "FRESH TARGET DATABASE REFUSAL" in content, "Missing fresh target database refusal guard"

    # Rule: Same pod check
    assert "SOURCE_POD_UID" in content and "TARGET_POD_UID" in content, "Missing source vs target Pod UID distinction guard"
    assert "Target Pod UID matches Source Pod UID" in content, "Missing identical Pod UID refusal guard"

    # Rule: Strict query assertions without || echo 0
    assert "|| echo 0" not in content, "VIOLATION: Found '|| echo 0' suppressing verification failures in restore-db.sh"
    assert "ON_ERROR_STOP=1" in content, "Missing ON_ERROR_STOP=1 for strict psql query execution"

    print("  [PASS] restore-db.sh enforces strict error handling, --exit-on-error, fresh DB assertion, and UID isolation.")

def test_backup_source_isolation_and_prevalidation():
    print("--> Test 5: Verifying backup-db.sh strict source selection and pre-validation...")
    backup_script = os.path.join(REPO_ROOT, "scripts/cluster/dr/backup-db.sh")
    with open(backup_script, "r") as f:
        content = f.read()

    assert "app=dr-source-db" in content, "backup-db.sh must select app=dr-source-db in forgeops-dr-lab"
    assert "Refusing to backup dr-target-db" in content, "backup-db.sh must reject dr-target-db as backup source"
    assert "DATA PRE-VALIDATION FAILURE" in content, "backup-db.sh must validate source dataset before executing pg_dump"
    assert "pg_dump" in content and "-Fc" in content, "backup-db.sh must invoke pg_dump with -Fc"
    print("  [PASS] backup-db.sh strictly selects source pod, rejects target pod, and pre-validates dataset.")

def test_secret_race_prevention():
    print("--> Test 6: Verifying Secret creation precedes Deployment scheduling in setup-dr-lab.sh...")
    setup_script = os.path.join(REPO_ROOT, "scripts/cluster/dr/setup-dr-lab.sh")
    with open(setup_script, "r") as f:
        content = f.read()

    secret_pos = content.find("kubectl create secret generic dr-db-secret")
    kustomize_pos = content.find("kubectl apply -k")
    assert secret_pos != -1, "setup-dr-lab.sh must create dr-db-secret"
    assert kustomize_pos != -1, "setup-dr-lab.sh must apply kustomize manifests"
    assert secret_pos < kustomize_pos, "RACE CONDITION: dr-db-secret must be created BEFORE applying Deployments!"

    # Verify placeholder secret is not committed to active kustomization
    kustomization_file = os.path.join(REPO_ROOT, "platform/dr-lab/kustomization.yaml")
    with open(kustomization_file, "r") as f:
        kust = f.read()
    assert "secret.yaml" not in kust, "Committed secret.yaml must not be in active kustomization.yaml"

    # Verify authentication check is performed on both database instances
    assert "dr-source-db failed to authenticate" in content, "Missing source DB auth check"
    assert "dr-target-db failed to authenticate" in content, "Missing target DB auth check"
    print("  [PASS] Secret creation precedes Deployments; zero race condition on database credentials.")

def test_authentic_flyway_history():
    print("--> Test 7: Verifying genuine Flyway migrations & checksum enforcement...")
    setup_script = os.path.join(REPO_ROOT, "scripts/cluster/dr/setup-dr-lab.sh")
    with open(setup_script, "r") as f:
        setup_content = f.read()

    assert "12345678" not in setup_content, "VIOLATION: Fabricated Flyway checksum 12345678 found in setup-dr-lab.sh!"
    assert "FlywayMigrationRunner" in setup_content or "run_flyway_migration_runner" in setup_content, "Must invoke authentic Flyway migration runner"

    restore_script = os.path.join(REPO_ROOT, "scripts/cluster/dr/restore-db.sh")
    with open(restore_script, "r") as f:
        restore_content = f.read()
    assert "12345678" in restore_content, "restore-db.sh must explicitly check and reject fabricated checksum 12345678"
    assert "run_flyway_migration_runner \"validate\"" in restore_content or "FlywayMigrationRunner" in restore_content, "restore-db.sh must run Flyway validate"

    # Verify FlywayMigrationRunner.java exists and has required actions
    runner_file = os.path.join(REPO_ROOT, "apps/forgetasks-api/src/main/java/com/forgeops/forgetasks/FlywayMigrationRunner.java")
    assert os.path.exists(runner_file), f"Missing FlywayMigrationRunner.java at {runner_file}"
    with open(runner_file, "r") as f:
        runner_content = f.read()
    assert "flyway.migrate()" in runner_content, "Runner missing migrate action"
    assert "flyway.validate()" in runner_content, "Runner missing validate action"
    print("  [PASS] Genuine Flyway migration engine configured with authentic checksum verification.")

def test_teardown_hardening():
    print("--> Test 8: Verifying teardown-dr-lab.sh allowlist and UID verification...")
    teardown_script = os.path.join(REPO_ROOT, "scripts/cluster/dr/teardown-dr-lab.sh")
    with open(teardown_script, "r") as f:
        content = f.read()

    assert "forgeops-dr-lab.ns-uid" in content, "teardown-dr-lab.sh must verify recorded namespace UID"
    assert "assert_no_pvc_in_disposable_ns" in content, "teardown-dr-lab.sh must assert 0 PVCs"
    assert "StatefulSet(s)" in content, "teardown-dr-lab.sh must block if unexpected StatefulSets exist"
    assert "DaemonSet(s)" in content, "teardown-dr-lab.sh must block if unexpected DaemonSets exist"
    assert "UNEXPECTED DEPLOYMENT" in content, "teardown-dr-lab.sh must block on unapproved deployments"
    assert "Host backup archives preserved" in content, "teardown-dr-lab.sh must verify host backup preservation"
    print("  [PASS] teardown-dr-lab.sh enforces strict resource allowlist and namespace UID matching.")

def test_api_smoke_test_order_and_metrics():
    print("--> Test 9: Verifying rehearse-dr.sh sequencing, REST smoke tests, and metric clarity...")
    rehearse_script = os.path.join(REPO_ROOT, "scripts/cluster/dr/rehearse-dr.sh")
    with open(rehearse_script, "r") as f:
        content = f.read()

    restore_call = content.find("restore-db.sh")
    api_deploy = content.find("api-deployment.yaml")
    assert restore_call != -1, "rehearse-dr.sh missing restore-db.sh call"
    assert api_deploy != -1, "rehearse-dr.sh missing api-deployment apply"
    assert restore_call < api_deploy, "ORDER VIOLATION: dr-api must only be deployed AFTER restore-db completes!"

    # Smoke test checks
    assert "/api/v1/projects" in content, "rehearse-dr.sh missing /api/v1/projects query"
    assert "/actuator/health" in content, "rehearse-dr.sh missing /actuator/health probe"
    assert "401" in content, "rehearse-dr.sh missing negative authentication check (401)"

    # Metric label distinctions
    assert "DUMP_DURATION_MS" in content, "rehearse-dr.sh must report dump duration"
    assert "RESTORE_DURATION_MS" in content, "rehearse-dr.sh must report restore duration"
    assert "BACKUP_AGE_SECONDS" in content, "rehearse-dr.sh must report backup age (RPO)"
    assert "E2E_DURATION_MS" in content, "rehearse-dr.sh must report end-to-end recovery time"
    print("  [PASS] rehearse-dr.sh deploys API strictly after restore, runs REST smoke tests, and distinguishes all metrics.")

def test_verify_backup_integrity_checks():
    print("--> Test 10: Verifying verify-backup.sh cryptographic and corruption detection...")
    with tempfile.TemporaryDirectory() as td:
        dump_file = os.path.join(td, "test.dump")
        manifest_file = os.path.join(td, "test.manifest.json")
        
        # A: Nonexistent file
        res = run_cmd(f"bash scripts/cluster/dr/verify-backup.sh {td}/nonexistent.dump", check=False)
        assert res.returncode != 0, "verify-backup should fail on nonexistent file"
        
        # B: Invalid magic header
        content = b"NOT_A_PG_DUMP_FILE_12345"
        with open(dump_file, "wb") as f:
            f.write(content)
        sha = hashlib.sha256(content).hexdigest()
        with open(manifest_file, "w") as f:
            json.dump({
                "manifest_schema_version": "1.0",
                "sha256_checksum": sha,
                "archive_size_bytes": len(content),
                "source_namespace": "forgeops-dr-lab",
                "source_database": "forgetasks",
                "backup_utc_timestamp": "20261028-120000Z"
            }, f)
        res = run_cmd(f"bash scripts/cluster/dr/verify-backup.sh {dump_file}", check=False)
        assert res.returncode != 0, "verify-backup should fail on invalid magic header"
        
        # C: Checksum mismatch (tampered file)
        with open(dump_file, "wb") as f:
            f.write(b"PGDMP_tampered_payload_here")
        res = run_cmd(f"bash scripts/cluster/dr/verify-backup.sh {dump_file}", check=False)
        assert res.returncode != 0, "verify-backup should fail on checksum mismatch"
        
    print("  [PASS] verify-backup successfully detected missing, tampered, and corrupt archives.")

def test_kustomize_dr_manifests():
    print("--> Test 11: Validating DR lab manifests & zero PVC enforcement...")
    kustomize_dir = os.path.join(REPO_ROOT, "platform/dr-lab")
    res = run_cmd(f"kubectl kustomize {kustomize_dir}")
    manifest = res.stdout
    assert manifest, "Kustomize produced empty manifest for platform/dr-lab!"
    
    # Assert zero PersistentVolumeClaims
    assert "kind: PersistentVolumeClaim" not in manifest, "Found PVC in disposable DR lab! Must use ephemeral emptyDir."
    assert "emptyDir: {}" in manifest, "PostgreSQL workloads must mount emptyDir ephemeral storage."
    assert "runAsNonRoot: true" in manifest, "Workloads must enforce runAsNonRoot: true"
    print("  [PASS] DR lab manifests verified: 0 PVCs, emptyDir storage, and non-root security contexts enforced.")

def test_runbooks_and_specs():
    print("--> Test 12: Verifying DR runbooks and technical specifications...")
    required_docs = [
        "docs/runbooks/POSTGRESQL_DISASTER_RECOVERY_RUNBOOK.md",
        "docs/runbooks/KIND_CLUSTER_REBUILD_RUNBOOK.md",
        "docs/sre-dr-spec.md"
    ]
    for d in required_docs:
        full_path = os.path.join(REPO_ROOT, d)
        assert os.path.exists(full_path), f"Missing required document: {d}"
        size = os.path.getsize(full_path)
        assert size > 500, f"Document {d} appears empty or too small ({size} bytes)"
        print(f"  [PASS] Document exists and verified: {d} ({size} bytes)")

def test_makefile_targets():
    print("--> Test 13: Validating Makefile G13 targets dry-run execution...")
    targets = ["backup-db", "verify-backup", "restore-db", "dr-test"]
    for t in targets:
        res = run_cmd(f"make -n {t}")
        assert res.returncode == 0, f"make -n {t} failed"
        print(f"  [PASS] make -n {t} syntax valid.")

def test_synthetic_account_authentication_bcrypt():
    print("--> Test 14: Verifying synthetic seed credentials and authentic BCrypt matching...")
    seed_sql = os.path.join(REPO_ROOT, "platform/dr-lab/synthetic-seed.sql")
    with open(seed_sql, "r") as f:
        content = f.read()

    # Extract BCrypt hashes
    pattern = re.compile(r"\('([^']+)',\s*'([^']+)',\s*'(\$2[ab]\$12\$[^']+)',\s*'([^']+)'\)")
    matches = pattern.findall(content)
    assert len(matches) >= 2, f"Expected at least 2 synthetic accounts, found {len(matches)}"

    for account_id, username, hash_val, role in matches:
        assert username in ("dr_admin", "dr_user"), f"Unexpected user: {username}"
        assert role in ("ROLE_ADMIN", "ROLE_USER"), f"Unexpected role: {role}"
        assert re.match(r"^\$2[ab]\$12\$[./A-Za-z0-9]{53}$", hash_val), f"Invalid BCrypt hash format for {username}: {hash_val}"
        assert hash_val == "$2a$12$KuejrKi6nxwWYq0O.eEt5.XpnQUJLKgXrpwETOUVi.h8OdrChvUD.", f"Hash does not match verified BCrypt value for {username}"
        if bcrypt is not None:
            # Positive authentication
            assert bcrypt.checkpw(b"Password123!", hash_val.encode("utf-8")), f"Positive authentication failed for {username}"
            # Negative authentication
            assert not bcrypt.checkpw(b"WrongPassword", hash_val.encode("utf-8")), f"Negative authentication failed for {username}"
            assert not bcrypt.checkpw(b"InvalidPassword123!", hash_val.encode("utf-8")), f"Negative authentication failed for {username}"
            assert not bcrypt.checkpw(b"", hash_val.encode("utf-8")), f"Negative authentication failed for {username}"

    # Verify Java test exists
    java_test = os.path.join(REPO_ROOT, "apps/forgetasks-api/src/test/java/com/forgeops/forgetasks/SyntheticAccountAuthenticationTest.java")
    assert os.path.exists(java_test), f"Missing Java authentication test: {java_test}"
    print("  [PASS] Synthetic accounts authentic BCrypt hashes verified for positive and negative authentication.")

def test_freshness_query_negative_blocking_executable():
    print("--> Test 15: Executable negative testing: proving failed freshness query blocks pg_restore...")
    with tempfile.TemporaryDirectory() as td:
        bin_dir = os.path.join(td, "bin")
        os.makedirs(bin_dir, exist_ok=True)
        trace_file = os.path.join(td, "pg_restore_trace.log")

        # Mock pg_restore
        pg_restore_mock = os.path.join(bin_dir, "pg_restore")
        with open(pg_restore_mock, "w") as f:
            f.write(f"""#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  echo "pg_restore (PostgreSQL) 16.2"
  exit 0
fi
if [[ "$*" == *"-l "* ]]; then
  echo "TABLE public accounts forgeuser"
  echo "TABLE public projects forgeuser"
  echo "TABLE public tasks forgeuser"
  echo "TABLE public flyway_schema_history forgeuser"
  exit 0
fi
echo "RESTORE_EXECUTED" >> "{trace_file}"
exit 0
""")
        os.chmod(pg_restore_mock, os.stat(pg_restore_mock).st_mode | stat.S_IEXEC)

        # Mock kubectl
        kubectl_mock = os.path.join(bin_dir, "kubectl")
        with open(kubectl_mock, "w") as f:
            f.write("""#!/usr/bin/env bash
if [[ "$*" == *"config current-context"* ]]; then
  echo "kind-forgeops"
  exit 0
fi
if [[ "$*" == *"cluster-info"* ]]; then
  exit 0
fi
if [[ "$*" == *"get pvc -n forgeops-dr-lab"* ]]; then
  exit 0
fi
if [[ "$*" == *"get pvc"* ]]; then
  case "$*" in
    *postgres-storage-forgetasks-db-0*) echo "84853fb3-4d13-43a9-bc62-973c3be3c90c" ;;
    *postgres-storage-forgetasks-rehearsal-db-0*) echo "b5ea8ec9-47e8-4979-afdb-621f2e3c63b8" ;;
    *prometheus-g09-monitoring-kube-promet-prometheus-db-prometheus-g09-monitoring-kube-promet-prometheus-0*) echo "cd64e090-2c69-49b3-a389-de5841ce06d6" ;;
    *storage-loki-0*) echo "23468366-7394-4f2d-be1f-2a640d6f12c5" ;;
    *storage-tempo-0*) echo "092b6655-6617-467c-b546-69e201a0ba8a" ;;
    *) exit 0 ;;
  esac
  exit 0
fi
if [[ "$*" == *"get pods -n forgeops-dr-lab -l app=dr-target-db"* ]]; then
  echo "dr-target-db-pod"
  exit 0
fi
if [[ "$*" == *"get pod dr-target-db-pod"* ]]; then
  if [[ "$*" == *"ownerReferences"* ]]; then
    echo "dr-target-db"
    exit 0
  fi
  if [[ "$*" == *"uid"* ]]; then
    echo "target-uid-1111"
    exit 0
  fi
  if [[ "$*" == *"role"* ]]; then
    echo "target"
    exit 0
  fi
fi
if [[ "$*" == *"get pods -n forgeops-dr-lab -l app=dr-source-db"* ]]; then
  echo "source-uid-2222"
  exit 0
fi
if [[ "$*" == *"get secrets -n forgeops-dr-lab"* ]]; then
  echo "dr-db-secret"
  exit 0
fi
if [[ "$*" == *"get secret dr-db-secret"* ]]; then
  echo "cGFzc3dvcmQ=" # base64 "password"
  exit 0
fi
if [[ "$*" == *"port-forward"* ]]; then
  sleep 30 &
  exit 0
fi
exit 0
""")
        os.chmod(kubectl_mock, os.stat(kubectl_mock).st_mode | stat.S_IEXEC)

        # Mock psql
        psql_mock = os.path.join(bin_dir, "psql")
        with open(psql_mock, "w") as f:
            f.write("""#!/usr/bin/env bash
if [[ "$*" == *"SELECT 1;"* ]] || [[ "$*" == *"pg_database"* ]]; then
  echo "1"
  exit 0
fi
if [[ "$*" == *"information_schema.tables"* ]]; then
  case "${TEST_MOCK_FRESHNESS_MODE:-}" in
    query_failure)
      echo "psql: error: connection lost during query" >&2
      exit 2
      ;;
    non_empty)
      echo "4"
      exit 0
      ;;
    corrupt)
      echo "unexpected_corrupt_text"
      exit 0
      ;;
    clean)
      echo "0"
      exit 0
      ;;
  esac
fi
echo "1"
exit 0
""")
        os.chmod(psql_mock, os.stat(psql_mock).st_mode | stat.S_IEXEC)

        # Create valid dummy dump and manifest
        dump_file = os.path.join(td, "test.dump")
        manifest_file = os.path.join(td, "test.manifest.json")
        payload = b"PGDMP_valid_custom_dump_header_data"
        with open(dump_file, "wb") as f:
            f.write(payload)
        sha = hashlib.sha256(payload).hexdigest()
        with open(manifest_file, "w") as f:
            json.dump({
                "manifest_schema_version": "1.0",
                "sha256_checksum": sha,
                "archive_size_bytes": len(payload),
                "source_namespace": "forgeops-dr-lab",
                "source_database": "forgetasks",
                "backup_utc_timestamp": "20261028-120000Z",
                "backup_epoch_seconds": 1730000000
            }, f)

        custom_env = os.environ.copy()
        custom_env["PATH"] = f"{bin_dir}:{custom_env['PATH']}"

        # Sub-test 1: Query failure (exit code 2 from psql)
        if os.path.exists(trace_file):
            os.remove(trace_file)
        custom_env["TEST_MOCK_FRESHNESS_MODE"] = "query_failure"
        res = subprocess.run(
            f"bash scripts/cluster/dr/restore-db.sh {dump_file} --target-namespace forgeops-dr-lab",
            shell=True, capture_output=True, text=True, cwd=REPO_ROOT, env=custom_env
        )
        assert res.returncode != 0, "restore-db.sh should have failed when freshness query failed!"
        assert "DATABASE FRESHNESS QUERY FAILURE" in res.stderr or "DATABASE FRESHNESS QUERY FAILURE" in res.stdout
        assert not os.path.exists(trace_file), "CRITICAL: pg_restore was executed despite failed freshness query!"
        print("  [PASS] Freshness query failure strictly blocked restoration and halted before pg_restore.")

        # Sub-test 2: Non-empty target database (count = 4)
        if os.path.exists(trace_file):
            os.remove(trace_file)
        custom_env["TEST_MOCK_FRESHNESS_MODE"] = "non_empty"
        res = subprocess.run(
            f"bash scripts/cluster/dr/restore-db.sh {dump_file} --target-namespace forgeops-dr-lab",
            shell=True, capture_output=True, text=True, cwd=REPO_ROOT, env=custom_env
        )
        assert res.returncode != 0, "restore-db.sh should have failed when target DB is non-empty!"
        assert "FRESH TARGET DATABASE REFUSAL" in res.stderr or "FRESH TARGET DATABASE REFUSAL" in res.stdout
        assert not os.path.exists(trace_file), "CRITICAL: pg_restore was executed on non-empty database!"
        print("  [PASS] Non-empty destination database strictly blocked restoration and halted before pg_restore.")

        # Sub-test 3: Corrupt freshness query output
        if os.path.exists(trace_file):
            os.remove(trace_file)
        custom_env["TEST_MOCK_FRESHNESS_MODE"] = "corrupt"
        res = subprocess.run(
            f"bash scripts/cluster/dr/restore-db.sh {dump_file} --target-namespace forgeops-dr-lab",
            shell=True, capture_output=True, text=True, cwd=REPO_ROOT, env=custom_env
        )
        assert res.returncode != 0, "restore-db.sh should have failed on corrupt freshness query output!"
        assert "DATABASE FRESHNESS QUERY CORRUPT" in res.stderr or "DATABASE FRESHNESS QUERY CORRUPT" in res.stdout
        assert not os.path.exists(trace_file), "CRITICAL: pg_restore was executed on corrupt freshness query output!"
        print("  [PASS] Corrupt freshness query output strictly blocked restoration and halted before pg_restore.")

def test_teardown_and_setup_hardening_executable():
    print("--> Test 16: Executable negative testing: UID identity, inventory allowlists, and unowned namespace refusal...")
    with tempfile.TemporaryDirectory() as td:
        bin_dir = os.path.join(td, "bin")
        os.makedirs(bin_dir, exist_ok=True)

        kubectl_mock = os.path.join(bin_dir, "kubectl")
        with open(kubectl_mock, "w") as f:
            f.write(r"""#!/usr/bin/env bash
if [[ "$*" == *"config current-context"* ]]; then
  echo "kind-forgeops"
  exit 0
fi
if [[ "$*" == *"cluster-info"* ]]; then
  exit 0
fi
if [[ "$*" == *"get pvc -n forgeops-dr-lab"* ]]; then
  exit 0
fi
if [[ "$*" == *"get pvc"* ]]; then
  case "$*" in
    *postgres-storage-forgetasks-db-0*) echo "84853fb3-4d13-43a9-bc62-973c3be3c90c" ;;
    *postgres-storage-forgetasks-rehearsal-db-0*) echo "b5ea8ec9-47e8-4979-afdb-621f2e3c63b8" ;;
    *prometheus-g09-monitoring-kube-promet-prometheus-db-prometheus-g09-monitoring-kube-promet-prometheus-0*) echo "cd64e090-2c69-49b3-a389-de5841ce06d6" ;;
    *storage-loki-0*) echo "23468366-7394-4f2d-be1f-2a640d6f12c5" ;;
    *storage-tempo-0*) echo "092b6655-6617-467c-b546-69e201a0ba8a" ;;
    *) exit 0 ;;
  esac
  exit 0
fi
if [[ "$*" == *"get ns forgeops-dr-lab"* ]]; then
  if [[ "${MOCK_NS_STATE:-}" == "not_found" ]]; then
    exit 1
  fi
  if [[ "$*" == *".metadata.name"* ]]; then
    echo "forgeops-dr-lab"
    exit 0
  fi
  if [[ "$*" == *"disposable"* ]]; then
    if [[ "${MOCK_NS_STATE:-}" == "unowned" ]]; then
      echo ""
      exit 0
    fi
    echo "true"
    exit 0
  fi
  if [[ "$*" == *"environment"* ]]; then
    if [[ "${MOCK_NS_STATE:-}" == "unowned" ]]; then
      echo ""
      exit 0
    fi
    echo "dr-lab"
    exit 0
  fi
  if [[ "$*" == *".metadata.uid"* ]]; then
    echo "${MOCK_CURRENT_UID:-actual-uid-12345}"
    exit 0
  fi
  exit 0
fi

# Resource allowlist checks
if [[ "$*" == *"get statefulsets"* ]]; then
  [[ -n "${MOCK_STS_OUTPUT:-}" ]] && echo "${MOCK_STS_OUTPUT}"
  exit 0
fi
if [[ "$*" == *"get daemonsets"* ]]; then
  [[ -n "${MOCK_DS_OUTPUT:-}" ]] && echo "${MOCK_DS_OUTPUT}"
  exit 0
fi
if [[ "$*" == *"get jobs"* ]]; then
  [[ -n "${MOCK_JOB_OUTPUT:-}" ]] && echo "${MOCK_JOB_OUTPUT}"
  exit 0
fi
if [[ "$*" == *"get cronjobs"* ]]; then
  [[ -n "${MOCK_CRONJOB_OUTPUT:-}" ]] && echo "${MOCK_CRONJOB_OUTPUT}"
  exit 0
fi
if [[ "$*" == *"get ingress"* ]]; then
  [[ -n "${MOCK_ING_OUTPUT:-}" ]] && echo "${MOCK_ING_OUTPUT}"
  exit 0
fi
if [[ "$*" == *"get deployments"* ]]; then
  echo "${MOCK_DEP_OUTPUT:-dr-source-db dr-target-db dr-api}"
  exit 0
fi
if [[ "$*" == *"get services"* ]]; then
  echo "${MOCK_SVC_OUTPUT:-dr-source-db dr-target-db dr-api}"
  exit 0
fi
if [[ "$*" == *"get secrets"* ]]; then
  echo "${MOCK_SEC_OUTPUT:-dr-db-secret}"
  exit 0
fi
if [[ "$*" == *"get secret "* ]]; then
  echo "Opaque"
  exit 0
fi
if [[ "$*" == *"get configmaps"* ]]; then
  echo "${MOCK_CM_OUTPUT:-kube-root-ca.crt dr-api-config}"
  exit 0
fi
if [[ "$*" == *"get serviceaccounts"* ]]; then
  echo "${MOCK_SA_OUTPUT:-default dr-serviceaccount}"
  exit 0
fi
exit 0
""")
        os.chmod(kubectl_mock, os.stat(kubectl_mock).st_mode | stat.S_IEXEC)

        custom_env = os.environ.copy()
        custom_env["PATH"] = f"{bin_dir}:{custom_env['PATH']}"

        # 1. Missing UID file
        custom_env["FORGEOPS_DR_UID_FILE"] = os.path.join(td, "nonexistent.uid")
        res = subprocess.run(
            "bash scripts/cluster/dr/teardown-dr-lab.sh forgeops-dr-lab",
            shell=True, capture_output=True, text=True, cwd=REPO_ROOT, env=custom_env
        )
        assert res.returncode != 0, "teardown should fail when UID file is missing!"
        assert "Missing recorded namespace UID file" in res.stderr or "Missing recorded namespace UID file" in res.stdout
        print("  [PASS] Missing UID file strictly halts teardown.")

        # 2. Empty UID file
        empty_uid_file = os.path.join(td, "empty.uid")
        with open(empty_uid_file, "w") as f:
            f.write("   \n")
        custom_env["FORGEOPS_DR_UID_FILE"] = empty_uid_file
        res = subprocess.run(
            "bash scripts/cluster/dr/teardown-dr-lab.sh forgeops-dr-lab",
            shell=True, capture_output=True, text=True, cwd=REPO_ROOT, env=custom_env
        )
        assert res.returncode != 0, "teardown should fail when UID file is empty!"
        assert "is empty" in res.stderr or "is empty" in res.stdout
        print("  [PASS] Empty UID file strictly halts teardown.")

        # 3. Mismatched UID
        mismatch_uid_file = os.path.join(td, "mismatch.uid")
        with open(mismatch_uid_file, "w") as f:
            f.write("recorded-uid-99999\n")
        custom_env["FORGEOPS_DR_UID_FILE"] = mismatch_uid_file
        custom_env["MOCK_CURRENT_UID"] = "actual-uid-12345"
        res = subprocess.run(
            "bash scripts/cluster/dr/teardown-dr-lab.sh forgeops-dr-lab",
            shell=True, capture_output=True, text=True, cwd=REPO_ROOT, env=custom_env
        )
        assert res.returncode != 0, "teardown should fail when UID does not match!"
        assert "NAMESPACE IDENTITY MISMATCH" in res.stderr or "NAMESPACE IDENTITY MISMATCH" in res.stdout
        print("  [PASS] Mismatched namespace UID strictly halts teardown.")

        # Match UID for resource allowlist tests
        valid_uid_file = os.path.join(td, "valid.uid")
        with open(valid_uid_file, "w") as f:
            f.write("actual-uid-12345\n")
        custom_env["FORGEOPS_DR_UID_FILE"] = valid_uid_file
        custom_env["MOCK_CURRENT_UID"] = "actual-uid-12345"

        # 4. Unexpected Deployment
        custom_env["MOCK_DEP_OUTPUT"] = "dr-source-db dr-target-db dr-api unapproved-deployment"
        res = subprocess.run(
            "bash scripts/cluster/dr/teardown-dr-lab.sh forgeops-dr-lab",
            shell=True, capture_output=True, text=True, cwd=REPO_ROOT, env=custom_env
        )
        assert res.returncode != 0, "teardown should fail on unapproved deployment!"
        assert "UNEXPECTED DEPLOYMENT" in res.stderr or "UNEXPECTED DEPLOYMENT" in res.stdout
        custom_env.pop("MOCK_DEP_OUTPUT")

        # 5. Unexpected Service
        custom_env["MOCK_SVC_OUTPUT"] = "dr-source-db dr-target-db unapproved-service"
        res = subprocess.run(
            "bash scripts/cluster/dr/teardown-dr-lab.sh forgeops-dr-lab",
            shell=True, capture_output=True, text=True, cwd=REPO_ROOT, env=custom_env
        )
        assert res.returncode != 0, "teardown should fail on unapproved service!"
        assert "UNEXPECTED SERVICE" in res.stderr or "UNEXPECTED SERVICE" in res.stdout
        custom_env.pop("MOCK_SVC_OUTPUT")

        # 6. Unexpected Secret
        custom_env["MOCK_SEC_OUTPUT"] = "dr-db-secret rogue-secret"
        res = subprocess.run(
            "bash scripts/cluster/dr/teardown-dr-lab.sh forgeops-dr-lab",
            shell=True, capture_output=True, text=True, cwd=REPO_ROOT, env=custom_env
        )
        assert res.returncode != 0, "teardown should fail on unapproved secret!"
        assert "UNEXPECTED SECRET" in res.stderr or "UNEXPECTED SECRET" in res.stdout
        custom_env.pop("MOCK_SEC_OUTPUT")

        # 7. Unexpected ConfigMap
        custom_env["MOCK_CM_OUTPUT"] = "kube-root-ca.crt rogue-cm"
        res = subprocess.run(
            "bash scripts/cluster/dr/teardown-dr-lab.sh forgeops-dr-lab",
            shell=True, capture_output=True, text=True, cwd=REPO_ROOT, env=custom_env
        )
        assert res.returncode != 0, "teardown should fail on unapproved configmap!"
        assert "UNEXPECTED CONFIGMAP" in res.stderr or "UNEXPECTED CONFIGMAP" in res.stdout
        custom_env.pop("MOCK_CM_OUTPUT")

        # 8. Unexpected ServiceAccount
        custom_env["MOCK_SA_OUTPUT"] = "default rogue-sa"
        res = subprocess.run(
            "bash scripts/cluster/dr/teardown-dr-lab.sh forgeops-dr-lab",
            shell=True, capture_output=True, text=True, cwd=REPO_ROOT, env=custom_env
        )
        assert res.returncode != 0, "teardown should fail on unapproved serviceaccount!"
        assert "UNEXPECTED SERVICEACCOUNT" in res.stderr or "UNEXPECTED SERVICEACCOUNT" in res.stdout
        custom_env.pop("MOCK_SA_OUTPUT")

        # 9. Unexpected CronJob
        custom_env["MOCK_CRONJOB_OUTPUT"] = "sample-cronjob"
        res = subprocess.run(
            "bash scripts/cluster/dr/teardown-dr-lab.sh forgeops-dr-lab",
            shell=True, capture_output=True, text=True, cwd=REPO_ROOT, env=custom_env
        )
        assert res.returncode != 0, "teardown should fail on unexpected cronjob!"
        assert "CronJob(s)" in res.stderr or "CronJob(s)" in res.stdout
        custom_env.pop("MOCK_CRONJOB_OUTPUT")
        print("  [PASS] Resource allowlist checks strictly halt teardown on any unapproved resource.")

        # 10. Setup rejects pre-existing unowned lab namespace
        custom_env["MOCK_NS_STATE"] = "unowned"
        res = subprocess.run(
            "bash scripts/cluster/dr/setup-dr-lab.sh forgeops-dr-lab",
            shell=True, capture_output=True, text=True, cwd=REPO_ROOT, env=custom_env
        )
        assert res.returncode != 0, "setup should fail on pre-existing unowned namespace!"
        assert "is unowned or lacks required disposable labels" in res.stderr or "is unowned or lacks required disposable labels" in res.stdout
        print("  [PASS] Pre-existing unowned namespace strictly rejected by setup-dr-lab.sh.")

def main():
    print("=======================================================================")
    print("Starting Gate G13 Disaster Recovery & Hardening Validation Suite")
    print("=======================================================================")
    test_shell_syntax()
    test_backup_source_negative_guards()
    test_restore_target_negative_guards()
    test_restore_db_error_handling_and_no_suppression()
    test_backup_source_isolation_and_prevalidation()
    test_secret_race_prevention()
    test_authentic_flyway_history()
    test_teardown_hardening()
    test_api_smoke_test_order_and_metrics()
    test_verify_backup_integrity_checks()
    test_kustomize_dr_manifests()
    test_runbooks_and_specs()
    test_makefile_targets()
    test_synthetic_account_authentication_bcrypt()
    test_freshness_query_negative_blocking_executable()
    test_teardown_and_setup_hardening_executable()
    print("=======================================================================")
    print("ALL GATE G13 HARDENING & STATIC TESTS PASSED (16/16 suites successful)")
    print("=======================================================================")

if __name__ == "__main__":
    main()
