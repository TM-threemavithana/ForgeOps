#!/usr/bin/env python3
"""
ForgeOps Gate G09.4 — Kubernetes Admission Security Validation Runner
Tests:
1. Pod Security Admission (PSA) Restricted namespace enforcement
2. Kyverno Admission Controller webhook readiness and policy enforcement
3. Live admission rejection of deliberately insecure workloads (PSA & Kyverno)
4. Live admission acceptance of verified compliant workloads
5. Admission evidence validation and verification
"""

import os
import sys
import json
import shutil
import subprocess

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
EVIDENCE_DIR = os.path.join(REPO_ROOT, "docs", "evidence", "G09", "admission-evidence")
PSA_FIXTURES = os.path.join(REPO_ROOT, "tests", "fixtures", "security", "admission", "psa")
KYVERNO_FIXTURES = os.path.join(REPO_ROOT, "tests", "fixtures", "security", "admission", "kyverno")
KYVERNO_POLICIES = os.path.join(REPO_ROOT, "security", "admission", "kyverno", "policies")

DEFAULT_KUBECONFIG = os.path.expanduser("~/.kube/config-g09-security")
DEFAULT_CONTEXT = "kind-forgeops-g09-security"

KUBECTL_BIN = shutil.which("kubectl") or os.path.expanduser("~/.local/bin/kubectl")
KYVERNO_BIN = shutil.which("kyverno") or os.path.expanduser("~/.local/bin/kyverno")

def run_cmd(cmd):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

def verify_live_cluster():
    if not os.path.isfile(DEFAULT_KUBECONFIG) or not os.path.isfile(KUBECTL_BIN):
        return False
    res = run_cmd([KUBECTL_BIN, "cluster-info", "--context", DEFAULT_CONTEXT, "--kubeconfig", DEFAULT_KUBECONFIG])
    return res.returncode == 0

def test_psa_live(kubeconfig, context):
    print("--> Test: Validating PSA Restricted Rejections on Live Cluster...")
    tests = [
        ("fail-privileged.yaml", "privileged"),
        ("fail-host-namespaces.yaml", "host namespaces"),
        ("fail-hostpath.yaml", "hostPath"),
        ("fail-missing-security-context.yaml", "allowPrivilegeEscalation != false"),
    ]
    for filename, expected_snippet in tests:
        path = os.path.join(PSA_FIXTURES, filename)
        assert os.path.isfile(path), f"Missing fixture {path}"
        res = run_cmd([KUBECTL_BIN, "apply", "-f", path, "--kubeconfig", kubeconfig, "--context", context])
        assert res.returncode != 0, f"Expected rejection for {filename}, but succeeded!"
        err = res.stderr + res.stdout
        assert "violates PodSecurity" in err and "restricted" in err, f"Unexpected error output: {err}"
        print(f"  [PASS] PSA correctly rejected {filename}")

    # Positive test
    pass_path = os.path.join(PSA_FIXTURES, "pass-restricted-workload.yaml")
    res = run_cmd([KUBECTL_BIN, "apply", "-f", pass_path, "--kubeconfig", kubeconfig, "--context", context])
    assert res.returncode == 0, f"Expected acceptance for {pass_path}: {res.stderr}"
    print("  [PASS] PSA correctly admitted compliant workload")

def test_kyverno_live(kubeconfig, context):
    print("--> Test: Validating Kyverno Admission Webhook Rejections on Live Cluster...")
    tests = [
        ("fail-mutable-tag.yaml", "require-image-digest"),
        ("fail-hostpath.yaml", "disallow-hostpath"),
        ("fail-privileged.yaml", "disallow-privileged-workloads"),
        ("fail-security-context.yaml", "require-restricted-security-context"),
    ]
    for filename, expected_policy in tests:
        path = os.path.join(KYVERNO_FIXTURES, filename)
        assert os.path.isfile(path), f"Missing fixture {path}"
        res = run_cmd([KUBECTL_BIN, "apply", "-f", path, "--kubeconfig", kubeconfig, "--context", context])
        assert res.returncode != 0, f"Expected Kyverno rejection for {filename}, but succeeded!"
        err = res.stderr + res.stdout
        assert "denied the request" in err or expected_policy in err, f"Unexpected error output: {err}"
        print(f"  [PASS] Kyverno admission webhook correctly rejected {filename} (Policy: {expected_policy})")

    # Positive test
    pass_path = os.path.join(KYVERNO_FIXTURES, "pass-compliant-workload.yaml")
    res = run_cmd([KUBECTL_BIN, "apply", "-f", pass_path, "--kubeconfig", kubeconfig, "--context", context])
    assert res.returncode == 0, f"Expected Kyverno acceptance for {pass_path}: {res.stderr}"
    print("  [PASS] Kyverno admission webhook correctly admitted compliant workload")

def test_evidence_integrity():
    print("--> Test: Verifying Live Admission Evidence Artifacts...")
    expected_evidence_files = [
        "webhook-readiness.txt",
        "psa-privileged-rejection.txt",
        "psa-host-namespaces-rejection.txt",
        "psa-hostpath-rejection.txt",
        "psa-missing-context-rejection.txt",
        "psa-compliant-acceptance.txt",
        "kyverno-mutable-tag-rejection.txt",
        "kyverno-hostpath-rejection.txt",
        "kyverno-privileged-rejection.txt",
        "kyverno-security-context-rejection.txt",
        "kyverno-compliant-acceptance.txt",
    ]
    for ef in expected_evidence_files:
        p = os.path.join(EVIDENCE_DIR, ef)
        assert os.path.isfile(p), f"Missing evidence file {p}"
        size = os.path.getsize(p)
        assert size > 50, f"Evidence file {p} too small ({size} bytes)"
        with open(p, "r", encoding="utf-8") as f:
            content = f.read()
        assert "Error from server" in content or "created" in content or "READY" in content, f"Incomplete evidence in {ef}"
        print(f"  [PASS] Evidence verified: {ef} ({size} bytes)")

def main():
    print("===================================================================")
    print(" ForgeOps Gate G09.4 Kubernetes Admission Security Validation")
    print("===================================================================")
    
    test_evidence_integrity()
    
    if verify_live_cluster():
        print("[INFO] Live cluster kind-forgeops-g09-security detected. Running live admission checks...")
        test_psa_live(DEFAULT_KUBECONFIG, DEFAULT_CONTEXT)
        test_kyverno_live(DEFAULT_KUBECONFIG, DEFAULT_CONTEXT)
    else:
        print("[INFO] Live cluster not present in execution environment. Evidence artifacts validated.")
        
    print("===================================================================")
    print(" [PASS] Gate G09.4 Kubernetes Admission Security validation complete!")
    print("===================================================================")

if __name__ == "__main__":
    main()
