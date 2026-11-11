# Quick Start Guide

## Installation

```bash
# Clone the repository
git clone https://github.com/bglglzd/vps-sanity-check.git
cd vps-sanity-check

# Make the script executable
chmod +x sanity-check.sh
```

## Usage

```bash
# Run the sanity check (requires root)
sudo ./sanity-check.sh
```

## What You'll See

The script will check:

1. **System Information** - OS, kernel, uptime
2. **Users** - Suspicious accounts, UID 0 users, users without passwords
3. **Sudo** - Users with sudo access
4. **SSH** - Global configuration defaults, expanded Includes and key counts;
   per-connection Match rules and the live daemon require separate review
5. **Network** - TCP/UDP listeners and processes
6. **Processes** - Running processes, suspicious activity
7. **Cron** - Scheduled tasks and autostart
8. **Services** - Enabled system services
9. **Package Integrity** - System package verification
10. **Filesystem** - World-writable files, disk usage

## Understanding the Results

- **[✔] Green** - A selected check completed without a finding
- **[!] Yellow** - Warning, should be reviewed
- **[✘] Red** - Critical issue found
- **[*] Blue** - Informational message

## Final Status

At the end, you'll see one of three statuses:

- **NO FINDINGS IN COMPLETED CHECKS** - No findings in the selected completed checks
- **REVIEW RECOMMENDED** - Warnings or unavailable checks require review
- **ATTENTION REQUIRED** - A critical finding was detected

The report cannot establish that a host is uncompromised. SSH output describes
global file defaults from `sshd -T`, not all `Match` contexts or the live daemon.
See [README](README.md#ssh-configuration) for a per-connection query and
[VALIDATION](VALIDATION.md) for the tested scope.

## Optional: Install debsums

For package integrity checks, install debsums:

```bash
sudo apt-get update
sudo apt-get install debsums
```

## Troubleshooting

### "Permission denied"
Make sure you're running with `sudo`:
```bash
sudo ./sanity-check.sh
```

### "Command not found: ss"
Install iproute2:
```bash
sudo apt-get install iproute2
```

### "debsums not installed"
This is optional. Install with:
```bash
sudo apt-get install debsums
```

## Notes

- The script checks what can be checked from inside the VPS
- VPS providers always have hypervisor-level access (this is normal)
- This is a sanity check, not a complete security audit
- Always keep your system updated and follow security best practices

