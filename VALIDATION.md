# Validation

The runtime is a read-only Bash checker. Standard system utilities supply its
observations; it does not install packages, change SSH, create users, start
services or modify the inspected files. Failed/unavailable observations are
warnings, not successful empty results.

## Isolated regression checks

```sh
for file in sanity-check.sh lib/*.sh tests/*.sh; do bash -n "$file"; done
shellcheck -x sanity-check.sh lib/*.sh tests/*.sh
bash tests/check-command-failures.sh
bash tests/check-effective-queries.sh
```

The tests use actual library code copied to a private temporary directory with
only host paths remapped. Command and configuration fixtures are synthetic.
They never run the audit entrypoint against the developer's machine. They cover
failed/empty queries, actual report counters, SSH effective-output precedence,
UDP/loopback/socket activation, comment-only key files, locked versus genuinely
empty passwords, and unchanged package/service regression cases.

## Booted VM acceptance

`tests/native-vm.sh` deliberately refuses normal developer/production hosts. CI
runs it only on a fresh GitHub-hosted Ubuntu 24.04 runner with KVM. Dev tooling
there includes QEMU, cloud-image-utils, OpenSSH client, GnuPG, curl and Python 3;
these are not dependencies of the installed checker.

The harness verifies the official Ubuntu Minimal 24.04 `release-20261105` image
against a signed checksum list and the pinned Ubuntu cloud-image signing key.
It uses a private disposable QCOW2 overlay, one vCPU, 1 GiB RAM, user-mode NAT
and a loopback-only SSH forward. There are no host mounts. Its generated private
SSH key, cloud seed and overlay stay outside uploaded evidence and are removed
with the owned QEMU process on exit.

Inside that VM, cloud-init installs ordinary system tools and marks the guest
as task-owned. The separate guarded `native-guest.sh` performs the installation
step from README, tests nonroot refusal, then executes the actual root CLI:

- all eleven report sections with real systemd, OpenSSH and debsums;
- an expected failing historical baseline at
  `ce22ace36e7f34bb5e4fc0cf2b8c2821266b1293`, followed by the current report on a
  real Include-based weak SSH setting and duplicate first-value directives;
- recovery of SSH settings and a separate demonstration of global versus
  connection-specific Match policy;
- comment-only and actual synthetic key-with-options inventories;
- a real bound UDP socket and a failed disposable systemd oneshot, then recovery;
- a controlled change to a non-executable package documentation file and exact
  restoration, proving the real debsums failure/recovery path.

Before/after snapshots compare selected security-file contents, modes/owners,
account/group databases, service enablement and listeners around every current
CLI audit. Provisioning and deliberate fixture changes are separate from the
checker's read-only operation. The final manifest binds source SHA/tree, baseline,
image hash/signature, workload, package versions, numeric counters and log hashes.
Only synthetic task evidence is uploaded. A failed assertion prevents acceptance.

Ubuntu 20.04/22.04 and other distributions are not covered by this VM job.
This acceptance is not a full security audit or hypervisor-compromise detector.

Primary references:

- [OpenSSH extended test mode and connection context](https://man.openbsd.org/sshd)
- [OpenSSH Include/Match and first-obtained-value rules](https://man.openbsd.org/sshd_config)
- [Ubuntu signed checksum verification](https://ubuntu.com/docs/public-images/public-images-how-to/verify-image-checksum/)
- [Pinned Ubuntu Minimal image](https://cloud-images.ubuntu.com/minimal/releases/noble/release-20261105/)
