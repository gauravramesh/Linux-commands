# Onboarding a New Employee and Configuring Secure Access in Linux

## Scenario Overview
A new DevOps engineer (`gaurav`) is joining the team and requires a dedicated Linux user account with **least-privilege** administrative access, enforced password aging policies, collaboration in shared directories, and standard operational monitoring/communication setup.

This guide outlines the complete step-by-step workflow—including exact configuration commands, security rationale, and verification checks—to ensure every setting is applied and audited properly.

---

## Step 1: Create the User Account, Group & Initial Credentials

1. **Create the user with a home directory and assign them to the `devops` group:**
   ```bash
   sudo useradd -m gaurav
   sudo groupadd devops
   sudo usermod -aG devops gaurav
   ```
   *(Note: Always use `-aG` with `usermod` to append the secondary group rather than overwriting existing group memberships.)*

2. **Set the initial account password:**
   ```bash
   sudo passwd gaurav
   ```

3. **Verify user creation and group assignment:**
   ```bash
   id gaurav
   groups gaurav
   ```
   * **Expected Output:** Confirms the UID, primary GID, and secondary membership in `devops`.

---

## Step 2: Enforce Password Aging & Expiration Policies (`chage`)

To maintain credential hygiene, configure mandatory password rotation and advance expiration warnings rather than leaving passwords set to never expire.

1. **Set maximum password age (90 days) and warning period (7 days):**
   ```bash
   sudo chage -M 90 gaurav
   sudo chage -W 7 gaurav
   ```
   * **`-M 90`:** Forces the user to change their password every 90 days.
   * **`-W 7`:** Alerts the user 7 days prior to expiration.
   * *(Optional)* Force a password reset on first login: `sudo chage -d 0 gaurav`.

2. **Verify the applied aging policy:**
   ```bash
   sudo chage -l gaurav
   ```
   * **Expected Output:** Displays `Maximum number of days between password change: 90` and `Number of days of warning before password expires: 7`.

---

## Step 3: Configure Least-Privilege `sudo` Access (`visudo`)

Avoid granting unrestricted `ALL=(ALL) ALL` root privileges. Instead, whitelist only the specific binaries or service commands required for the DevOps role.

1. **Open the sudoers configuration safely (syntax-checked upon save):**
   ```bash
   sudo visudo
   ```
   *(Best practice: Create a dedicated drop-in file via `sudo visudo -f /etc/sudoers.d/devops-gaurav` to keep rules modular.)*

2. **Add explicit, command-level rules:**
   ```text
   gaurav ALL=(ALL) NOPASSWD: /bin/systemctl restart apache2, /bin/systemctl status apache2
   ```
   * **Security Rationale:** Specify full binary paths and exact subcommands/arguments where possible so the user cannot escalate privileges via arbitrary flags or shell escapes.

3. **Verify the exact `sudo` privileges granted to the user:**
   ```bash
   sudo -l -U gaurav
   ```
   * **Expected Output:** Lists only the explicitly permitted `systemctl` commands under `User gaurav may run the following commands`.

---

## Step 4: Monitor Active Users & Send Terminal Communications

Administrators must be able to audit who is logged into a server before performing maintenance and notify active sessions directly.

### 1. Monitor Logged-In Users & Activity
```bash
# View logged-in users, terminals (TTY/PTS), login times, and source IPs
who

# View active users along with their current running processes and CPU load
w

# Quick list of active usernames
users

# Review recent login history and authentication logs
last -n 10
```

### 2. Send Terminal Messages (`wall` vs. `write`)
* **Broadcast to all logged-in terminals (e.g., maintenance alerts):**
  ```bash
  wall "Scheduled maintenance on Apache in 10 minutes. Please save your work."
  ```
* **Send a direct message to a specific user session:**
  ```bash
  write gaurav pts/1
  # Type message, then press Ctrl+D to end transmission
  ```
  *(Note: The target terminal's identifier, such as `pts/1`, is retrieved from the `who` or `w` output. Users can toggle incoming `write` messages using `mesg y` or `mesg n`.)*

---

## Step 5: Configure Special Permissions for Shared Directories & Executables

Understanding special permission bits (`setuid`, `setgid`, and `sticky bit`) is critical for securing shared team directories without breaking file ownership boundaries.

| Special Bit | Octal | Symbolic | Behavior on Files | Behavior on Directories |
| :--- | :--- | :--- | :--- | :--- |
| **SetUID** | `4000` | `u+s` | Runs the executable with the **file owner's** privileges (e.g., `passwd`). | Ignored on Linux. |
| **SetGID** | `2000` | `g+s` | Runs the executable with the **file group's** privileges. | **Group Inheritance:** New files/subdirectories automatically inherit the directory's group (`devops`). |
| **Sticky Bit** | `1000` | `+t` | Ignored on modern Linux. | **Deletion Protection:** Users can only delete or rename files **they own**, even with directory write access (e.g., `/tmp`). |

### Practical Setup for a Shared DevOps Project Directory
To create a collaborative folder where all `devops` members can create files that automatically belong to the `devops` group—while preventing team members from deleting each other's files:

```bash
# Create shared directory and assign group ownership
sudo mkdir -p /srv/devops-shared
sudo chown root:devops /srv/devops-shared

# Apply SetGID (2) + Sticky Bit (1) = 3, plus rwxrwx--- (770)
sudo chmod 3770 /srv/devops-shared
```

* **Verify permissions:**
  ```bash
  ls -ld /srv/devops-shared
  ```
  * **Expected Output:** `drwxrws--T 2 root devops ... /srv/devops-shared`
    * Lowercase `s` in the group execute slot confirms **SetGID** is active.
    * Uppercase `T` (or lowercase `t` if world-executable) in the others slot confirms the **Sticky Bit** is active.