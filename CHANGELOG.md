# Changelog

## Unreleased

- Read SSH global configuration through `sshd -T`, including Includes and
  effective defaults, and state the separate Match/live-daemon boundary.
- Keep failed network, process, cron, user/group and filesystem queries visible
  in report severity; distinguish empty results from unavailable observations.
- Include UDP and socket-activated listeners, fix comment-only key counts and
  distinguish locked password fields from genuinely empty ones.
- Print collected text literally and describe a no-finding result within its
  completed-check scope.
- Add isolated source regressions and signed-image, real systemd/OpenSSH VM CI
  with seeded failures, recovery and read-only snapshots.
