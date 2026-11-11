#!/usr/bin/env bash
# Mutating acceptance fixtures: ONLY inside the dedicated disposable cloud VM.
set -euo pipefail
if [[ $EUID -ne 0 || $(hostname) != vps-sanity-fixture ||
      ! -f /run/vps-sanity-fixture-owned ||
      $(cat /run/vps-sanity-fixture-owned) != disposable-ci-only ]]; then
  printf 'Refusing native fixtures outside the owned disposable VM.\n' >&2
  exit 2
fi
[[ $(cat /proc/1/comm) == systemd ]]
source_sha=${1:?source SHA required}
[[ $source_sha =~ ^[0-9a-f]{40}$ ]]
root=/opt/vps-sanity-fixture
out=/run/vps-sanity-fixture-evidence
mkdir -p "$out"
chmod +x "$root/current/sanity-check.sh"
export LC_ALL=C.UTF-8 TERM=dumb
# shellcheck source=/dev/null
source /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 24.04 ]]
systemctl is-active ssh.service > "$out/ssh-service.log"
dpkg-query -W bash openssh-server systemd debsums cron iproute2 procps > "$out/packages.log"
printf '%s\n' "$source_sha" > "$out/source-sha.txt"
checks=0
pass() { printf 'PASS %s\n' "$1" >> "$out/acceptance.log"; checks=$((checks + 1)); }
assert_absent() {
  local status=0
  grep -q -- "$1" "$2" || status=$?
  if [[ $status -ne 1 ]]; then
    printf 'Expected pattern absence could not be established: %s\n' "$2" >&2
    exit 1
  fi
}
readonly_snapshot() {
  local file
  for file in /etc/passwd /etc/group /etc/shadow /etc/gshadow /etc/sudoers \
      /etc/ssh/sshd_config /etc/ssh/sshd_config.d/00-00-vps-sanity-fixture.conf \
      /var/lib/dpkg/status /bin/bash /bin/sh /usr/bin/sudo /usr/bin/su \
      /usr/share/doc/debsums/copyright /home/key-fixture/.ssh/authorized_keys; do
    [[ -e $file || -L $file ]] || continue
    stat -Lc '%n %a %u %g %s' "$file"
    sha256sum "$file"
  done
  systemctl list-unit-files --type=service --no-legend --plain --no-pager | sort
  ss -H -tuln | sort
}
run_current() {
  readonly_snapshot > "$out/$1.before"
  "$root/current/sanity-check.sh" > "$out/$1.log" 2>&1
  readonly_snapshot > "$out/$1.after"
  cmp "$out/$1.before" "$out/$1.after"
}
strong_config() {
  cat > /etc/ssh/sshd_config <<'CONFIG'
Include /etc/ssh/sshd_config.d/*.conf
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
CONFIG
  printf 'PermitRootLogin no\nPasswordAuthentication no\nPubkeyAuthentication yes\n' > /etc/ssh/sshd_config.d/00-00-vps-sanity-fixture.conf
  /usr/sbin/sshd -t
}
effective() { /usr/sbin/sshd -T | grep -E '^(permitrootlogin|passwordauthentication|pubkeyauthentication|port) '; }
strong_config
effective > "$out/initial-effective.log"
if runuser -u fixture -- bash "$root/current/sanity-check.sh" > "$out/nonroot.log" 2>&1; then
  printf 'Nonroot execution unexpectedly succeeded.\n' >&2; exit 1
fi
grep -q 'must be run as root' "$out/nonroot.log"
assert_absent '── SYSTEM ' "$out/nonroot.log"
pass 'Nonroot entrypoint refuses before any audit section'
run_current initial
for heading in SYSTEM USERS SUDO SSH NETWORK PROCESSES 'CRON / AUTOSTART' SERVICES 'PACKAGE INTEGRITY' FILESYSTEM RESULT; do
  grep -Fq -- "── $heading " "$out/initial.log"
done
grep -q 'Global root login: DISABLED' "$out/initial.log"
grep -q 'Package integrity: OK (debsums)' "$out/initial.log"
assert_absent 'Cannot check\|Cannot determine\|Cannot complete\|Cannot enumerate' "$out/initial.log"
pass 'All eleven report sections on a real booted Ubuntu24.04/systemd/SSH guest'

printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/00-00-vps-sanity-fixture.conf
/usr/sbin/sshd -t
effective > "$out/weak-effective.log"
grep -q '^permitrootlogin yes$' "$out/weak-effective.log"
grep -q '^passwordauthentication yes$' "$out/weak-effective.log"
bash "$root/baseline/sanity-check.sh" > "$out/baseline-negative.log" 2>&1
grep -q 'Root login: DISABLED' "$out/baseline-negative.log"
grep -q 'Password authentication: DISABLED' "$out/baseline-negative.log"
pass 'Expected failing baseline: old grep reports disabled despite real weak Include settings'
run_current weak
grep -q 'Global root login: ENABLED' "$out/weak.log"
grep -q 'Global password authentication: ENABLED' "$out/weak.log"
grep -q 'OVERALL STATUS: ATTENTION REQUIRED' "$out/weak.log"
pass 'Current report follows real sshd -T Include precedence'

printf 'PermitRootLogin yes\nPermitRootLogin no\nPasswordAuthentication no\n' > /etc/ssh/sshd_config.d/00-00-vps-sanity-fixture.conf
effective > "$out/duplicate-effective.log"
run_current duplicate
grep -q '^permitrootlogin yes$' "$out/duplicate-effective.log"
grep -q 'Global root login: ENABLED' "$out/duplicate.log"
pass 'OpenSSH first-obtained value is preserved for duplicate directives'
strong_config
run_current ssh_recovered
grep -q 'Global root login: DISABLED' "$out/ssh_recovered.log"
grep -q 'Global password authentication: DISABLED' "$out/ssh_recovered.log"
assert_absent 'OVERALL STATUS: ATTENTION REQUIRED' "$out/ssh_recovered.log"
pass 'SSH configuration recovery clears the seeded critical finding'

mkdir -p /home/key-fixture/.ssh
useradd -M -d /home/key-fixture -s /usr/sbin/nologin key-fixture
printf '# Synthetic comment-only key inventory\n' > /home/key-fixture/.ssh/authorized_keys
run_current empty_keys
assert_absent 'syntax error\|invalid arithmetic' "$out/empty_keys.log"
pass 'Real comment-only authorized_keys produces a numeric zero without errors'
{ printf 'no-agent-forwarding,no-port-forwarding '; cat /home/fixture/.ssh/authorized_keys; } > /home/key-fixture/.ssh/authorized_keys
run_current key_options
grep -q 'key-fixture: 1 key(s)' "$out/key_options.log"
pass 'An actual synthetic SSH key with options is counted without exposing its content'
printf '# Synthetic comment-only key inventory\n' > /home/key-fixture/.ssh/authorized_keys

cat >> /etc/ssh/sshd_config <<'MATCH'
Match User root
    PasswordAuthentication yes
MATCH
/usr/sbin/sshd -T > "$out/match-global-full.log"
/usr/sbin/sshd -T -C user=root,host=example.invalid,addr=192.0.2.10 > "$out/match-context-full.log"
grep -q '^passwordauthentication no$' "$out/match-global-full.log"
grep -q '^passwordauthentication yes$' "$out/match-context-full.log"
run_current match_scope
grep -q 'Connection-specific Match rules and the running daemon are not evaluated' "$out/match_scope.log"
pass 'Global policy is explicitly distinguished from a real Match connection context'
strong_config

# Only synthetic data is served; this socket never sends traffic.
cat > /run/vps-sanity-udp-fixture.py <<'PY'
import socket,time
sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
sock.bind(('0.0.0.0',4444))
time.sleep(120)
PY
python3 /run/vps-sanity-udp-fixture.py &
udp_pid=$!
cleanup_udp() {
  if [[ -r /proc/$udp_pid/cmdline ]] && tr '\0' '\n' < "/proc/$udp_pid/cmdline" | grep -Fxq /run/vps-sanity-udp-fixture.py; then
    kill "$udp_pid" 2>/dev/null || true
  fi
  wait "$udp_pid" 2>/dev/null || true
}
trap cleanup_udp EXIT
for _ in {1..30}; do
  if ss -H -uln | grep -q ':4444 '; then break; fi
  sleep 0.2
done
run_current udp
grep -q '4444/UDP' "$out/udp.log"
grep -q 'Potentially suspicious ports detected' "$out/udp.log"
pass 'A real bound UDP UNCONN socket is visible and flagged'
cleanup_udp
trap - EXIT
run_current udp_recovered
assert_absent '4444/UDP' "$out/udp_recovered.log"
pass 'UDP fixture recovery removes the seeded listener'

cat > /etc/systemd/system/vps-sanity-fixture-failure.service <<'UNIT'
[Unit]
Description=Disposable VPS Sanity Check acceptance fixture
[Service]
Type=oneshot
ExecStart=/usr/bin/false
UNIT
systemctl daemon-reload
if systemctl start vps-sanity-fixture-failure.service > "$out/seed-service.log" 2>&1; then
  printf 'Expected synthetic service failure did not occur.\n' >&2; exit 1
fi
systemctl is-failed vps-sanity-fixture-failure.service > "$out/service-state.log"
run_current failed_service
grep -q 'Failed services detected' "$out/failed_service.log"
grep -q 'vps-sanity-fixture-failure.service' "$out/failed_service.log"
pass 'A real failed oneshot service is reported'
systemctl reset-failed vps-sanity-fixture-failure.service
rm -f -- /etc/systemd/system/vps-sanity-fixture-failure.service
systemctl daemon-reload
run_current final
assert_absent 'vps-sanity-fixture-failure.service\|4444/UDP\|Global root login: ENABLED' "$out/final.log"
pass 'Final report clears all owned seeded failures after recovery'

integrity_file=/usr/share/doc/debsums/copyright
cp -p "$integrity_file" /run/vps-sanity-copyright-backup
printf '\nSynthetic integrity test marker\n' >> "$integrity_file"
run_current changed_package
grep -q 'Package integrity issues detected (debsums)' "$out/changed_package.log"
pass 'Real debsums detects a controlled change to a non-executable package file'
cp -p /run/vps-sanity-copyright-backup "$integrity_file"
run_current integrity_recovered
grep -q 'Package integrity: OK (debsums)' "$out/integrity_recovered.log"
assert_absent 'OVERALL STATUS: ATTENTION REQUIRED' "$out/integrity_recovered.log"
pass 'Package fixture recovery restores integrity and the prior review status'

python3 - "$out" "$source_sha" "$checks" <<'PY'
import datetime,hashlib,json,pathlib,re,sys
out=pathlib.Path(sys.argv[1])
report={'status':'pass','source_sha':sys.argv[2],'checks_passed':int(sys.argv[3]),
 'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'environment':'Real Ubuntu24.04 minimal cloud VM, systemd PID1, OpenSSH server; synthetic identities/data',
 'artifacts':[{'path':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(out.iterdir()) if p.is_file()],
 'reports':[]}
for path in sorted(out.glob('*.log')):
    text=path.read_text()
    if 'OVERALL STATUS:' not in text or path.name=='baseline-negative.log': continue
    warnings=re.findall(r'Warnings: (\d+)',text)
    failures=re.findall(r'Critical issues detected: (\d+)',text)
    report['reports'].append({'path':path.name,'warnings':int(warnings[-1]) if warnings else 0,'failures':int(failures[-1]) if failures else 0,'readonly_snapshot_matches':(out/(path.stem+'.before')).read_bytes()==(out/(path.stem+'.after')).read_bytes()})
assert report['reports'] and all(row['readonly_snapshot_matches'] for row in report['reports'])
(out/'acceptance.json').write_text(json.dumps(report,indent=2)+'\n')
PY
cat "$out/acceptance.log"
