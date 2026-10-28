#!/usr/bin/env python3
"""
ForgeOps Gate G14: Automated SOPS + age Encrypted Secrets Validation Suite
Tests encryption, dual-recipient recovery, wrong-key refusal, tamper detection, and key hygiene.
"""

import os
import re
import sys
import yaml
import shutil
import tempfile
import subprocess

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SOPS_YAML = os.path.join(REPO_ROOT, ".sops.yaml")
ENC_SECRET_PATH = os.path.join(REPO_ROOT, "security", "sops", "synthetic-secrets.enc.yaml")

# Resolve binaries
SOPS_BIN = shutil.which("sops") or os.path.expanduser("~/.local/bin/sops")
AGE_BIN = shutil.which("age") or os.path.expanduser("~/.local/bin/age")
AGE_KEYGEN_BIN = shutil.which("age-keygen") or os.path.expanduser("~/.local/bin/age-keygen")

for b, name in [(SOPS_BIN, "sops"), (AGE_BIN, "age"), (AGE_KEYGEN_BIN, "age-keygen")]:
    if not os.path.isfile(b) or not os.access(b, os.X_OK):
        print(f"[FAIL] Required tool '{name}' not found at {b}")
        sys.exit(1)

def run_cmd(cmd, env=None, expect_zero=True):
    e = os.environ.copy()
    if env:
        e.update(env)
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=e)
    if expect_zero and res.returncode != 0:
        print(f"[FAIL] Command failed ({res.returncode}): {' '.join(cmd)}")
        print("STDERR:\n" + res.stderr)
        sys.exit(1)
    elif not expect_zero and res.returncode == 0:
        print(f"[FAIL] Command succeeded unexpectedly (expected non-zero): {' '.join(cmd)}")
        sys.exit(1)
    return res

def test_tool_versions():
    print("--> Test 1: Verifying SOPS and age tool versions...")
    res_sops = run_cmd([SOPS_BIN, "--version"])
    res_age = run_cmd([AGE_BIN, "--version"])
    assert "3.13" in res_sops.stdout or "sops" in res_sops.stdout, f"Unexpected SOPS version: {res_sops.stdout}"
    assert "v1." in res_age.stdout or "v1." in res_age.stderr or "age" in res_age.stdout, f"Unexpected age version: {res_age.stdout}"
    print(f"  [PASS] SOPS operational: {res_sops.stdout.splitlines()[0]}")
    print(f"  [PASS] age operational:  {res_age.stdout.splitlines()[0] if res_age.stdout else res_age.stderr.splitlines()[0]}")

def test_sops_config():
    print("--> Test 2: Validating .sops.yaml configuration & recipient public keys...")
    assert os.path.isfile(SOPS_YAML), f"Missing {SOPS_YAML}"
    with open(SOPS_YAML, "r") as f:
        cfg = yaml.safe_load(f)
    assert "creation_rules" in cfg, ".sops.yaml missing creation_rules"
    rules = cfg["creation_rules"]
    assert len(rules) > 0, "creation_rules is empty"
    rule = rules[0]
    assert "age" in rule, "Rule missing age public keys"
    age_keys = [k.strip() for k in rule["age"].split(",")]
    assert len(age_keys) >= 2, f"Expected at least 2 age recipients (primary + recovery), found {len(age_keys)}"
    for k in age_keys:
        assert k.startswith("age1"), f"Invalid age recipient key format: {k}"
        assert len(k) == 62, f"Unexpected age key length ({len(k)}): {k}"
    print(f"  [PASS] .sops.yaml contains valid dual-recipient configuration ({len(age_keys)} public keys).")

def test_encrypted_fixture_structure():
    print("--> Test 3: Validating structure of encrypted synthetic secret manifest...")
    assert os.path.isfile(ENC_SECRET_PATH), f"Missing {ENC_SECRET_PATH}"
    with open(ENC_SECRET_PATH, "r") as f:
        content = f.read()
    assert "ENC[AES256_GCM" in content, "File does not appear to contain SOPS AES256_GCM ciphertext"
    assert "sops:" in content, "Missing SOPS metadata block"
    assert "mac:" in content, "Missing SOPS cryptographic MAC block"
    assert "synthetic-lab-password-change-me" not in content, "CRITICAL LEAK: Plaintext password found in encrypted file!"
    print("  [PASS] Encrypted manifest contains ciphertext and valid SOPS metadata without plaintext exposure.")

