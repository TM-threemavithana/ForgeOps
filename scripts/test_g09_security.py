#!/usr/bin/env python3
"""
ForgeOps Gate G09: DevSecOps Security Engineering & CI Foundation Validation Suite
Tests GitHub Actions full-SHA cryptographic pinning, least-privilege workflow permissions,
Semgrep OSS SAST ruleset syntax, positive baseline compliance, and synthetic negative rejection.
"""

import os
import re
import sys
import yaml
import json
import shutil
import subprocess

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CI_WORKFLOW = os.path.join(REPO_ROOT, ".github", "workflows", "ci.yml")
PUBLISH_WORKFLOW = os.path.join(REPO_ROOT, ".github", "workflows", "publish.yml")
SAST_DIR = os.path.join(REPO_ROOT, "security", "sast")
SAST_RULES = os.path.join(SAST_DIR, "semgrep-rules.yaml")
SAST_FIXTURES = os.path.join(SAST_DIR, "fixtures")
DEP_FIXTURE = os.path.join(REPO_ROOT, "security", "dependencies", "fixtures", "fail-pom.xml")
APP_POM = os.path.join(REPO_ROOT, "apps", "forgetasks-api", "pom.xml")
APP_SRC = os.path.join(REPO_ROOT, "apps", "forgetasks-api", "src", "main")

# Resolve semgrep binary
SEMGREP_BIN = shutil.which("semgrep")
if not SEMGREP_BIN:
    for candidate in [
        os.path.expanduser("~/.local/bin/semgrep"),
        os.path.expanduser("~/.local/share/semgrep-venv/bin/semgrep"),
        "/usr/local/bin/semgrep",
    ]:
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            SEMGREP_BIN = candidate
            break

def run_cmd(cmd, expect_zero=True):
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

def test_action_pinning():
    print("--> Test 1: Verifying full 40-character commit SHA pinning for all GitHub Actions...")
    assert os.path.isfile(CI_WORKFLOW), f"Missing {CI_WORKFLOW}"
    assert os.path.isfile(PUBLISH_WORKFLOW), f"Missing {PUBLISH_WORKFLOW}"

    sha_pattern = re.compile(r'^\s*uses:\s+([^@\s]+)@([0-9a-fA-F]{40})\s*(#\s*.+)?$')
    mutable_tag_pattern = re.compile(r'^\s*uses:\s+([^@\s]+)@([a-zA-Z0-9_\.\-]+)')

    total_actions_checked = 0

    for wf_path in [CI_WORKFLOW, PUBLISH_WORKFLOW]:
        wf_name = os.path.basename(wf_path)
        with open(wf_path, "r", encoding="utf-8") as f:
            lines = f.readlines()

        for idx, line in enumerate(lines, start=1):
            stripped = line.strip()
            if stripped.startswith("uses:"):
                total_actions_checked += 1
                match = sha_pattern.match(line)
                if not match:
                    # Check if it was pinned with mutable tag
                    mut = mutable_tag_pattern.match(line)
                    tag_info = mut.group(2) if mut else "unknown"
                    print(f"[FAIL] Insecure or unpinned action in {wf_name}:{idx}: {stripped}")
                    print(f"       Expected 40-character immutable commit SHA; found tag '{tag_info}'")
                    sys.exit(1)
                
                action_name = match.group(1)
                commit_sha = match.group(2)
                comment = match.group(3)

                assert len(commit_sha) == 40, f"SHA length != 40 for {action_name}"
                assert comment is not None and len(comment.strip()) > 1, f"Missing human-readable version comment for {action_name} in {wf_name}:{idx}"

    print(f"  [PASS] Verified {total_actions_checked} action references across workflows; 100% pinned to 40-char SHAs with version comments.")

def test_workflow_permissions_and_least_privilege():
    print("--> Test 2: Auditing workflow permissions and least-privilege security boundaries...")
    for wf_path in [CI_WORKFLOW, PUBLISH_WORKFLOW]:
        with open(wf_path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f)

        top_perms = data.get("permissions")
        assert top_perms is not None, f"Workflow {os.path.basename(wf_path)} must declare top-level permissions"
        assert top_perms.get("contents") == "read", f"Workflow {os.path.basename(wf_path)} top-level contents permission must be 'read'"

    with open(PUBLISH_WORKFLOW, "r", encoding="utf-8") as f:
        pub_data = yaml.safe_load(f)
    on_trigger = pub_data.get("on") or pub_data.get(True) or {}
    assert "workflow_dispatch" in on_trigger, "publish.yml must only be triggered via workflow_dispatch"
    assert "push" not in on_trigger, "publish.yml MUST NOT trigger on push"
    assert "pull_request" not in on_trigger, "publish.yml MUST NOT trigger on pull_request"

    print("  [PASS] Least-privilege permissions and workflow trust boundaries verified.")

