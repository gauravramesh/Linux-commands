# Fixing File Access Issues with Permissions and Ownership in Linux

## Scenario Overview

A project team is unable to update `/srv/team/report.txt` shortly before an important review. To unblock them quickly, a manager suggests running `chmod -R 777 /srv/team` to make the entire directory tree writable to everyone.

Instead of applying an insecure, recursive, world-writable shortcut, follow this structured approach to inspect ownership, verify user group/session state, apply the smallest scoped fix (via standard permissions or ACLs), and verify access for both intended and unintended users.

---

## Step 1: Inspect Path Permissions, Ownership & User/Group Context

Before modifying permissions, gather exact context on the directory path, target file, and the affected users' active group memberships.

### 1. Inspect Directory Traversal & File Permissions
```bash
ls -ld /srv /srv/team
ls -l /srv/team/report.txt
getfacl /srv/team /srv/team/report.txt
```
* **Observed State:**
  * `/srv/team` is owned by `root:analysts` with mode `750` (`drwxr-x---`).
  * `/srv/team/report.txt` is owned by `root:analysts` with mode `640` (`-rw-r-----`).
  * *(Note: If `ls -l` shows a `+` at the end of the mode string, e.g., `-rw-r-----+`, extended ACLs are already active.)*

### 2. Verify Affected Users' Group Membership & Session State
```bash
# Check configured group memberships for the affected analyst
id <analyst_username>
groups <analyst_username>
```
* **Why session state matters:** If a user was recently added to the `analysts` group (`usermod -aG analysts <user>`), their **existing login session** will not reflect the new group until they log out and log back in (or run `newgrp analysts`).

---

## Step 2: Understand Numeric vs. Symbolic Modes & Directory Semantics

Applying the minimum required permission requires understanding how permission bits behave differently on directories versus files—and avoiding unnecessary execute bits on plain text files.

### 1. Directory Search (`x`) vs. File Write (`w`)
* **Directory (`750` / `rwxr-x---`):**
  * `r` (`4`): Allows listing filenames inside `/srv/team`.
  * `x` (`1` — **search/traversal bit**): Mandatory for entering `/srv/team` and accessing file inodes inside it. Without `x` on every parent directory in the path, a user cannot read or write `report.txt` even if the file itself permits it.
  * `w` (`2`): Allows creating, renaming, or deleting files inside `/srv/team`. Since `/srv/team` is `750`, the `analysts` group has `r-x` (read and search) but **cannot** delete or rename files in the directory—which is ideal when they only need to edit an existing file.
* **Regular File (`640` / `-rw-r-----`):**
  * `r` (`4`) + `w` (`2`) = `6`: Allows reading and modifying file contents.
  * `x` (`1`): **Not needed** for a text document like `report.txt`. Using `770` (`-rwxrwx---`) unnecessarily marks a plain text file as executable; `660` (`-rw-rw----`) is the proper least-privilege mode.

### 2. Numeric vs. Symbolic Notation
* **Numeric (Absolute):** `chmod 660 /srv/team/report.txt` explicitly sets `rw-rw----` (overwriting existing bits).
* **Symbolic (Relative):** `chmod g+w /srv/team/report.txt` adds group write (`+w`) without altering existing owner or other bits—making it safer when you only want to add a single permission.

---

## Step 3: Apply a Scoped, Least-Privilege Correction

Because `/srv/team` and `report.txt` already belong to `root:analysts`, no `chown` or `chgrp` changes are required, and `chmod -R` must be avoided so unrelated files in `/srv/team` are not exposed.

### Option A: Standard Group Permissions (When the Entire `analysts` Group Needs Edit Access)
Grant write access strictly to the `analysts` group on the single target file:

```bash
# Symbolic approach (preferred for minimal delta)
sudo chmod g+w /srv/team/report.txt

# Equivalent numeric approach (rw-rw----)
sudo chmod 660 /srv/team/report.txt
```
* **Result:** `/srv/team` remains `750` (`drwxr-x---`) and `/srv/team/report.txt` becomes `660` (`-rw-rw----`). All `analysts` members can traverse `/srv/team` and edit `report.txt`, while non-members (`others`) have zero access (`---`).

### Option B: Targeted ACL (When Only One Specific Analyst Needs Edit Access)
If only a single user (e.g., `alice`) should edit `report.txt` without granting write access to the rest of the `analysts` group, use POSIX Access Control Lists (ACLs):

```bash
# 1. Ensure the user can traverse /srv/team (if they are not in the analysts group)
sudo setfacl -m u:alice:rx /srv/team

# 2. Grant read/write access on the specific file
sudo setfacl -m u:alice:rw /srv/team/report.txt
```

#### Inspecting the Effective ACL `mask`
Whenever named user or group ACL entries are added, Linux calculates an **ACL mask** (`mask::`), which acts as the **maximum upper bound** of effective permissions for all named users, the owning group, and named groups:

```bash
getfacl /srv/team/report.txt
```
* **What to look for in `getfacl` output:**
  ```text
  # file: srv/team/report.txt
  # owner: root
  # group: analysts
  user::rw-
  user:alice:rw-
  group::r--
  mask::rw-
  other::---
  ```
* **Mask Pitfall:** If `mask::r--` were set (for instance, after a subsequent `chmod g-w` command, which modifies the ACL mask rather than the base group entry), `user:alice:rw-` would display `#effective:r--` and write access would still fail until the mask is recalculated (`sudo setfacl -m m::rw /srv/team/report.txt`).

---

## Step 4: Verification Plan (Intended vs. Unintended Users)

Never assume a permission fix works without testing both positive (authorized) and negative (unauthorized) access paths.

### 1. Verify Metadata & Effective Permissions
```bash
ls -ld /srv/team
ls -l /srv/team/report.txt
getfacl /srv/team/report.txt
```

### 2. Test as an Intended Editor (Should Succeed)
```bash
# Confirm active session groups
sudo -u <intended_analyst> id

# Test reading and appending/writing to the file
sudo -u <intended_analyst> head -n 5 /srv/team/report.txt
sudo -u <intended_analyst> test -w /srv/team/report.txt && echo "WRITE_OK" || echo "WRITE_DENIED"
```

### 3. Test as an Unintended User (Should Fail)
```bash
# Test with a user outside the analysts group / ACL
sudo -u <unintended_user> ls -ld /srv/team
sudo -u <unintended_user> cat /srv/team/report.txt
sudo -u <unintended_user> test -w /srv/team/report.txt && echo "WRITE_OK" || echo "WRITE_DENIED"
```
* **Expected Outcome:**
  * `<intended_analyst>` prints `WRITE_OK` and can save edits to `/srv/team/report.txt`.
  * `<unintended_user>` receives `Permission denied` and `WRITE_DENIED`, confirming confidentiality and integrity are preserved.