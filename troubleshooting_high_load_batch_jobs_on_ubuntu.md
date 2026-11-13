# Troubleshooting High-Load Batch Jobs on Ubuntu

## Scenario Overview
An Ubuntu server experiences severe system-wide slowdowns during active hours. Running `top` reveals a batch job consuming ~89% CPU at the top of the process list. 

To resolve this safely without causing data corruption, orphaned locks, or missed schedules, follow this structured operational workflow—moving from **diagnosis** to **non-destructive throttling**, **graceful termination**, **timezone-aware rescheduling**, and **post-run verification**.

---

## Phase 1: Diagnose & Correlate Evidence
Before altering or stopping any process, confirm what is causing the bottleneck (CPU vs. disk I/O), identify child processes, and verify how the job is managed.

### 1. Check System Load, I/O Wait & Process Tree
```bash
uptime
vmstat 1 5
ps -ef --forest | grep -i <batch_job_name>
```
* **What to look for:** 
  * In `vmstat`, compare `wa` (I/O wait) against `us`/`sy` (CPU user/system) to determine if disk saturation is freezing the system.
  * In `ps --forest`, check whether the main PID has spawned child worker processes.

### 2. Map the PID to Its Owning Service or Cgroup
```bash
systemctl status <PID>
cat /proc/<PID>/cgroup
```
* **Why this matters:** If the batch job is managed by a `systemd` unit with `Restart=always`, killing the PID directly will cause `systemd` to immediately respawn it.

### 3. Correlate Start Time & Logs with the Slowdown Window
```bash
ps -p <PID> -o pid,ppid,lstart,etime,%cpu,%mem,cmd
journalctl -u <service_name> --since "1 hour ago"
```
* **What to look for:** Confirm that the process start time (`lstart`) aligns with the onset of system latency.

---

## Phase 2: Choose the Right Mitigation Scenario

### Scenario A: The Job Can Continue Running at Lower Priority (Non-Destructive)
If the job does not need to be stopped immediately, lower its CPU and disk priority so interactive sessions and critical services take precedence.

```bash
# Lower CPU priority (range: -20 highest to 19 lowest)
sudo renice -n 19 -p <PID>

# Lower disk I/O priority (class 3 = Idle; uses disk only when no other process needs it)
sudo ionice -c 3 -p <PID>
```
* **Verify impact:** Run `top -p <PID>` or `ps -o pid,ni,cmd -p <PID>` to confirm `NI` is `19` and system responsiveness recovers.
* *(Note: Shell job control commands like `Ctrl+Z`, `bg`, and `fg` only manage interactive jobs started inside your current terminal session—do not use them for background daemons or detached batch PIDs.)*

---

### Scenario B: The Job Must Be Stopped Immediately (Escalation Path)
If throttling does not relieve the slowdown, stop the process using a safe escalation sequence—never jump straight to `kill -9`.

#### Step 1: Stop via Service Manager (If managed by systemd)
```bash
sudo systemctl stop <service_name>
```

#### Step 2: Send Graceful `SIGTERM` (`kill -15`)
```bash
kill -15 <PID>
```
* **Why:** `SIGTERM` notifies the application to shut down cleanly—allowing it to flush buffers, close file descriptors, release locks, and save checkpoint progress.

#### Step 3: Forceful `SIGKILL` (`kill -9`) — Last Resort Only
If the process hangs and ignores `SIGTERM` after a reasonable grace window:
```bash
kill -9 <PID>
```
* **Risks of `SIGKILL`:** Terminates the process at the kernel level with zero cleanup. This can cause partial/corrupted file writes, stale `.lock` files, orphaned temporary files, and inconsistent state in dependent services.
* **Post-kill check:** Verify the process is gone (`ps -p <PID>`) and inspect the job's working directory for leftover lock files before restarting.

---

## Phase 3: Reschedule for Off-Peak Hours

### Scenario C: One-Time Deferred Run Tonight (`at`)
Use `at` when you only need to run the interrupted job once overnight.

1. **Check the server timezone and `atd` service:**
   ```bash
   timedatectl
   sudo systemctl status atd
   ```
   * **Why:** Many servers run in `UTC` while teams operate in local time (e.g., `IST`). Always confirm the server clock before specifying a runtime.

2. **Schedule the job with explicit paths and log redirection:**
   ```bash
   echo "/usr/local/bin/batch-job.sh >> /var/log/batch-job.log 2>&1" | at 02:00
   ```
   * **Why:** `at` captures your current shell environment (`PATH`, working directory, environment variables) at submission time, and `>> ... 2>&1` captures both standard output and errors for troubleshooting.

### Scenario D: Permanent Schedule Change (`cron`)
If the batch job runs daily during peak hours and needs a permanent schedule change:
```bash
crontab -e
```
Update the schedule entry (e.g., moving it to `0 2 * * *`), ensuring explicit environment variables (`PATH`) and log redirection are defined inside the crontab or wrapper script.

---

## Phase 4: Verify Schedule, Execution & System Health

### 1. Immediate Verification (Right After Scheduling)
```bash
# Confirm the job is queued with the expected timestamp
atq

# Inspect the exact environment and command payload stored for the job
at -c <job_number> | tail -n 15
```

### 2. Post-Execution Verification (Next Morning)
```bash
# Check batch job logs for clean completion (exit code 0)
tail -n 50 /var/log/batch-job.log

# Check scheduler daemon logs
journalctl -u atd --since "yesterday"
```
* **Application health check:** Review monitoring metrics (API latency, error rates, CPU/I/O load) during the 02:00 execution window to confirm the overnight run completed without impacting other services.