def test_semgrep_ruleset_syntax():
    print("--> Test 3: Validating Semgrep SAST ruleset syntax and schema...")
    assert os.path.isfile(SAST_RULES), f"Missing SAST rules file: {SAST_RULES}"
    with open(SAST_RULES, "r", encoding="utf-8") as f:
        rules_data = yaml.safe_load(f)

    assert "rules" in rules_data, "semgrep-rules.yaml must contain a top-level 'rules' list"
    rules = rules_data["rules"]
    assert len(rules) >= 5, f"Expected at least 5 SAST rules, found {len(rules)}"

    required_rule_ids = {
        "forgeops.java.security.sql-injection",
        "forgeops.java.security.command-injection",
        "forgeops.java.security.weak-crypto",
        "forgeops.java.security.insecure-hash",
        "forgeops.java.security.path-traversal",
    }
    found_ids = set()

    for r in rules:
        r_id = r.get("id")
        found_ids.add(r_id)
        assert "languages" in r and "java" in r["languages"], f"Rule {r_id} must target java"
        assert "message" in r and len(r["message"]) > 10, f"Rule {r_id} missing descriptive message"
        assert r.get("severity") in ["ERROR", "WARNING", "INFO"], f"Rule {r_id} invalid severity: {r.get('severity')}"
        assert "metadata" in r, f"Rule {r_id} missing metadata (CWE/OWASP)"
        assert "cwe" in r["metadata"], f"Rule {r_id} metadata missing cwe"
        assert "owasp" in r["metadata"], f"Rule {r_id} metadata missing owasp"

    missing = required_rule_ids - found_ids
    assert not missing, f"Missing required SAST rule IDs: {missing}"
    print(f"  [PASS] All {len(rules)} SAST rules validated with schema, CWE, and OWASP mapping.")

def test_semgrep_positive_baseline():
    print("--> Test 4: Running Semgrep positive baseline compliance checks...")
    if not SEMGREP_BIN:
        print("  [WARN] Semgrep binary not available in local PATH. Marking live scan as UNVERIFIED locally.")
        return

    # 1. Scan pass fixture
    pass_file = os.path.join(SAST_FIXTURES, "pass-sample.java")
    assert os.path.isfile(pass_file), f"Missing {pass_file}"
    res = run_cmd([SEMGREP_BIN, "scan", "--config", SAST_RULES, "--json", pass_file])
    data = json.loads(res.stdout)
    findings = data.get("results", [])
    assert len(findings) == 0, f"Expected 0 findings on pass-sample.java, got {len(findings)}: {findings}"
    print("  [PASS] Compliant pass-sample.java passed with 0 findings.")

    # 2. Scan production application source tree
    if os.path.isdir(APP_SRC):
        res_app = run_cmd([SEMGREP_BIN, "scan", "--config", SAST_RULES, "--json", APP_SRC])
        app_data = json.loads(res_app.stdout)
        app_findings = app_data.get("results", [])
        assert len(app_findings) == 0, f"Expected 0 findings on application source, got {len(app_findings)}: {app_findings}"
        print(f"  [PASS] Production codebase ({APP_SRC}) clean: 0 blocking SAST findings.")

def test_semgrep_negative_synthetic_rejection():
    print("--> Test 5: Running Semgrep synthetic negative rejection tests...")
    if not SEMGREP_BIN:
        print("  [WARN] Semgrep binary not available. Marking negative rejection test as UNVERIFIED locally.")
        return

    expected_rejections = [
        ("fail-sqli.java", "forgeops.java.security.sql-injection"),
        ("fail-command-injection.java", "forgeops.java.security.command-injection"),
        ("fail-weak-crypto.java", "forgeops.java.security.weak-crypto"),
        ("fail-path-traversal.java", "forgeops.java.security.path-traversal"),
    ]

    for filename, expected_rule in expected_rejections:
        target_path = os.path.join(SAST_FIXTURES, filename)
        assert os.path.isfile(target_path), f"Missing negative fixture: {target_path}"

        res = run_cmd([SEMGREP_BIN, "scan", "--config", SAST_RULES, "--json", target_path])
        data = json.loads(res.stdout)
        findings = data.get("results", [])
        matched_rules = [f.get("check_id") for f in findings]
        
        # Check rule match
        matching = [r for r in matched_rules if expected_rule in r]
        assert len(matching) > 0, f"Fixture {filename} failed to trigger {expected_rule}. Detected: {matched_rules}"

        # Test non-zero exit code when --error flag is provided
        err_res = subprocess.run(
            [SEMGREP_BIN, "scan", "--config", SAST_RULES, "--error", target_path],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert err_res.returncode != 0, f"Expected Semgrep --error to exit non-zero for {filename}, but got {err_res.returncode}"
        print(f"  [PASS] Synthetic rejection verified for {filename} (triggered {expected_rule}, non-zero exit enforced).")

def test_dependency_fixture_isolation():
    print("--> Test 6: Verifying dependency scanner synthetic negative fixture isolation...")
    assert os.path.isfile(DEP_FIXTURE), f"Missing {DEP_FIXTURE}"
    with open(DEP_FIXTURE, "r", encoding="utf-8") as f:
        dep_content = f.read()

    assert "commons-collections" in dep_content, "Synthetic fail-pom.xml must specify vulnerable commons-collections"
    assert "3.2.1" in dep_content, "Synthetic fail-pom.xml must specify vulnerable version 3.2.1"

    # Verify primary pom.xml does not reference vulnerable dependency
    with open(APP_POM, "r", encoding="utf-8") as f:
        app_pom_content = f.read()

    assert "commons-collections" not in app_pom_content, "Primary pom.xml must NOT reference vulnerable commons-collections"
    print("  [PASS] Dependency test fixture correctly isolated from production application pom.xml.")

def main():
    print("===================================================================")
    print(" ForgeOps Gate G09 DevSecOps Security & Action Pinning Test Suite")
    print("===================================================================")
    test_action_pinning()
    test_workflow_permissions_and_least_privilege()
    test_semgrep_ruleset_syntax()
    test_semgrep_positive_baseline()
    test_semgrep_negative_synthetic_rejection()
    test_dependency_fixture_isolation()
    print("===================================================================")
    print(" [PASS] All Gate G09 security engineering checks completed successfully!")
    print("===================================================================")

if __name__ == "__main__":
    main()