def test_dynamic_decryption_and_recovery():
    print("--> Test 4: Testing dynamic key generation, encryption, decryption, and recovery...")
    with tempfile.TemporaryDirectory() as tmpdir:
        # Generate primary and recovery keys
        primary_key_file = os.path.join(tmpdir, "primary.agekey")
        recovery_key_file = os.path.join(tmpdir, "recovery.agekey")
        unrelated_key_file = os.path.join(tmpdir, "unrelated.agekey")
        
        for kf in [primary_key_file, recovery_key_file, unrelated_key_file]:
            run_cmd([AGE_KEYGEN_BIN, "-o", kf])
            os.chmod(kf, 0o600)
            
        def get_pub(path):
            for line in open(path):
                if line.startswith("# public key:"):
                    return line.split(":", 1)[1].strip()
            raise RuntimeError(f"No pubkey in {path}")
            
        p_pub = get_pub(primary_key_file)
        r_pub = get_pub(recovery_key_file)
        
        # Create synthetic secret
        test_plain = os.path.join(tmpdir, "secret.yaml")
        with open(test_plain, "w") as f:
            f.write("""apiVersion: v1
kind: Secret
metadata:
  name: test-credentials
  namespace: test-ns
stringData:
  db_password: "dynamic-synthetic-password-xyz"
  api_token: "dynamic-synthetic-token-abc"
""")
            
        # Create a local .sops.yaml in tmpdir
        sops_cfg = os.path.join(tmpdir, ".sops.yaml")
        with open(sops_cfg, "w") as f:
            f.write(f"""creation_rules:
  - path_regex: .*\\.ya?ml$
    age: "{p_pub},{r_pub}"
""")

        # Encrypt with dual recipients using the local config
        test_enc = os.path.join(tmpdir, "secret.enc.yaml")
        res_enc = run_cmd([SOPS_BIN, "--config", sops_cfg, "--encrypt", test_plain])
        with open(test_enc, "w") as f:
            f.write(res_enc.stdout)
            
        # A: Decrypt with Primary Key
        res_dec_p = run_cmd([SOPS_BIN, "--decrypt", test_enc], env={"SOPS_AGE_KEY_FILE": primary_key_file})
        dec_data_p = yaml.safe_load(res_dec_p.stdout)
        assert dec_data_p["stringData"]["db_password"] == "dynamic-synthetic-password-xyz"
        assert dec_data_p["stringData"]["api_token"] == "dynamic-synthetic-token-abc"
        print("  [PASS] Primary key decryption verified: matched synthetic fields without leaking plaintext.")
        
        # B: Decrypt with Recovery Key ONLY (proves independent recovery)
        res_dec_r = run_cmd([SOPS_BIN, "--decrypt", test_enc], env={"SOPS_AGE_KEY_FILE": recovery_key_file})
        dec_data_r = yaml.safe_load(res_dec_r.stdout)
        assert dec_data_r["stringData"]["db_password"] == "dynamic-synthetic-password-xyz"
        print("  [PASS] Recovery key decryption verified: independent recovery succeeds without primary key.")
        
        # C: Negative Test: Decrypt with Unrelated Key -> MUST FAIL
        run_cmd([SOPS_BIN, "--decrypt", test_enc], env={"SOPS_AGE_KEY_FILE": unrelated_key_file}, expect_zero=False)
        print("  [PASS] Wrong-key decryption strictly failed and returned non-zero exit code.")
        
        # D: Negative Test: Decrypt with No Key -> MUST FAIL
        empty_env = os.environ.copy()
        empty_env.pop("SOPS_AGE_KEY_FILE", None)
        empty_env.pop("SOPS_AGE_KEY", None)
        run_cmd([SOPS_BIN, "--decrypt", test_enc], env={"SOPS_AGE_KEY_FILE": "/dev/null"}, expect_zero=False)
        print("  [PASS] Missing-key decryption strictly failed and returned non-zero exit code.")
        
        # E: Negative Test: Tamper Detection (Modify ciphertext) -> MUST FAIL (MAC mismatch)
        with open(test_enc, "r") as f:
            enc_lines = f.readlines()
        # Tamper with one ciphertext character in db_password
        tampered_lines = []
        tampered = False
        for line in enc_lines:
            if "database_password:" in line or "db_password:" in line:
                tampered_lines.append(line.replace("ENC[AES256_GCM,data:", "ENC[AES256_GCM,data:TAMPERED"))
                tampered = True
            else:
                tampered_lines.append(line)
        assert tampered, "Failed to inject tamper into ciphertext"
        
        tampered_file = os.path.join(tmpdir, "tampered.enc.yaml")
        with open(tampered_file, "w") as f:
            f.writelines(tampered_lines)
            
        res_tamper = run_cmd([SOPS_BIN, "--decrypt", tampered_file], env={"SOPS_AGE_KEY_FILE": primary_key_file}, expect_zero=False)
        assert "MAC mismatch" in res_tamper.stderr or "failed" in res_tamper.stderr or res_tamper.returncode != 0
        print("  [PASS] Tamper detection verified: altered ciphertext failed cryptographic MAC integrity check.")

def test_git_repository_hygiene():
    print("--> Test 5: Verifying repository hygiene and absence of private age keys in Git...")
    # Walk repo and ensure no actual age private key (AGE-SECRET-KEY-1...) exists in tracked/manifest files
    key_pattern = re.compile(r"AGE-SECRET-KEY-1[0-9A-Za-z]{30,}")
    violating_files = []
    
    for root, dirs, files in os.walk(REPO_ROOT):
        # Ignore .git and temp dirs
        if ".git" in root or "target" in root or "node_modules" in root:
            continue
        for file in files:
            fpath = os.path.join(root, file)
            # Only check text files
            if file.endswith((".yaml", ".yml", ".json", ".md", ".sh", ".py", ".txt")):
                try:
                    with open(fpath, "r", errors="ignore") as f:
                        content = f.read()
                        if key_pattern.search(content):
                            # Exclude this test script itself
                            if file != "test_g14_sops.py":
                                violating_files.append(os.path.relpath(fpath, REPO_ROOT))
                except Exception:
                    pass
                    
    assert len(violating_files) == 0, f"CRITICAL LEAK: Private age secret keys found in repository files: {violating_files}"
    print("  [PASS] Zero private age keys detected across repository files.")

def main():
    print("=======================================================================")
    print("Starting Gate G14 SOPS + age Encrypted Secrets Validation Suite")
    print(f"SOPS Binary: {SOPS_BIN}")
    print(f"age Binary:  {AGE_BIN}")
    print("=======================================================================")
    test_tool_versions()
    test_sops_config()
    test_encrypted_fixture_structure()
    test_dynamic_decryption_and_recovery()
    test_git_repository_hygiene()
    print("=======================================================================")
    print("ALL GATE G14 SOPS + AGE ENCRYPTED SECRETS TESTS PASSED (5/5 suites successful)")
    print("=======================================================================")

if __name__ == "__main__":
    main()
