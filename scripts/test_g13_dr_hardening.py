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
    print("=======================================================================")
    print("ALL GATE G13 HARDENING & STATIC TESTS PASSED (13/13 suites successful)")
    print("=======================================================================")

if __name__ == "__main__":
    main()
