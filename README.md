# VPS Sanity Check

🔐 **Minimalistic VPS security sanity checker**

## 🎯 Purpose

Quickly and clearly verify that your VPS:
- ✅ Is not compromised
- ✅ Has no obvious backdoors
- ✅ Is ready for production

**No ChatGPT. No "by eye".**  
**One run → clear report.**

## 🧠 Philosophy

❌ **Does NOT** promise 100% protection from the host (honest)  
✅ **Checks EVERYTHING** that can realistically be checked from inside the VPS  
✅ **Shows** users, sudo, SSH, network, processes, autostart, cron, package integrity  
✅ **Beautiful output** (colors, icons, sections)  
✅ **Works on** Ubuntu 20.04–24.04

## 🧩 Tech Stack

- **bash** (maximum compatibility)
- **awk / sed / grep**
- **Optional:** debsums, ss, systemctl
- **NO Python**, **NO dependencies** by default

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
- Root login status
- Password authentication
- Public key authentication
- Authorized keys
- SSH port

### Network
- Listening ports and processes
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
[✔] Root login: DISABLED
[✔] Password authentication: DISABLED
[✔] Public key authentication: ENABLED
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
[✔] STATUS: SYSTEM LOOKS CLEAN
    ✓ No critical issues detected

[*] NOTE: This tool checks what can be checked from inside the VPS.
[*] VPS host/provider may still have hypervisor-level access.
[*] This is normal and expected for VPS services.

    Report generated: Mon Jan 15 10:30:45 UTC 2024
```

## ⚠️ Disclaimer

This tool **cannot detect hypervisor-level access** by the VPS provider. It checks everything that can be checked from inside the VPS, but the host always has access at the virtualization level. This is normal and expected for VPS services.

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

