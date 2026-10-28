#!/usr/bin/env python3
"""
ForgeOps Gate G14: Automated Security & Policy-as-Code Validation Suite
Tests Kyverno CLI policies, positive/negative manifest enforcement, and error trapping.
"""

import os
import sys
import yaml
import shutil
import subprocess

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
KYVERNO_DIR = os.path.join(REPO_ROOT, "security", "policies", "kyverno")
TESTS_DIR = os.path.join(KYVERNO_DIR, "tests")

# Resolve kyverno CLI binary
KYVERNO_BIN = shutil.which("kyverno")
if not KYVERNO_BIN:
    user_local_bin = os.path.expanduser("~/.local/bin/kyverno")
    if os.path.isfile(user_local_bin) and os.access(user_local_bin, os.X_OK):
        KYVERNO_BIN = user_local_bin
    else:
        print("[FAIL] kyverno CLI binary not found in PATH or ~/.local/bin/kyverno")
        sys.exit(1)

def run_command(cmd, expect_zero=True):
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if expect_zero and res.returncode != 0:
        print(f"[FAIL] Command failed with exit code {res.returncode}: {' '.join(cmd)}")
        print("STDOUT:\n" + res.stdout)
        print("STDERR:\n" + res.stderr)
        sys.exit(1)
    elif not expect_zero and res.returncode == 0:
        print(f"[FAIL] Command succeeded unexpectedly (expected non-zero): {' '.join(cmd)}")
        print("STDOUT:\n" + res.stdout)
        sys.exit(1)
    return res

def test_tool_version():
    print("--> Test 1: Verifying Kyverno CLI version & tool availability...")
    res = run_command([KYVERNO_BIN, "version"])
    assert "Version: 1.19" in res.stdout or "Version:" in res.stdout, f"Unexpected version: {res.stdout}"
    print(f"  [PASS] Kyverno CLI operational: {res.stdout.splitlines()[0]}")

def test_policy_yaml_syntax():
    print("--> Test 2: Validating YAML syntax and schema of all 10 Kyverno policies...")
    policy_files = [f for f in os.listdir(KYVERNO_DIR) if f.endswith(".yaml") or f.endswith(".yml")]
    assert len(policy_files) == 10, f"Expected 10 policy files, found {len(policy_files)}: {policy_files}"
    
    for pf in sorted(policy_files):
        path = os.path.join(KYVERNO_DIR, pf)
        with open(path, "r") as f:
            docs = list(yaml.safe_load_all(f))
        assert len(docs) > 0, f"Empty policy file: {pf}"
        doc = docs[0]
        assert doc.get("apiVersion") == "kyverno.io/v1", f"{pf} missing apiVersion: kyverno.io/v1"
        assert doc.get("kind") == "ClusterPolicy", f"{pf} missing kind: ClusterPolicy"
        assert "spec" in doc and "rules" in doc["spec"], f"{pf} missing spec.rules"
        print(f"  [PASS] Policy syntax valid: {pf}")

def test_kyverno_test_suite():
    print("--> Test 3: Executing comprehensive Kyverno CLI test suite (kyverno test)...")
    test_yaml = os.path.join(TESTS_DIR, "kyverno-test.yaml")
    assert os.path.isfile(test_yaml), f"Missing {test_yaml}"
    
    res = run_command([KYVERNO_BIN, "test", TESTS_DIR])
    assert "Test Summary: 20 tests passed and 0 tests failed" in res.stdout, f"Test failure in summary:\n{res.stdout}"
    print("  [PASS] All 20 Kyverno test cases passed (10 positive, 10 negative assertions).")

def test_positive_workload_enforcement():
    print("--> Test 4: Verifying compliant workload passes all 10 security policies via kyverno apply...")
    pass_workload = os.path.join(TESTS_DIR, "pass-workload.yaml")
    policy_files = [f for f in os.listdir(KYVERNO_DIR) if f.endswith(".yaml") or f.endswith(".yml")]
    
    for pf in sorted(policy_files):
        p_path = os.path.join(KYVERNO_DIR, pf)
        res = run_command([KYVERNO_BIN, "apply", p_path, "--resource", pass_workload])
        assert "pass: 1, fail: 0" in res.stdout or "pass: 2, fail: 0" in res.stdout, f"Workload unexpectedly rejected by {pf}:\n{res.stdout}"
        print(f"  [PASS] Compliant workload passed {pf}")

