# VPS Sanity Check

🔐 **Minimalistic VPS security sanity checker**

## 🎯 Purpose

Inspect selected security settings and visible warning signs on your VPS. A report can help you decide what to investigate; it cannot establish that the machine is uncompromised or ready for production.

**No ChatGPT. No "by eye".**  
**One run → clear report.**

## 🧠 Philosophy

❌ **Does NOT** promise 100% protection from the host (honest)  
✅ **Checks selected settings and warning signs** visible from inside the VPS<br>
✅ **Shows** users, sudo, SSH, network, processes, autostart, cron, package integrity  
✅ **Beautiful output** (colors, icons, sections)  
✅ **Targets** Ubuntu 20.04–24.04; automated VM acceptance covers 24.04

## 🧩 Tech Stack

- **bash** (maximum compatibility)
- **awk / sed / grep**
- **System tools:** getent, procps, find/df and standard GNU text utilities
- **Check-specific tools:** sshd, ss, crontab, systemctl and optional debsums
- **No Python runtime.** The checker installs no packages or services.

## 📦 Installation

```bash
git clone https://github.com/bglglzd/vps-sanity-check.git
cd vps-sanity-check
chmod +x sanity-check.sh
```

## 🚀 Usage

```bash
sudo ./sanity-check.sh
```

**Note:** The script requires root privileges to check system files and configurations.
Unavailable or failed queries produce a warning. A report with no findings is
limited to the selected completed checks; it cannot prove that a host is safe.

## 📋 What It Checks

### System Information
- OS version and kernel
- System uptime
- Hostname

### Users & Permissions
- Suspicious user accounts
- Users with UID 0 (root privileges)
- Users without passwords
- Sudo group members
- Custom sudoers entries

### SSH Configuration
- Global configured root/password/public-key authentication from `sshd -T`
- Included configuration files, defaults and first-obtained-value precedence
- Conventional `authorized_keys` inventory (counts only)
- Configured SSH ports

These are configuration-file defaults, separate from the live daemon and
connection-specific `Match` policies. The report states that boundary. For a
particular connection, replace the synthetic values below with the relevant
user, peer address and hostname and inspect that context separately:

```sh
sudo /usr/sbin/sshd -T -C user=your-user,addr=192.0.2.10,host=example.invalid
```

### Network
- TCP and UDP listeners, including UDP `UNCONN` and socket-activated listeners
- Suspicious port numbers
- Network listeners

### Processes
- Processes running as root
- Suspicious process names
- Processes with network listeners

### Cron & Autostart
- Root crontab
- System-wide cron jobs
- Suspicious cron entries (downloading from internet)

### Services
- Enabled system services
- Non-standard services
- Failed services

### Package Integrity
- Package integrity check (using debsums)
- Modified critical binaries
- Files not owned by packages

### Filesystem
- World-writable files in sensitive directories
- Disk usage

## 📊 Example Output

Illustrative format; actual findings depend on the inspected host. Reproducible
checks and native VM evidence are described in [VALIDATION.md](VALIDATION.md).

```
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║                    VPS SANITY CHECK                         ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

── SYSTEM ──────────────────────────────────────────────────────
[✔] OS detected: Ubuntu 24.04 LTS
[✔] Kernel: 6.8.0-90-generic
[✔] Uptime: 2h 14m
[*] Hostname: vps-server

── USERS ──────────────────────────────────────────────────────
[✔] No suspicious users found

── SUDO ───────────────────────────────────────────────────────
[✔] Sudo users (1):
    • deploy

── SSH ────────────────────────────────────────────────────────
[ℹ] SSH global defaults from configuration files (Includes expanded)
[ℹ] Connection-specific Match rules and the running daemon are not evaluated
[✔] Global root login: DISABLED
[✔] Global password authentication: DISABLED
[✔] Global public key authentication: ENABLED
[✔] Total authorized keys: 1
    • deploy: 1 key(s)

── NETWORK ────────────────────────────────────────────────────
[✔] Listening ports:
    • 22/tcp (sshd)
    • 80/tcp (nginx)
    • 443/tcp (nginx)

── PROCESSES ───────────────────────────────────────────────────
[*] Processes running as root: 45

── CRON / AUTOSTART ────────────────────────────────────────────
[✔] Root crontab: empty or only comments

── SERVICES ────────────────────────────────────────────────────
[✔] Enabled services: 23

── PACKAGE INTEGRITY ───────────────────────────────────────────
[*] Checking package integrity with debsums...
[✔] Package integrity: OK

── FILESYSTEM ──────────────────────────────────────────────────
[✔] Disk usage: 45%

── RESULT ──────────────────────────────────────────────────────
[✔] OVERALL STATUS: NO FINDINGS IN COMPLETED CHECKS
    No findings in the selected completed checks

[*] NOTE: This tool checks what can be checked from inside the VPS.
[*] VPS host/provider may still have hypervisor-level access.
[*] This is normal and expected for VPS services.

    Report generated: Mon Jan 15 10:30:45 UTC 2024
```

## ⚠️ Disclaimer

This tool **cannot detect hypervisor-level access** by the VPS provider. Its checks are limited to the settings and processes visible inside the VPS; a clean report is not proof that the machine is secure.

Command failures in the service and package-integrity checks are reported as warnings. A successful empty service list is shown as zero; an unavailable query is not treated as an empty list. The report uses its existing summary counters and retains the existing process exit-code behavior.

## Regression checks

```bash
bash tests/check-command-failures.sh
```

These tests use synthetic `systemctl`, `getent`, `debsums` and `dpkg` command fixtures and do not audit the host. They check real report functions, service-column parsing, empty groups, failed commands, warning/failure summary counters, parent-directory symlinks in package ownership and UTF-8 section headings (`iconv` from the Ubuntu base utilities is used by the test). A disposable Ubuntu 24.04 container was also exercised; a fully booted VPS and the other advertised Ubuntu versions have not been tested by this change.

## 🔧 Optional Dependencies

For full functionality, you may want to install:

```bash
# For package integrity checks
sudo apt-get install debsums

# ss and systemctl are usually pre-installed on Ubuntu
```

## 📝 License

See [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

**Remember:** This tool is a sanity check, not a complete security audit. Always follow security best practices and keep your system updated.

