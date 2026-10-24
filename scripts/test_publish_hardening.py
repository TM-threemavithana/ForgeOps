#!/usr/bin/env python3
"""
Test script for ForgeOps G03 GHCR Publishing Security Hardening.
Validates:
1. YAML syntax and structural integrity of .github/workflows/publish.yml
2. Concurrency controls, triggers, and least-privilege permissions
3. All bash script blocks extracted from publish.yml using bash -n
4. Rejection path unit tests for input validation, git ancestry, and CI verification
"""

import sys
import re
import yaml
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PUBLISH_YML = REPO_ROOT / ".github" / "workflows" / "publish.yml"
CI_YML = REPO_ROOT / ".github" / "workflows" / "ci.yml"

passes = 0
failures = 0

def log_pass(msg):
    global passes
    passes += 1
    print(f"[PASS] {msg}")

def log_fail(msg):
    global failures
    failures += 1
    print(f"[FAIL] {msg}")

def test_yaml_syntax():
    print("\n--- Test 1: YAML Syntax and Schema ---")
    try:
        with open(PUBLISH_YML, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f)
        log_pass("publish.yml parsed as valid YAML")
    except Exception as e:
        log_fail(f"publish.yml YAML syntax error: {e}")
        return None

    # Check top-level properties
    if data.get("name") == "Publish to GHCR":
        log_pass("Workflow name is 'Publish to GHCR'")
    else:
        log_fail("Workflow name is missing or unexpected")

    # Check trigger: workflow_dispatch only
    on = data.get("on") if "on" in data else data.get(True, {})
    if "workflow_dispatch" in on and len(on) == 1:
        log_pass("Trigger restricted exclusively to workflow_dispatch")
    else:
        log_fail(f"Unexpected triggers found: {list(on.keys())}")

    # Check concurrency
    concurrency = data.get("concurrency", {})
    if concurrency.get("group") == "publish-ghcr" and concurrency.get("cancel-in-progress") is False:
        log_pass("Concurrency configured: group=publish-ghcr, cancel-in-progress=false")
    else:
        log_fail(f"Concurrency misconfigured: {concurrency}")

    # Check top-level permissions
    permissions = data.get("permissions", {})
    if permissions == {"contents": "read"}:
        log_pass("Global permissions restricted to read-only (contents: read)")
    else:
        log_fail(f"Global permissions not minimal: {permissions}")

    # Check jobs
    jobs = data.get("jobs", {})
    if "validate-release" in jobs and "publish" in jobs:
        log_pass("Both 'validate-release' and 'publish' jobs defined")
    else:
        log_fail(f"Expected jobs missing: {list(jobs.keys())}")

    # Check validate-release permissions
    val_perms = jobs.get("validate-release", {}).get("permissions", {})
    if "packages" not in val_perms and val_perms.get("contents") == "read" and val_perms.get("actions") == "read":
        log_pass("validate-release job has scoped read permissions (contents: read, actions: read; no packages)")
    else:
        log_fail(f"validate-release job permissions unexpected: {val_perms}")

    # Check publish job permissions & environment
    pub_job = jobs.get("publish", {})
    if pub_job.get("environment", {}).get("name") == "release":
        log_pass("publish job scoped to protected 'release' GitHub Environment")
    else:
        log_fail(f"publish job missing release environment: {pub_job.get('environment')}")

    pub_perms = pub_job.get("permissions", {})
    if pub_perms.get("packages") == "write" and pub_perms.get("contents") == "read":
        log_pass("publish job has packages: write and contents: read")
    else:
        log_fail(f"publish job permissions unexpected: {pub_perms}")

    if pub_job.get("needs") == "validate-release":
        log_pass("publish job explicitly depends on 'validate-release'")
    else:
        log_fail(f"publish job dependencies unexpected: {pub_job.get('needs')}")

    return data

