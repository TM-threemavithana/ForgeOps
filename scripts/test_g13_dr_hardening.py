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
    # These protected namespaces must NEVER be targetable by restore-db
    protected_targets = [
        "forgeops-dev",
        "forgeops-gitops-rehearsal",
        "forgeops-observability",
        "kube-system",
        "argocd",
        "default"
    ]
    # Create dummy backup file for testing parameter validation
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
            print("  [PASS] restore-db strictly rejected all protected target namespaces (G06/G08 intact).")
        finally:
            if os.path.exists(manifest_path):
                os.remove(manifest_path)

def test_verify_backup_integrity_checks():
    print("--> Test 4: Verifying verify-backup.sh cryptographic and corruption detection...")
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
    print("--> Test 5: Validating DR lab manifests & zero PVC enforcement...")
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
    print("--> Test 6: Verifying DR runbooks and technical specifications...")
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
    print("--> Test 7: Validating Makefile G13 targets dry-run execution...")
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
    test_verify_backup_integrity_checks()
    test_kustomize_dr_manifests()
    test_runbooks_and_specs()
    test_makefile_targets()
    print("=======================================================================")
    print("ALL GATE G13 HARDENING & STATIC TESTS PASSED (7/7 suites successful)")
    print("=======================================================================")

if __name__ == "__main__":
    main()
