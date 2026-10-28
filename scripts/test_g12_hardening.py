#!/usr/bin/env python3
"""
ForgeOps Gate G12 Hardening & Static Validation Suite
Validates k6 test suites, resilience experiment scripts, safety guards, manifests, and runbooks.
"""

import os
import subprocess
import sys
import glob

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

def run_cmd(cmd, env=None, check=True):
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=REPO_ROOT, env=env)
    if check and res.returncode != 0:
        print(f"FAILED: {cmd}")
        print(f"STDOUT:\n{res.stdout}")
        print(f"STDERR:\n{res.stderr}")
        raise RuntimeError(f"Command exited with {res.returncode}")
    return res

def test_k6_inspect():
    print("--> Test 1: Validating k6 load test scripts syntax...")
    k6_scripts = glob.glob(os.path.join(REPO_ROOT, "tests/load/k6/*.js"))
    assert len(k6_scripts) >= 6, f"Expected at least 6 k6 scripts, found {len(k6_scripts)}"
    for s in k6_scripts:
        rel = os.path.relpath(s, REPO_ROOT)
        # Use k6 inspect
        res = run_cmd(f"k6 inspect {s}")
        assert res.returncode == 0, f"k6 inspect failed for {rel}"
        print(f"  [PASS] k6 inspect: {rel}")

def test_shell_syntax():
    print("--> Test 2: Validating shell scripts syntax (bash -n)...")
    shell_scripts = glob.glob(os.path.join(REPO_ROOT, "scripts/cluster/sre/*.sh"))
    shell_scripts.append(os.path.join(REPO_ROOT, "tests/load/run-k6.sh"))
    assert len(shell_scripts) >= 7, f"Expected at least 7 shell scripts, found {len(shell_scripts)}"
    for s in shell_scripts:
        rel = os.path.relpath(s, REPO_ROOT)
        res = run_cmd(f"bash -n {s}")
        assert res.returncode == 0, f"bash -n failed for {rel}"
        print(f"  [PASS] bash syntax: {rel}")

def test_safety_guards_negative():
    print("--> Test 3: Verifying fail-closed safety guards (negative authorization tests)...")
    experiments = [
        "scripts/cluster/sre/experiment-01-pod-termination.sh",
        "scripts/cluster/sre/experiment-02-readiness-failure.sh",
        "scripts/cluster/sre/experiment-03-invalid-image-rollout.sh",
        "scripts/cluster/sre/experiment-04-resource-pressure.sh",
        "scripts/cluster/sre/experiment-05-gitops-rollback.sh"
    ]
    
    forbidden_namespaces = [
        "forgeops-dev",
        "forgeops-gitops-rehearsal",
        "forgeops-observability",
        "kube-system",
        "default",
        "arbitrary-ns"
    ]
    
    for exp in experiments:
        for ns in forbidden_namespaces:
            cmd = f"bash {exp} {ns} --validate-only"
            res = run_cmd(cmd, check=False)
            assert res.returncode != 0, f"SAFETY BREACH! Script {exp} allowed execution against forbidden namespace '{ns}'!"
        print(f"  [PASS] Negative guard verified for {exp}")

def test_manifest_validation():
    print("--> Test 4: Validating SRE lab manifests & zero PVC enforcement...")
    kustomize_dir = os.path.join(REPO_ROOT, "platform/sre-lab")
    res = run_cmd(f"kubectl kustomize {kustomize_dir}")
    manifest = res.stdout
    assert manifest, "Kustomize produced empty manifest!"
    
    # Assert zero PVCs in disposable fixture
    assert "kind: PersistentVolumeClaim" not in manifest, "Found PersistentVolumeClaim in disposable SRE lab! Must use emptyDir."
    import re
    assert "runAsNonRoot: true" in manifest, "Manifest must enforce runAsNonRoot: true"
    assert re.search(r"drop:\s*\n\s*-\s*ALL", manifest), "Manifest must drop all capabilities"
    print("  [PASS] Manifests verified: zero PVCs and non-root security contexts enforced.")

def test_runbooks_and_specs():
    print("--> Test 5: Verifying SRE documentation and runbooks...")
    required_docs = [
        "docs/roadmap-and-security-baseline.md",
        "docs/sre-sli-slo-spec.md",
        "docs/runbooks/INCIDENT_RESPONSE_MASTER_RUNBOOK.md",
        "docs/runbooks/RUNBOOK_API_CRASH_LOOP.md",
        "docs/runbooks/RUNBOOK_HIGH_LATENCY_AND_SATURATION.md",
        "docs/runbooks/RUNBOOK_IMAGE_ROLLOUT_FAILURE.md"
    ]
    for d in required_docs:
        full_path = os.path.join(REPO_ROOT, d)
        assert os.path.exists(full_path), f"Missing required document: {d}"
        size = os.path.getsize(full_path)
        assert size > 200, f"Document {d} appears empty or too small ({size} bytes)"
        print(f"  [PASS] Doc exists and verified: {d} ({size} bytes)")

def main():
    print("=======================================================================")
    print("Starting Gate G12 SRE Reliability & Hardening Validation Suite")
    print("=======================================================================")
    test_k6_inspect()
    test_shell_syntax()
    test_safety_guards_negative()
    test_manifest_validation()
    test_runbooks_and_specs()
    print("=======================================================================")
    print("ALL GATE G12 HARDENING & STATIC TESTS PASSED (5/5 suites successful)")
    print("=======================================================================")

if __name__ == "__main__":
    main()
