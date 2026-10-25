# ForgeOps Guest VM Bootstrap & Recovery Runbook

- **Document Version:** 1.2
- **Effective Gate:** G04 Phase 1
- **Managed Target:** `forgeops-node-01` (Ubuntu Server 24.04.5 LTS on VirtualBox 7.2.8)
- **Control Node:** WSL2 Ubuntu 24.04 LTS (`ansible-core 2.17.7`)
- **Guest Status:** Verified Provisioned & Baseline Snapshot Confirmed

---

## 1. Prerequisites & Controller Baseline

### 1.1 Dedicated Lab SSH Key Pair on WSL2 Controller
The dedicated keypair resides in WSL user storage outside the repository:
```bash
# Generated ed25519 keypair for the lab
~/.ssh/forgeops_lab_ed25519      # Private key (mode 0600, untracked, never committed)
~/.ssh/forgeops_lab_ed25519.pub  # Public key (mode 0644, used by users role)
```

### 1.2 Enforced SSH Host-Key Verification
All connections strictly enforce host-key checking against the controller's trusted `~/.ssh/known_hosts` (`host_key_checking = True` in `ansible.cfg`). Host-key bypasses (`StrictHostKeyChecking=no` or `UserKnownHostsFile=/dev/null`) are prohibited.
```bash
# Ensure host key is recorded in ~/.ssh/known_hosts for port 2222
ssh-keyscan -p 2222 192.168.96.1 >> ~/.ssh/known_hosts
```

---

## 2. VirtualBox VM Topology & Sizing (Verified)

### VM Configuration Summary
- **VM Name:** `forgeops-ansible-lab` in `C:\Users\User\VirtualBox VMs\forgeops-ansible-lab`
- **vCPUs:** 2 vCPUs
- **Base Memory:** 2048 MB (2.0 GiB)
- **Hard Disk:** 25.00 GB dynamically allocated VDI
- **Network Adapter 1:** NAT
- **Preserved VirtualBox SSH Forwarding Rule:**
  - Rule specification: `guestssh,tcp,192.168.96.1,2222,,22`
  - Name: `guestssh`
  - Protocol: `TCP`
  - Host IP: `192.168.96.1` (Windows WSL gateway)
  - Host Port: `2222`
  - Guest IP: *(blank / dynamic DHCP)*
  - Guest Port: `22`

---

## 3. Ubuntu Server OS Installation Profile (Completed)

1. **Base OS:** Ubuntu Server 24.04.5 LTS (Noble Numbat).
2. **Profile:**
   - Server Name: `forgeops-node-01`
   - Primary User: `ops` (installer assigns UID 1000, preserved by Ansible)
   - Password: Set temporary password for bootstrap and console recovery.
3. **SSH Setup:**
   - **OpenSSH server installed**.
   - Password authentication temporarily enabled during initial bootstrap.
4. **Snaps:** None installed.

---

## 4. Post-Boot SSH Key Verification & Inventory Setup

### 4.1 Host Reachability & Key Installation
```bash
# 1. Discover Windows gateway address (192.168.96.1)
WINDOWS_HOST=$(ip route | awk '/default/ {print $3}')
TARGET_HOST="192.168.96.1"

# 2. Test port 2222 reachability
nc -zv -w 2 "$TARGET_HOST" 2222 || nc -zv -w 2 "$WINDOWS_HOST" 2222

# 3. Securely copy dedicated public key to guest using temporary password
ssh-copy-id -i ~/.ssh/forgeops_lab_ed25519.pub -p 2222 ops@"$TARGET_HOST"
```

### 4.2 Verify Key-Based Authentication
Verify that key-based login succeeds without password prompts:
```bash
ssh -i ~/.ssh/forgeops_lab_ed25519 -p 2222 -o PasswordAuthentication=no ops@"$TARGET_HOST" "sudo whoami"
# Expected output: root
```

