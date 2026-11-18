#!/usr/bin/env python3
"""
Regenerates all live admission evidence artifacts for Gate G09.4.
Executes live admission tests against the isolated forgeops-g09-security cluster.
Captures authentic API server and Kyverno webhook admission responses.
"""

import json
import os
import subprocess
import sys
import time

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
EVIDENCE_DIR = os.path.join(REPO_ROOT, "docs", "evidence", "G09", "admission-evidence")
os.makedirs(EVIDENCE_DIR, exist_ok=True)

KUBECONFIG = os.path.expanduser("~/.kube/config-g09-security")


def run_cmd(cmd_list, check=False, input_data=None):
    env = os.environ.copy()
    env["KUBECONFIG"] = KUBECONFIG
    res = subprocess.run(cmd_list, input=input_data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    if check and res.returncode != 0:
        raise RuntimeError(f"Command failed ({res.returncode}): {' '.join(cmd_list)}\n{res.stderr}\n{res.stdout}")
    return res


def main():
    print("===================================================================")
    print(" ForgeOps G09.4 Admission Evidence Regeneration Engine")
    print("===================================================================")

    # 0. Preflight checks
    res = run_cmd(["kubectl", "config", "current-context"])
    if res.returncode != 0:
        print(f"[FAIL] Unable to connect to cluster with KUBECONFIG={KUBECONFIG}")
        sys.exit(1)
    context = res.stdout.strip()
    print(f"[INFO] Active Kubernetes context: {context}")
    assert context == "kind-forgeops-g09-security", f"Unexpected context: {context}"

    # 1. Capture Webhook Readiness Evidence
    print("\n--> 1. Generating webhook readiness evidence...")
    pods = run_cmd(["kubectl", "get", "pods", "-n", "kyverno", "-o", "wide"], check=True).stdout
    vwc = run_cmd(["kubectl", "get", "validatingwebhookconfigurations"], check=True).stdout
    nvp = run_cmd(["kubectl", "get", "namespacedvalidatingpolicies", "-n", "forgeops-g09-kyverno"], check=True).stdout
    ep = run_cmd(["kubectl", "get", "endpoints", "-n", "kyverno"], check=True).stdout

    webhook_evidence = f"""# ForgeOps G09.4 Kyverno Admission Controller & Webhook Readiness
Date: {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}
Cluster: forgeops-g09-security
Context: {context}

=== Kyverno Admission Controller Pods (namespace: kyverno) ===
{pods}

=== ValidatingWebhookConfigurations ===
{vwc}

=== NamespacedValidatingPolicy Resources (namespace: forgeops-g09-kyverno) ===
{nvp}

=== Kyverno Service Endpoints ===
{ep}
"""
    with open(os.path.join(EVIDENCE_DIR, "webhook-readiness.txt"), "w", encoding="utf-8") as f:
        f.write(webhook_evidence)
    print("  [PASS] webhook-readiness.txt generated.")

    # 2. PSA Tests
    print("\n--> 2. Executing PSA Restricted admission tests (namespace: forgeops-g09-psa)...")
    run_cmd(["kubectl", "delete", "pods", "--all", "-n", "forgeops-g09-psa", "--grace-period=0", "--force"])

    psa_fixtures = [
        ("fail-privileged.yaml", "psa-privileged-rejection.txt", "Privileged & Privilege Escalation"),
        ("fail-host-namespaces.yaml", "psa-host-namespaces-rejection.txt", "Host Namespaces (hostNetwork/hostPID/hostIPC)"),
        ("fail-hostpath.yaml", "psa-hostpath-rejection.txt", "hostPath Volume Mount"),
        ("fail-missing-security-context.yaml", "psa-missing-context-rejection.txt", "Missing Restricted SecurityContext"),
    ]

    for fix_file, ev_file, desc in psa_fixtures:
        fix_path = os.path.join(REPO_ROOT, "tests", "fixtures", "security", "admission", "psa", fix_file)
        print(f"  Testing negative fixture: {fix_file} ({desc})...")
        res = run_cmd(["kubectl", "create", "-f", fix_path])
        assert res.returncode != 0, f"Expected rejection for {fix_file}, but succeeded!"
        err_out = res.stderr or res.stdout
        assert "violates PodSecurity" in err_out and "restricted" in err_out, f"Unexpected error message: {err_out}"

        content = f"""# ForgeOps Gate G09.4 Live Admission Evidence: PSA Restricted Rejection
Fixture: tests/fixtures/security/admission/psa/{fix_file}
Description: Rejection of {desc}
Namespace: forgeops-g09-psa
Date: {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}
Exit Code: {res.returncode} (Admission Rejected)

--- Command Executed ---
kubectl create -f tests/fixtures/security/admission/psa/{fix_file}

--- Raw API Server Response ---
{err_out}

--- Zero-Pod-Leakage Verification ---
Pods in forgeops-g09-psa:
{run_cmd(['kubectl', 'get', 'pods', '-n', 'forgeops-g09-psa']).stdout}
"""
        with open(os.path.join(EVIDENCE_DIR, ev_file), "w", encoding="utf-8") as f:
            f.write(content)
        print(f"  [PASS] {ev_file} captured.")

    # PSA Positive Workload
    print("  Testing positive compliant fixture: pass-restricted-workload.yaml...")
    pass_fix = os.path.join(REPO_ROOT, "tests", "fixtures", "security", "admission", "psa", "pass-restricted-workload.yaml")
    res = run_cmd(["kubectl", "create", "-f", pass_fix], check=True)
    time.sleep(6)  # Workload sleeps 5s then completes

    pod_desc = run_cmd(["kubectl", "describe", "pod", "test-psa-pass-restricted", "-n", "forgeops-g09-psa"]).stdout
    pod_logs = run_cmd(["kubectl", "logs", "test-psa-pass-restricted", "-n", "forgeops-g09-psa"]).stdout
    pod_get = run_cmd(["kubectl", "get", "pod", "test-psa-pass-restricted", "-n", "forgeops-g09-psa", "-o", "wide"]).stdout

    psa_pass_content = f"""# ForgeOps Gate G09.4 Live Admission Evidence: PSA Restricted Workload Compliant Acceptance
Fixture: tests/fixtures/security/admission/psa/pass-restricted-workload.yaml
Namespace: forgeops-g09-psa
Date: {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}
Exit Code: 0 (Admission Accepted & Executed)

--- Command Executed ---
kubectl create -f tests/fixtures/security/admission/psa/pass-restricted-workload.yaml

--- Pod Execution Status ---
{pod_get}

--- Pod Logs ---
{pod_logs}

--- Pod Describe Details ---
{pod_desc}
"""
    with open(os.path.join(EVIDENCE_DIR, "psa-compliant-acceptance.txt"), "w", encoding="utf-8") as f:
        f.write(psa_pass_content)
    run_cmd(["kubectl", "delete", "pod", "test-psa-pass-restricted", "-n", "forgeops-g09-psa", "--grace-period=0", "--force"])
    print("  [PASS] psa-compliant-acceptance.txt captured.")

    # 3. Kyverno Pod Tests
    print("\n--> 3. Executing Kyverno CEL admission tests on Pods (namespace: forgeops-g09-kyverno)...")
    run_cmd(["kubectl", "delete", "pods", "--all", "-n", "forgeops-g09-kyverno", "--grace-period=0", "--force"])

    kyv_fixtures = [
        ("fail-mutable-tag.yaml", "kyverno-mutable-tag-rejection.txt", "require-image-digest", "Mutable Image Tag"),
        ("fail-hostpath.yaml", "kyverno-hostpath-rejection.txt", "disallow-hostpath", "hostPath Volume Mount"),
        ("fail-privileged.yaml", "kyverno-privileged-rejection.txt", "disallow-privileged-workloads", "Privileged Container"),
        ("fail-security-context.yaml", "kyverno-security-context-rejection.txt", "require-restricted-security-context", "Missing Restricted SecurityContext"),
        ("fail-initcontainer-nonroot.yaml", "kyverno-initcontainer-nonroot-rejection.txt", "require-restricted-security-context", "Insecure InitContainer Non-Root Override"),
        ("fail-initcontainer-seccomp.yaml", "kyverno-initcontainer-seccomp-rejection.txt", "require-restricted-security-context", "Insecure InitContainer Seccomp Override"),
        ("fail-fake-digest-image.yaml", "kyverno-fake-digest-rejection.txt", "require-image-digest", "Malformed Fake Digest Image Containing @sha256: Substring"),
        ("fail-non-sha256-digest-image.yaml", "kyverno-non-sha256-digest-rejection.txt", "require-image-digest", "Non-SHA256 Valid Digest Image"),
    ]

    for fix_file, ev_file, pol_name, desc in kyv_fixtures:
        fix_path = os.path.join(REPO_ROOT, "tests", "fixtures", "security", "admission", "kyverno", fix_file)
        print(f"  Testing negative fixture: {fix_file} ({desc})...")
        res = run_cmd(["kubectl", "create", "-f", fix_path])
        assert res.returncode != 0, f"Expected webhook rejection for {fix_file}, but succeeded!"
        err_out = res.stderr or res.stdout
        assert "denied the request" in err_out and pol_name in err_out, f"Unexpected webhook error: {err_out}"

        content = f"""# ForgeOps Gate G09.4 Live Admission Evidence: Kyverno CEL Webhook Rejection
Policy: {pol_name}
Fixture: tests/fixtures/security/admission/kyverno/{fix_file}
Description: Admission Rejection of {desc}
Namespace: forgeops-g09-kyverno
Date: {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}
Exit Code: {res.returncode} (Admission Webhook Denied)

--- Command Executed ---
kubectl create -f tests/fixtures/security/admission/kyverno/{fix_file}

--- Raw Webhook Response ---
{err_out}

--- Zero-Pod-Leakage Verification ---
Pods in forgeops-g09-kyverno:
{run_cmd(['kubectl', 'get', 'pods', '-n', 'forgeops-g09-kyverno']).stdout}
"""
        with open(os.path.join(EVIDENCE_DIR, ev_file), "w", encoding="utf-8") as f:
            f.write(content)
        print(f"  [PASS] {ev_file} captured.")

    # Ephemeral Container Security Enforcement Tests:
    # 1. Static Kyverno CLI evaluation
    # 2. Kubernetes API creation restriction
    # 3. Live subresource webhook rejections against active running base pod
    # 4. Live compliant ephemeral container admission & runtime execution
    print("  Testing ephemeral container admission security (CLI, API creation, and live subresource webhook)...")
    eph_path = os.path.join(REPO_ROOT, "tests", "fixtures", "security", "admission", "kyverno", "fail-ephemeral-container.yaml")
    pol_dir = os.path.join(REPO_ROOT, "security", "admission", "kyverno", "policies")

    # Section 1: Static Kyverno CLI evaluation
    cli_res = subprocess.run(["kyverno", "apply", pol_dir, "--resource", eph_path, "--warnings-as-errors"],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert cli_res.returncode != 0, f"Expected CLI rejection for {eph_path}"

    # Section 2: Kubernetes API creation restriction
    k8s_create_res = run_cmd(["kubectl", "create", "-f", eph_path])
    assert k8s_create_res.returncode != 0, "Expected API server rejection of spec.ephemeralContainers on creation"
    assert "cannot be set on create" in (k8s_create_res.stderr or k8s_create_res.stdout)

    # Section 3 & 4: Live ephemeral container subresource tests against running base pod
    base_pod_name = "test-kyverno-ephemeral-base"
    run_cmd(["kubectl", "delete", "pod", base_pod_name, "-n", "forgeops-g09-kyverno", "--grace-period=0", "--force"])

    base_pod_yaml = f"""apiVersion: v1
kind: Pod
metadata:
  name: {base_pod_name}
  namespace: forgeops-g09-kyverno
  labels:
    app.kubernetes.io/name: {base_pod_name}
    forgeops.dev/fixture: ephemeral-base
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: base-container
      image: alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc
      command: ["sh", "-c", "sleep 300"]
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        runAsNonRoot: true
        runAsUser: 10001
        capabilities:
          drop:
            - ALL
"""
    run_cmd(["kubectl", "apply", "-f", "-"], check=True, input_data=base_pod_yaml)

    # Wait for base pod to be Running
    base_running = False
    for _ in range(30):
        phase_res = run_cmd(["kubectl", "get", "pod", base_pod_name, "-n", "forgeops-g09-kyverno", "-o", "jsonpath={.status.phase}"])
        if phase_res.stdout.strip() == "Running":
            base_running = True
            break
        time.sleep(1)
    assert base_running, "Base pod failed to reach Running state"

    # Negative Test A: Insecure Security Context (allowPrivilegeEscalation=true, runAsNonRoot=false)
    patch_sec = {
        "spec": {
            "ephemeralContainers": [
                {
                    "name": "insecure-debug-sec",
                    "image": "alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc",
                    "securityContext": {
                        "allowPrivilegeEscalation": True,
                        "runAsNonRoot": False
                    }
                }
            ]
        }
    }
    res_patch_sec = run_cmd([
        "kubectl", "patch", "pod", base_pod_name, "-n", "forgeops-g09-kyverno",
        "--subresource=ephemeralcontainers", "--type=strategic",
        "-p", json.dumps(patch_sec)
    ])
    assert res_patch_sec.returncode != 0, "Expected Kyverno webhook rejection for insecure ephemeral securityContext"
    err_sec = res_patch_sec.stderr or res_patch_sec.stdout
    assert "denied the request" in err_sec and ("require-restricted-security-context" in err_sec or "disallow-privileged-workloads" in err_sec)

    # Negative Test B: Insecure Image Reference (Mutable Tag 'alpine:3.20')
    patch_tag = {
        "spec": {
            "ephemeralContainers": [
                {
                    "name": "insecure-debug-tag",
                    "image": "alpine:3.20",
                    "securityContext": {
                        "allowPrivilegeEscalation": False,
                        "runAsNonRoot": True,
                        "capabilities": {"drop": ["ALL"]}
                    }
                }
            ]
        }
    }
    res_patch_tag = run_cmd([
        "kubectl", "patch", "pod", base_pod_name, "-n", "forgeops-g09-kyverno",
        "--subresource=ephemeralcontainers", "--type=strategic",
        "-p", json.dumps(patch_tag)
    ])
    assert res_patch_tag.returncode != 0, "Expected Kyverno webhook rejection for mutable tag on ephemeral container"
    err_tag = res_patch_tag.stderr or res_patch_tag.stdout
    assert "denied the request" in err_tag and "require-image-digest" in err_tag

    # Negative Test C: Insecure Image Reference (Non-SHA256 Valid Digest 'alpine:3.20@sha512:...')
    patch_sha512 = {
        "spec": {
            "ephemeralContainers": [
                {
                    "name": "insecure-debug-sha512",
                    "image": "alpine:3.20@sha512:cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e",
                    "securityContext": {
                        "allowPrivilegeEscalation": False,
                        "runAsNonRoot": True,
                        "capabilities": {"drop": ["ALL"]}
                    }
                }
            ]
        }
    }
    res_patch_sha512 = run_cmd([
        "kubectl", "patch", "pod", base_pod_name, "-n", "forgeops-g09-kyverno",
        "--subresource=ephemeralcontainers", "--type=strategic",
        "-p", json.dumps(patch_sha512)
    ])
    assert res_patch_sha512.returncode != 0, "Expected Kyverno webhook rejection for non-SHA256 digest on ephemeral container"
    err_sha512 = res_patch_sha512.stderr or res_patch_sha512.stdout
    assert "denied the request" in err_sha512 and "require-image-digest" in err_sha512

    # Integrity Check: Confirming Target Pod remains intact with zero ephemeral containers
    check_intact = run_cmd(["kubectl", "get", "pod", base_pod_name, "-n", "forgeops-g09-kyverno", "-o", "jsonpath={.spec.ephemeralContainers}"])
    assert check_intact.stdout.strip() in ["", "[]", "null"], f"Base pod unexpectedly modified: {check_intact.stdout}"

    # Section 4: Live Compliant Ephemeral Container Update
    patch_pos = {
        "spec": {
            "ephemeralContainers": [
                {
                    "name": "compliant-debug",
                    "image": "alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc",
                    "command": ["sh", "-c", "echo 'Compliant ephemeral active' && sleep 30"],
                    "securityContext": {
                        "allowPrivilegeEscalation": False,
                        "runAsNonRoot": True,
                        "seccompProfile": {
                            "type": "RuntimeDefault"
                        },
                        "capabilities": {
                            "drop": ["ALL"]
                        }
                    }
                }
            ]
        }
    }
    res_patch_pos = run_cmd([
        "kubectl", "patch", "pod", base_pod_name, "-n", "forgeops-g09-kyverno",
        "--subresource=ephemeralcontainers", "--type=strategic",
        "-p", json.dumps(patch_pos)
    ])
    assert res_patch_pos.returncode == 0, f"Compliant ephemeral container patch was unexpectedly rejected: {res_patch_pos.stderr}"

    time.sleep(3)
    eph_spec_res = run_cmd(["kubectl", "get", "pod", base_pod_name, "-n", "forgeops-g09-kyverno", "-o", "jsonpath={.spec.ephemeralContainers[*].name}"])
    assert "compliant-debug" in eph_spec_res.stdout, f"Ephemeral container not found in pod spec: {eph_spec_res.stdout}"

    eph_status_res = run_cmd(["kubectl", "get", "pod", base_pod_name, "-n", "forgeops-g09-kyverno", "-o", "jsonpath={.status.ephemeralContainerStatuses}"])

    eph_content = f"""# ForgeOps Gate G09.4 Live Admission Evidence: Ephemeral Container Security Enforcement
Fixture: tests/fixtures/security/admission/kyverno/fail-ephemeral-container.yaml
Namespace: forgeops-g09-kyverno
Target Subresource: pods/ephemeralcontainers
Date: {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}

===================================================================
=== Section 1: Static Kyverno Policy Engine Evaluation (CLI)    ===
===================================================================
Command: kyverno apply security/admission/kyverno/policies/ --resource tests/fixtures/security/admission/kyverno/fail-ephemeral-container.yaml --warnings-as-errors
Exit Code: {cli_res.returncode} (Policy Rejection Enforced)
Output:
{cli_res.stdout.strip()}

===================================================================
=== Section 2: Kubernetes API Core Creation Restriction         ===
===================================================================
Command: kubectl create -f tests/fixtures/security/admission/kyverno/fail-ephemeral-container.yaml
Exit Code: {k8s_create_res.returncode} (API Server Schema Rejection)
Output:
{k8s_create_res.stderr.strip()}
Technical Note: The Kubernetes API server strictly forbids setting 'spec.ephemeralContainers' during initial Pod creation ('Forbidden: cannot be set on create'). Ephemeral containers can only be attached to running pods via the '/ephemeralcontainers' subresource.

===================================================================
=== Section 3: Live Subresource Dynamic Webhook Rejection       ===
===================================================================
Target Pod: {base_pod_name} (Status: Running)
Subresource: pods/ephemeralcontainers
Webhook Config: kyverno-resource-validating-webhook-cfg (rule: pods/ephemeralcontainers -> UPDATE)

--> Negative Test A: Insecure Security Context (allowPrivilegeEscalation=true, runAsNonRoot=false)
Command: kubectl patch pod {base_pod_name} --subresource=ephemeralcontainers --type=strategic -p '<insecure-sec-context>'
Exit Code: {res_patch_sec.returncode} (Dynamic Admission Webhook Denied)
Raw Webhook Response:
{err_sec.strip()}

--> Negative Test B: Insecure Image Reference (Mutable Tag 'alpine:3.20')
Command: kubectl patch pod {base_pod_name} --subresource=ephemeralcontainers --type=strategic -p '<mutable-tag-image>'
Exit Code: {res_patch_tag.returncode} (Dynamic Admission Webhook Denied)
Raw Webhook Response:
{err_tag.strip()}

--> Negative Test C: Insecure Image Reference (Non-SHA256 Digest 'alpine:3.20@sha512:...')
Command: kubectl patch pod {base_pod_name} --subresource=ephemeralcontainers --type=strategic -p '<non-sha256-image>'
Exit Code: {res_patch_sha512.returncode} (Dynamic Admission Webhook Denied)
Raw Webhook Response:
{err_sha512.strip()}

--> Integrity Check: Confirming Target Pod Remains Intact
Command: kubectl get pod {base_pod_name} -o jsonpath='{{.spec.ephemeralContainers}}'
Output: '{check_intact.stdout.strip()}' (Zero Insecure Ephemeral Containers Admitted)

===================================================================
=== Section 4: Live Compliant Ephemeral-Container Update        ===
===================================================================
Compliant Spec: Image pinned to SHA-256 digest, runAsNonRoot=true, allowPrivilegeEscalation=false, seccomp RuntimeDefault, drop ALL.
Command: kubectl patch pod {base_pod_name} --subresource=ephemeralcontainers --type=strategic -p '<compliant-ephemeral-container>'
Exit Code: {res_patch_pos.returncode} (Dynamic Admission Webhook Accepted & Patched)
Raw Output:
{res_patch_pos.stdout.strip()}

--> Admitted Pod Specification Verification:
spec.ephemeralContainers:
{eph_spec_res.stdout.strip()}

--> Containerd Runtime Execution Status (Distinguishing Admission from Runtime):
status.ephemeralContainerStatuses:
{eph_status_res.stdout.strip()}

--- Zero-Workload-Leakage Verification ---
Pods in forgeops-g09-kyverno:
{run_cmd(['kubectl', 'get', 'pods', '-n', 'forgeops-g09-kyverno']).stdout}
"""
    with open(os.path.join(EVIDENCE_DIR, "kyverno-ephemeral-container-rejection.txt"), "w", encoding="utf-8") as f:
        f.write(eph_content)
    print("  [PASS] kyverno-ephemeral-container-rejection.txt captured.")

    # Cleanup base pod
    run_cmd(["kubectl", "delete", "pod", base_pod_name, "-n", "forgeops-g09-kyverno", "--grace-period=0", "--force"])

    # Kyverno Positive Compliant Pod
    print("  Testing positive compliant fixture: pass-compliant-workload.yaml...")
    pass_fix = os.path.join(REPO_ROOT, "tests", "fixtures", "security", "admission", "kyverno", "pass-compliant-workload.yaml")
    res = run_cmd(["kubectl", "create", "-f", pass_fix], check=True)
    time.sleep(6)

    pod_desc = run_cmd(["kubectl", "describe", "pod", "test-kyverno-pass-compliant", "-n", "forgeops-g09-kyverno"]).stdout
    pod_logs = run_cmd(["kubectl", "logs", "test-kyverno-pass-compliant", "-n", "forgeops-g09-kyverno"]).stdout
    pod_get = run_cmd(["kubectl", "get", "pod", "test-kyverno-pass-compliant", "-n", "forgeops-g09-kyverno", "-o", "wide"]).stdout

    kyv_pass_content = f"""# ForgeOps Gate G09.4 Live Admission Evidence: Kyverno Compliant Pod Acceptance
Fixture: tests/fixtures/security/admission/kyverno/pass-compliant-workload.yaml
Namespace: forgeops-g09-kyverno
Date: {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}
Exit Code: 0 (Admission Webhook Accepted & Executed)

--- Command Executed ---
kubectl create -f tests/fixtures/security/admission/kyverno/pass-compliant-workload.yaml

--- Pod Execution Status ---
{pod_get}

--- Pod Logs ---
{pod_logs}

--- Pod Describe Details ---
{pod_desc}
"""
    with open(os.path.join(EVIDENCE_DIR, "kyverno-compliant-acceptance.txt"), "w", encoding="utf-8") as f:
        f.write(kyv_pass_content)
    run_cmd(["kubectl", "delete", "pod", "test-kyverno-pass-compliant", "-n", "forgeops-g09-kyverno", "--grace-period=0", "--force"])
    print("  [PASS] kyverno-compliant-acceptance.txt captured.")

    # 4. Controller-Level (Deployment) Tests
    print("\n--> 4. Executing Controller-Level (Deployment) Admission Tests (namespace: forgeops-g09-kyverno)...")
    run_cmd(["kubectl", "delete", "deployments", "--all", "-n", "forgeops-g09-kyverno", "--grace-period=0", "--force"])

    # 4a. Negative Deployment
    neg_deploy = os.path.join(REPO_ROOT, "tests", "fixtures", "security", "admission", "kyverno", "fail-deployment-insecure.yaml")
    print(f"  Testing negative Deployment fixture: fail-deployment-insecure.yaml...")
    res = run_cmd(["kubectl", "create", "-f", neg_deploy])
    assert res.returncode != 0, "Expected negative deployment to be rejected by admission webhook!"
    err_out = res.stderr or res.stdout
    assert "denied the request" in err_out, f"Unexpected rejection response: {err_out}"

    neg_deploy_content = f"""# ForgeOps Gate G09.4 Live Admission Evidence: Controller-Level (Deployment) Admission Rejection
Fixture: tests/fixtures/security/admission/kyverno/fail-deployment-insecure.yaml
Description: Deliberately insecure Deployment with mutable image tag and missing security context
Namespace: forgeops-g09-kyverno
Date: {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}
Exit Code: {res.returncode} (Admission Webhook Denied)

--- Command Executed ---
kubectl create -f tests/fixtures/security/admission/kyverno/fail-deployment-insecure.yaml

--- Raw Webhook Response ---
{err_out}

--- Zero-Workload-Leakage Verification ---
Deployments in forgeops-g09-kyverno:
{run_cmd(['kubectl', 'get', 'deployments', '-n', 'forgeops-g09-kyverno']).stdout}
Pods in forgeops-g09-kyverno:
{run_cmd(['kubectl', 'get', 'pods', '-n', 'forgeops-g09-kyverno']).stdout}
"""
    with open(os.path.join(EVIDENCE_DIR, "kyverno-deployment-rejection.txt"), "w", encoding="utf-8") as f:
        f.write(neg_deploy_content)
    print("  [PASS] kyverno-deployment-rejection.txt captured.")

    # 4b. Positive Deployment
    pos_deploy = os.path.join(REPO_ROOT, "tests", "fixtures", "security", "admission", "kyverno", "pass-deployment-compliant.yaml")
    print(f"  Testing positive Deployment fixture: pass-deployment-compliant.yaml...")
    res = run_cmd(["kubectl", "create", "-f", pos_deploy], check=True)

    # Wait for rollout
    rollout_res = run_cmd(["kubectl", "rollout", "status", "deployment/test-kyverno-pass-deployment", "-n", "forgeops-g09-kyverno", "--timeout=60s"], check=True)
    time.sleep(2)

    dep_get = run_cmd(["kubectl", "get", "deployment", "test-kyverno-pass-deployment", "-n", "forgeops-g09-kyverno", "-o", "wide"]).stdout
    pod_get = run_cmd(["kubectl", "get", "pods", "-n", "forgeops-g09-kyverno", "-l", "app=test-kyverno-pass-deployment", "-o", "wide"]).stdout
    dep_desc = run_cmd(["kubectl", "describe", "deployment", "test-kyverno-pass-deployment", "-n", "forgeops-g09-kyverno"]).stdout

    pos_deploy_content = f"""# ForgeOps Gate G09.4 Live Admission Evidence: Controller-Level (Deployment) Compliant Acceptance
Fixture: tests/fixtures/security/admission/kyverno/pass-deployment-compliant.yaml
Description: Compliant Deployment with immutable image digest and restricted security context
Namespace: forgeops-g09-kyverno
Date: {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())}
Exit Code: 0 (Admission Webhook Accepted & Rollout Succeeded)

--- Command Executed ---
kubectl create -f tests/fixtures/security/admission/kyverno/pass-deployment-compliant.yaml

--- Rollout Status ---
{rollout_res.stdout.strip()}

--- Deployment Status ---
{dep_get}

--- Running Pod Status (1/1 Ready) ---
{pod_get}

--- Deployment Describe ---
{dep_desc}
"""
    with open(os.path.join(EVIDENCE_DIR, "kyverno-deployment-acceptance.txt"), "w", encoding="utf-8") as f:
        f.write(pos_deploy_content)
    run_cmd(["kubectl", "delete", "deployment", "test-kyverno-pass-deployment", "-n", "forgeops-g09-kyverno", "--grace-period=0", "--force"])
    print("  [PASS] kyverno-deployment-acceptance.txt captured.")

    print("\n===================================================================")
    print(" [PASS] All Gate G09.4 Live Admission Evidence Successfully Regenerated!")
    print("===================================================================")


if __name__ == "__main__":
    main()