def test_negative_workload_rejections():
    print("--> Test 5: Verifying deliberate violation workloads are strictly rejected by policies...")
    test_matrix = [
        ("disallow-privileged-containers.yaml", "fail-privileged.yaml", "Privileged mode is disallowed"),
        ("disallow-privilege-escalation.yaml", "fail-privilege-escalation.yaml", "Privilege escalation is disallowed"),
        ("require-run-as-non-root.yaml", "fail-run-as-root.yaml", "Running as root is disallowed"),
        ("require-drop-all-capabilities.yaml", "fail-capabilities.yaml", "Containers must drop all capabilities"),
        ("require-seccomp-default.yaml", "fail-seccomp.yaml", "Seccomp profile must be set to RuntimeDefault"),
        ("disallow-latest-tag.yaml", "fail-latest-tag.yaml", "Using the ':latest' tag is disallowed"),
        ("require-resource-requests-limits.yaml", "fail-resource-limits.yaml", "CPU and memory requests and limits must be specified"),
        ("disallow-host-namespaces.yaml", "fail-host-namespaces.yaml", "Sharing host network, PID, or IPC namespaces is disallowed"),
        ("restrict-image-registries.yaml", "fail-untrusted-registry.yaml", "Images must originate from approved registries"),
        ("require-security-labels.yaml", "fail-missing-labels.yaml", "Workloads must declare 'app.kubernetes.io/name' and 'forgeops.dev/security-tier' labels")
    ]
    
    for policy_file, fail_manifest, expected_msg in test_matrix:
        p_path = os.path.join(KYVERNO_DIR, policy_file)
        m_path = os.path.join(TESTS_DIR, fail_manifest)
        res = run_command([KYVERNO_BIN, "apply", p_path, "--resource", m_path], expect_zero=False)
        assert expected_msg in res.stdout or expected_msg in res.stderr, f"Missing expected error message '{expected_msg}' in:\n{res.stdout}\n{res.stderr}"
        print(f"  [PASS] Correctly rejected {fail_manifest} with: '{expected_msg}'")

def test_error_handling_and_fail_closed():
    print("--> Test 6: Verifying kyverno test fails closed on malformed test cases...")
    # Test that kyverno returns non-zero if a test fails
    temp_fail_dir = "/tmp/kyverno-fail-test"
    os.makedirs(temp_fail_dir, exist_ok=True)
    try:
        with open(os.path.join(temp_fail_dir, "policy.yaml"), "w") as f:
            f.write("""apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privileged
spec:
  validationFailureAction: Enforce
  rules:
    - name: check
      match:
        any:
          - resources:
              kinds: [Pod]
      validate:
        message: "No priv"
        pattern:
          spec:
            containers:
              - =(securityContext):
                  =(privileged): false
""")
        with open(os.path.join(temp_fail_dir, "pod.yaml"), "w") as f:
            f.write("""apiVersion: v1
kind: Pod
metadata:
  name: bad-pod
spec:
  containers:
    - name: app
      image: ghcr.io/test:1.0
      securityContext:
        privileged: true
""")
        with open(os.path.join(temp_fail_dir, "kyverno-test.yaml"), "w") as f:
            f.write("""apiVersion: cli.kyverno.io/v1alpha1
kind: Test
metadata:
  name: should-fail
policies: [policy.yaml]
resources: [pod.yaml]
results:
  - policy: disallow-privileged
    rule: check
    resources: [bad-pod]
    kind: Pod
    result: pass
""")
        res = subprocess.run([KYVERNO_BIN, "test", temp_fail_dir], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert res.returncode != 0, "kyverno test unexpectedly passed when expected result mismatch occurred!"
        print("  [PASS] kyverno test strictly returns non-zero code on test failure assertion.")
    finally:
        shutil.rmtree(temp_fail_dir, ignore_errors=True)

def main():
    print("=======================================================================")
    print("Starting Gate G14 Policy-as-Code (Kyverno) Validation Suite")
    print(f"Kyverno Binary: {KYVERNO_BIN}")
    print(f"Policy Directory: {KYVERNO_DIR}")
    print("=======================================================================")
    test_tool_version()
    test_policy_yaml_syntax()
    test_kyverno_test_suite()
    test_positive_workload_enforcement()
    test_negative_workload_rejections()
    test_error_handling_and_fail_closed()
    print("=======================================================================")
    print("ALL GATE G14 KYVERNO POLICY-AS-CODE TESTS PASSED (6/6 suites successful)")
    print("=======================================================================")

if __name__ == "__main__":
    main()

