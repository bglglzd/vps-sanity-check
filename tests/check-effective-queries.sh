#!/usr/bin/env bash
# Synthetic queries and private configuration copies; never audit the host.
set -uo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf -- "$fixture_dir"' EXIT
# shellcheck source=tests/fixture-lib.sh
source "$ROOT/tests/fixture-lib.sh"
prepare_fixture_library "$ROOT" "$fixture_dir"
# shellcheck source=/dev/null
source "$fixture_dir/library/checks.sh"
scenario=normal
passed=0 failed=0

getent() {
  case "$1" in
    passwd)
      [[ $scenario != users_error ]] || return 1
      printf 'root:x:0:0:Synthetic:%s/users/root:/bin/bash\n' "$FIXTURE_ROOT"
      printf 'synthetic:x:1000:1000:Synthetic:%s/users/synthetic:/bin/false\n' "$FIXTURE_ROOT" ;;
    shadow)
      [[ $scenario != shadow_error ]] || return 1
      printf 'root:*:1::::::\n'
      if [[ $scenario == empty_password ]]; then printf 'synthetic::1::::::\n'; else printf 'synthetic:!!:1::::::\n'; fi ;;
    group)
      [[ $scenario != sudo_error ]] || return 1
      printf 'sudo:x:27:\n' ;;
    *) return 1 ;;
  esac
}
sshd() {
  [[ $1 == -T && $2 == -f && $3 == "$FIXTURE_ROOT/etc/ssh/sshd_config" ]] || return 1
  [[ $scenario != ssh_error ]] || return 1
  if [[ $scenario == ssh_incomplete ]]; then printf 'permitrootlogin no\n'; return; fi
  if [[ $scenario == ssh_weak ]]; then
    printf 'permitrootlogin yes\npasswordauthentication yes\n'
  else
    printf 'permitrootlogin no\npasswordauthentication no\n'
  fi
  printf 'pubkeyauthentication yes\nport 22\n'
}
ss() {
  [[ $scenario != network_error ]] || return 1
  if [[ $scenario == udp ]]; then
    printf 'udp UNCONN 0 0 0.0.0.0:4444 0.0.0.0:* users:(("synthetic",pid=999999,fd=3))\n'
  elif [[ $scenario == loopback ]]; then
    printf 'tcp LISTEN 0 1 [::1]:4444 [::]:* users:(("synthetic",pid=999999,fd=3))\n'
  else
    printf 'tcp LISTEN 0 1 0.0.0.0:22 0.0.0.0:* users:(("systemd",pid=1,fd=3))\n'
  fi
}
find() { [[ $scenario != filesystem_error && $scenario != cron_find_error ]] || return 1; }
df() {
  [[ $scenario != filesystem_error ]] || return 1
  if [[ $scenario == malformed_df ]]; then printf 'synthetic malformed output\n'; return; fi
  printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\nsynthetic 100 10 90 10%% /\n'
}
ps() {
  [[ $scenario != process_error ]] || return 1
  printf 'USER PID %%CPU %%MEM VSZ RSS TTY STAT START TIME COMMAND\nroot 999999 0 0 1 1 ? S 00:00 0:00 synthetic-process\n'
}
crontab() {
  case $scenario in
    cron_error) printf 'Synthetic crontab I/O error\n' >&2; return 1 ;;
    cron_absent) printf 'no crontab for root\n' >&2; return 1 ;;
    *) printf '  # Synthetic comment-only crontab\n' ;;
  esac
}
grep() {
  if [[ $scenario == cron_scan_error && $1 == -rE ]]; then return 2; fi
  command grep "$@"
}
check_case() {
  local label=$1 function=$2 expected=$3 warnings=${4:-0} failures=${5:-0} forbidden=${6:-__never__}
  STATUS_WARNINGS=0 STATUS_FAILURES=0
  "$function" > "$fixture_dir/output" 2>&1
  local output actual_warnings=$STATUS_WARNINGS actual_failures=$STATUS_FAILURES
  output=$(cat "$fixture_dir/output")
  summary >> "$fixture_dir/output"
  if [[ $output == *"$expected"* && $output != *"$forbidden"* &&
        $actual_warnings -eq $warnings && $actual_failures -eq $failures ]] &&
     { [[ $warnings -eq 0 && $failures -eq 0 ]] || ! command grep -q 'NO FINDINGS IN COMPLETED CHECKS' "$fixture_dir/output"; }; then
    printf 'PASS %s\n' "$label"; passed=$((passed + 1))
  else
    printf 'FAIL %s warnings=%s failures=%s\n' "$label" "$actual_warnings" "$actual_failures"
    cat "$fixture_dir/output"; failed=$((failed + 1))
  fi
}

scenario=ssh_weak
check_case 'effective output wins over contradictory source text' check_ssh 'Global root login: ENABLED' 1 1 'Global root login: DISABLED'
scenario=ssh_error
check_case 'failed sshd query never falls back to grep' check_ssh 'Cannot check SSH global defaults' 1 0 'DISABLED'
scenario=ssh_incomplete
check_case 'incomplete effective output is visible' check_ssh 'incomplete sshd -T output' 3
scenario=normal
printf '# Synthetic comment with ssh-ed25519 text is not a key\n' > "$FIXTURE_ROOT/users/synthetic/.ssh/authorized_keys"
check_case 'comment-only authorized keys count as zero without arithmetic errors' check_ssh 'Authorized keys: 0 total' 0 0 'syntax error'
scenario=udp
check_case 'UDP UNCONN is included and flagged' check_network '4444/UDP' 1
scenario=loopback
check_case 'bracketed IPv6 loopback is excluded' check_network 'No external TCP/UDP listeners found'
scenario=normal
check_case 'socket-activated listeners remain visible' check_network '22/TCP (systemd)'
scenario=network_error
check_case 'failed ss query is incomplete' check_network 'Cannot check network listeners' 1
scenario=filesystem_error
check_case 'find and df failures cannot report a clean filesystem or zero usage' check_filesystem 'Cannot check disk usage' 6 0 'No world-writable files'
scenario=malformed_df
check_case 'malformed successful df output is visible' check_filesystem 'Cannot determine disk usage' 1
scenario=process_error
check_case 'failed process query is incomplete' check_processes 'Cannot check processes' 1
scenario=sudo_error
check_case 'failed sudo-group query is incomplete' check_sudo 'Cannot check sudo users' 1
scenario=cron_error
check_case 'crontab failure is not mistaken for no crontab' check_cron 'Cannot check root crontab' 1 0 'Root crontab: none'
scenario=cron_absent
check_case 'documented no-crontab status is accepted' check_cron 'Root crontab: none'
scenario=cron_find_error
check_case 'cron inventory read failures are visible' check_cron 'Cannot inventory cron files' 5
scenario=cron_scan_error
check_case 'cron pattern scan failure is visible' check_cron 'Cannot complete suspicious-cron scan' 1
scenario=users_error
check_case 'failed user inventory is incomplete' check_users 'Cannot enumerate users' 1
scenario=shadow_error
check_case 'failed shadow inventory is incomplete' check_users 'Cannot check account password status' 1
scenario=normal
check_case 'locked passwords are not classified as empty' check_users 'locked system passwords: 1' 0 0 'Regular users with empty password'
scenario=empty_password
check_case 'genuinely empty regular password is flagged' check_users 'Regular users with empty password fields' 1

printf '%s passed; %s failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