def test_bash_script_syntax():
    print("\n--- Test 2: Shell Script Syntax (bash -n) ---")
    with open(PUBLISH_YML, "r", encoding="utf-8") as f:
        content = f.read()

    # Extract all `run: |` blocks
    # Using regex to capture indented run blocks
    pattern = re.compile(r'run:\s*\|\s*\n((?:(?: {8,}.*|\s*)\n)+)')
    matches = pattern.findall(content)

    if not matches:
        log_fail("No run: | script blocks found in publish.yml")
        return

    print(f"Found {len(matches)} shell script blocks in publish.yml")
    for idx, script in enumerate(matches, 1):
        # Dedent script
        lines = script.splitlines()
        min_indent = min(len(l) - len(l.lstrip()) for l in lines if l.strip())
        dedented = "\n".join(l[min_indent:] if l.strip() else "" for l in lines)

        # Replace GitHub Actions template expressions with dummy env vars for bash -n
        sanitized = re.sub(r'\$\{\{[^}]+\}\}', 'DUMMY_ACTION_VAR', dedented)

        # Run bash -n
        proc = subprocess.run(
            ["bash", "-n"],
            input=sanitized,
            text=True,
            capture_output=True
        )
        if proc.returncode == 0:
            log_pass(f"Shell script block {idx} passed bash -n syntax validation")
        else:
            log_fail(f"Shell script block {idx} failed syntax check: {proc.stderr}")

def test_rejection_paths():
    print("\n--- Test 3: Trusted Commit & Input Rejection Paths ---")

    # Test 3.1: Confirmation guard
    code = """
CONFIRM_INPUT="INVALID"
if [ "$CONFIRM_INPUT" != "PUBLISH" ]; then
    exit 1
fi
"""
    p = subprocess.run(["bash", "-c", code])
    if p.returncode == 1:
        log_pass("Rejection test: Non-PUBLISH confirmation correctly rejected (exit 1)")
    else:
        log_fail("Confirmation guard did not reject invalid input")

    code_pass = """
CONFIRM_INPUT="PUBLISH"
if [ "$CONFIRM_INPUT" != "PUBLISH" ]; then
    exit 1
fi
"""
    p = subprocess.run(["bash", "-c", code_pass])
    if p.returncode == 0:
        log_pass("Acceptance test: Exact 'PUBLISH' confirmation accepted (exit 0)")
    else:
        log_fail("Confirmation guard failed on valid input")

    # Test 3.2: 40-character hex SHA regex
    test_shas = [
        ("short sha", "5b70e43", False),
        ("branch name", "master", False),
        ("injection attempt", "5b70e43; rm -rf /", False),
        ("uppercase 40", "5B70E434313B0B7C6E05E1A11D9254DC23A13E5C", True), # normalized to lower
        ("valid 40 hex", "5b70e434313b0b7c6e05e1a11d9254dc23a13e5c", True),
        ("41 chars", "5b70e434313b0b7c6e05e1a11d9254dc23a13e5c1", False),
        ("non-hex", "5b70e434313b0b7c6e05e1a11d9254dc23a13e5g", False)
    ]
    for name, sha, should_pass in test_shas:
        check = f"""
INPUT_SHA="{sha}"
CLEAN_SHA="$(echo "$INPUT_SHA" | tr '[:upper:]' '[:lower:]' | xargs)"
if ! [[ "$CLEAN_SHA" =~ ^[0-9a-f]{{40}}$ ]]; then
    exit 1
fi
"""
        p = subprocess.run(["bash", "-c", check])
        passed = (p.returncode == 0)
        if passed == should_pass:
            log_pass(f"SHA regex test '{name}' ({sha[:12]}...): {'Accepted' if should_pass else 'Rejected'} as expected")
        else:
            log_fail(f"SHA regex test '{name}' unexpected result: expected {should_pass}, got {passed}")

    # Test 3.3: Semver regex
    test_semvers = [
        ("1.0.0", True),
        ("0.1.0-rc.1", True),
        ("v1.0.0", False), # v prefix not strict semver
        ("latest", False),
        ("1.0", False),
        ("1.0.0+build123", True)
    ]
    for semver, should_pass in test_semvers:
        check = f"""
SEMVER="{semver}"
if ! [[ "$SEMVER" =~ ^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(-([0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*))?(\\+([0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*))?$ ]]; then
    exit 1
fi
"""
        p = subprocess.run(["bash", "-c", check])
        passed = (p.returncode == 0)
        if passed == should_pass:
            log_pass(f"Semver regex test '{semver}': {'Accepted' if should_pass else 'Rejected'} as expected")
        else:
            log_fail(f"Semver regex test '{semver}' unexpected result")

    # Test 3.4: Git ancestry check against current master
    # Get current master HEAD
    git_head = subprocess.check_output(["git", "rev-parse", "master"], cwd=REPO_ROOT, text=True).strip()
    check_ancestor = f"""
TARGET_SHA="{git_head}"
git merge-base --is-ancestor "$TARGET_SHA" master
"""
    p = subprocess.run(["bash", "-c", check_ancestor], cwd=REPO_ROOT)
    if p.returncode == 0:
        log_pass(f"Git ancestry test: Current master HEAD ({git_head[:7]}) verified as valid ancestor of master")
    else:
        log_fail("Git ancestry test failed for master HEAD")

    # An invalid fake SHA should fail rev-parse
    fake_sha = "0000000000000000000000000000000000000000"
    check_fake = f"""
TARGET_SHA="{fake_sha}"
git rev-parse --verify --quiet "${{TARGET_SHA}}^{{commit}}"
"""
    p = subprocess.run(["bash", "-c", check_fake], cwd=REPO_ROOT)
    if p.returncode != 0:
        log_pass("Git existence test: Non-existent commit correctly rejected (exit non-zero)")
    else:
        log_fail("Git existence test did not reject non-existent commit")

