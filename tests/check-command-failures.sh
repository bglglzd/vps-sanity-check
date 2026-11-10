#!/usr/bin/env bash
# Synthetic command fixtures; this test never audits the host.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/checks.sh
source "$ROOT/lib/checks.sh"
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT
passed=0
failed=0

systemctl() {
  if [[ $1 == list-unit-files ]]; then
    [[ $scenario == unavailable ]] && return 1
    [[ $scenario == empty ]] && return 0
    printf 'fixture-a.service enabled enabled\nfixture-b.service enabled disabled\n'
  else
    [[ $scenario == unavailable || $scenario == failed_query ]] && return 1
    [[ $scenario == empty ]] && return 0
    printf 'fixture-a.service loaded failed failed Synthetic fixture\n'
  fi
}
getent() { printf 'sudo:x:27:%s\n' "$sudo_members"; }
debsums() {
  case "$integrity" in
    good) return 0 ;;
    changed) printf 'debsums: changed file /usr/bin/synthetic-fixture\n'; return 2 ;;
    unavailable) printf 'debsums: verification unavailable\n' >&2; return 1 ;;
  esac
}
is_package_owned() { return 0; }

check_case() {
  local name=$1 function=$2 expected=$3 forbidden=${4:-__never__}
  local expected_warnings=${5:-0} expected_failures=${6:-0} output
  STATUS_WARNINGS=0
  STATUS_FAILURES=0
  "$function" > "$fixture_dir/output" 2>&1
  output=$(cat "$fixture_dir/output")
  if [[ $output == *"$expected"* && $output != *"$forbidden"* &&
        $STATUS_WARNINGS -eq $expected_warnings && $STATUS_FAILURES -eq $expected_failures ]]; then
    printf 'PASS %s\n' "$name"
    passed=$((passed + 1))
  else
    printf 'FAIL %s\n' "$name"
    cat "$fixture_dir/output"
    printf 'Counters: warnings=%s failures=%s\n' "$STATUS_WARNINGS" "$STATUS_FAILURES"
    failed=$((failed + 1))
  fi
}

scenario=normal
check_case 'parse enabled service columns' check_services 'Enabled services: 2' __never__ 1
check_case 'parse failed service columns' check_services 'fixture-a.service' __never__ 1
scenario=unavailable
check_case 'failed service inventory never looks successful' check_services 'Cannot check services' 'Enabled services:' 1
scenario=failed_query
check_case 'failed status query is visible' check_services 'Cannot check failed services' __never__ 1
scenario=empty
check_case 'successful empty inventory has one zero' check_services 'Enabled services: 0' $'0\n0'
sudo_members=''
check_case 'empty sudo group has a valid numeric count' check_sudo 'No users in sudo group' 'syntax error'
integrity=good
check_case 'successful integrity scan' check_integrity 'Package integrity: OK'
integrity=changed
check_case 'reported integrity finding' check_integrity 'Package integrity issues detected' __never__ 0 1
integrity=unavailable
check_case 'integrity command failure never looks successful' check_integrity 'Cannot verify package integrity' 'Package integrity: OK' 1

section 'SYNTHETIC FIXTURE' > "$fixture_dir/heading"
if iconv -f UTF-8 -t UTF-8 "$fixture_dir/heading" > /dev/null 2>&1; then
  printf 'PASS section headings are valid UTF-8\n'
  passed=$((passed + 1))
else
  printf 'FAIL section headings are valid UTF-8\n'
  failed=$((failed + 1))
fi

printf '%s passed; %s failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