### 4.3 Configure Untracked Local Inventory Override
Configure [infrastructure/ansible/inventories/lab/hosts.local.yml](file:///c:/Project/ForgeOps/infrastructure/ansible/inventories/lab/hosts.local.yml) (ignored by git):
```yaml
all:
  children:
    managed_lab:
      children:
        webservers:
          hosts:
            forgeops-node-01:
              ansible_host: 192.168.96.1  # Windows WSL gateway address
              ansible_port: 2222
              ansible_user: ops
              ansible_ssh_private_key_file: ~/.ssh/forgeops_lab_ed25519
```
*Notice:* No `ansible_ssh_common_args` bypass options are configured. Host identity is strictly validated against `~/.ssh/known_hosts`.

---

## 5. Confirmed Baseline Snapshot

The clean baseline snapshot has been verified in VirtualBox:
```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" snapshot "forgeops-ansible-lab" take "clean-installed-baseline" --description "Ubuntu Server 24.04.5 LTS freshly installed with ops user and verified SSH key"
```

---

## 6. Execution of Ansible Playbooks (Gate G04 Verification)

From repository root in WSL2:

### 6.1 Syntax Check
```bash
make ansible-check
```

### 6.2 Ansible Ping Test (A-401 Step 1 - Verified)
```bash
# Verify connectivity and host-key validation (without privilege escalation)
ansible -i infrastructure/ansible/inventories/lab/hosts.local.yml managed_lab -m ping -e ansible_become=false
# Returns SUCCESS: {"ping": "pong"}
```

### 6.3 Dry Run (Check Mode)
```bash
# Use --ask-become-pass (-K) for initial privilege escalation with temporary password
ansible-playbook -i infrastructure/ansible/inventories/lab/hosts.local.yml \
  infrastructure/ansible/playbooks/site.yml --check --diff --ask-become-pass
```

### 6.4 First Apply (Convergence)
```bash
# Use --ask-become-pass (-K) during initial apply.
# Sudo policy is ops_sudo_nopasswd=false (password-required); --ask-become-pass is always required.
ansible-playbook -i infrastructure/ansible/inventories/lab/hosts.local.yml \
  infrastructure/ansible/playbooks/site.yml --ask-become-pass
```

### 6.5 Second Apply (Idempotence Gate A-402)
```bash
# Sudo policy is password-required (ops_sudo_nopasswd=false); --ask-become-pass is required.
ansible-playbook -i infrastructure/ansible/inventories/lab/hosts.local.yml \
  infrastructure/ansible/playbooks/site.yml --ask-become-pass
# Must report changed=0, failed=0
```

### 6.6 Non-Mutating Audit
```bash
ansible-playbook -i infrastructure/ansible/inventories/lab/hosts.local.yml \
  infrastructure/ansible/playbooks/verify.yml
```

---

## 7. Anti-Lockout Rules & Emergency Recovery Procedures

### 7.1 Anti-Lockout Safeguards
1. **Pre-requisite Key Verification:** The `ssh-hardening` role includes an assertion that aborts execution if `authorized_keys` does not exist or is empty on the guest.
2. **Early Drop-in Precedence:** Hardening is deployed as `/etc/ssh/sshd_config.d/00-forgeops-hardening.conf` to take precedence before cloud-init (`50-cloud-init.conf`), and any legacy `99-forgeops-hardening.conf` is removed.
3. **Syntax Validation Before Activation:** Candidate configuration is tested with `/usr/sbin/sshd -t` before the drop-in is copied to active status.
4. **Effective Value Inspection:** The role runs `sshd -T` to verify effective values for `passwordauthentication no`, `permitrootlogin no`, and `pubkeyauthentication yes`.
5. **Firewall Ordering:** The `firewall` role explicitly allows SSH port 22 before applying restrictive incoming deny policies.

### 7.2 Out-of-Band Console Recovery
If SSH connectivity is ever lost:
1. Open the Oracle VM VirtualBox GUI console window on the Windows desktop.
2. Log in directly at the virtual TTY console as `ops` using the temporary password.
3. Inspect and correct issues:
   ```bash
   sudo ufw status verbose
   sudo systemctl status ssh
   sudo sshd -t
   sudo sshd -T
   ```
4. If necessary, restore the `clean-installed-baseline` snapshot:
   ```powershell
   & "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" controlvm "forgeops-ansible-lab" poweroff
   & "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" snapshot "forgeops-ansible-lab" restore "clean-installed-baseline"
   & "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" startvm "forgeops-ansible-lab"
   ```