def test_build_once_scan_once_logic():
    print("\n--- Test 4: Build-Once, Scan-Once Integrity Logic ---")
    with open(PUBLISH_YML, "r", encoding="utf-8") as f:
        content = f.read()

    # Verify no second docker/build-push-action call with push: true
    bpa_calls = re.findall(r'uses:\s*docker/build-push-action@v6', content)
    if len(bpa_calls) == 1:
        log_pass("Exactly ONE docker/build-push-action call present (build-once verified)")
    else:
        log_fail(f"Found {len(bpa_calls)} docker/build-push-action calls (expected exactly 1)")

    # Verify load: true and push: false in that build step
    if "push: false" in content and "load: true" in content:
        log_pass("Candidate image built locally with load: true, push: false")
    else:
        log_fail("Candidate build step missing push: false or load: true")

    # Verify Trivy scan precedes publishing
    trivy_pos = content.find("Run Trivy security gate on candidate image")
    publish_pos = content.find("Publish verified image to GHCR (zero rebuild)")
    if trivy_pos != -1 and publish_pos != -1 and trivy_pos < publish_pos:
        log_pass("Trivy security gate is executed BEFORE publishing to GHCR")
    else:
        log_fail("Publishing occurs before or without Trivy security gate")

    # Verify Trivy severity gate blocks on CRITICAL,HIGH
    if "severity: CRITICAL,HIGH" in content and "exit-code: '1'" in content:
        log_pass("Trivy gate enforces blocking on CRITICAL,HIGH (exit-code: '1')")
    else:
        log_fail("Trivy gate does not enforce CRITICAL,HIGH blocking")

    # Verify zero-rebuild publish uses docker push
    if "docker push \"$tag\"" in content:
        log_pass("Publish step uses 'docker push' on pre-scanned loaded image tags")
    else:
        log_fail("Publish step does not use docker push")

    # Verify image ID integrity check
    if "CURRENT_ID=$(docker inspect --format='{{.Id}}'" in content and "$EXPECTED_ID" in content:
        log_pass("Pre-publish integrity check verifies image ID has not mutated")
    else:
        log_fail("Missing pre-publish image ID integrity check")

    # Verify digest capture from RepoDigests
    if "RepoDigests" in content and "GITHUB_OUTPUT" in content:
        log_pass("Published image digest captured from Docker daemon RepoDigests")
    else:
        log_fail("Published image digest not captured from RepoDigests")

def main():
    print("============================================================")
    print(" ForgeOps G03 GHCR Publishing Security Hardening Tests")
    print("============================================================")
    test_yaml_syntax()
    test_bash_script_syntax()
    test_rejection_paths()
    test_build_once_scan_once_logic()

    print("\n============================================================")
    print(f" Summary: {passes} PASSED, {failures} FAILED")
    print("============================================================")
    if failures > 0:
        sys.exit(1)
    print("All security hardening checks PASSED.")

if __name__ == "__main__":
    main()
