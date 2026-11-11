#!/usr/bin/env bash

# VPS Sanity Check - Security Checks Module
# All security checks are implemented here

# shellcheck source=lib/colors.sh
source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
# shellcheck source=lib/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Check OS and system information
check_os() {
  section "SYSTEM"
  
  if [[ -f /etc/os-release ]]; then
    # /etc/os-release only exists on the target Linux system; it cannot be
    # resolved during static analysis, so tell ShellCheck not to follow it.
    # shellcheck source=/dev/null
    source /etc/os-release
    ok "OS detected: ${PRETTY_NAME:-$NAME}"
  else
    warn "Cannot detect OS (no /etc/os-release)"
    return
  fi
  
  local kernel
  kernel=$(uname -r)
  ok "Kernel: $kernel"
  
  local uptime
  uptime=$(get_uptime)
  ok "Uptime: $uptime"
  
  local hostname
  hostname=$(hostname 2>/dev/null || echo "unknown")
  info "Hostname: $hostname"
}

# Check users - uses UID and shell logic, not hardcoded lists
check_users() {
  section "USERS"
  local accounts shadow shadow_available=true
  if ! accounts=$(getent passwd 2>/dev/null) || [[ -z $accounts ]]; then
    warn "Cannot enumerate users (getent passwd unavailable, failed or empty)"
    return
  fi
  if ! shadow=$(getent shadow 2>/dev/null) || [[ -z $shadow ]]; then
    warn "Cannot check account password status (getent shadow failed or empty)"
    shadow_available=false
  fi
  local interactive=() uid0=() empty_passwords=() system_count=0 locked_system=0
  local username uid shell kind valid=true
  while IFS=: read -r username _ uid _ _ _ shell; do
    [[ -n $username ]] || continue
    if [[ ! $uid =~ ^[0-9]{1,10}$ || -z $shell ]]; then
      warn "Cannot parse an account record"
      valid=false
      continue
    fi
    uid=$((10#$uid))
    if [[ $uid -eq 0 && $username != root ]]; then uid0+=("$username"); fi
    if [[ $uid -lt 1000 ]]; then
      system_count=$((system_count + 1))
    else
      case $shell in */nologin|*/false) ;; *) interactive+=("$username (UID: $uid, Shell: $shell)") ;; esac
    fi
    [[ $shadow_available == true ]] || continue
    # Emit only a classification; password hashes are never printed.
    kind=$(printf '%s\n' "$shadow" | awk -F: -v user="$username" '
      $1==user {found=1; if ($2=="") print "empty"; else if ($2 ~ /^[!*]/) print "locked"; else print "set"; exit}
      END {if (!found) print "missing"}')
    case $kind in
      empty)
        if [[ $uid -eq 0 ]]; then
          fail "UID 0 account has an empty password field: $username"
        elif [[ $uid -ge 1000 ]]; then
          empty_passwords+=("$username")
        fi ;;
      locked) if [[ $uid -lt 1000 ]]; then locked_system=$((locked_system + 1)); fi ;;
      set) ;;
      *) warn "Cannot determine password status for $username" ;;
    esac
  done <<< "$accounts"
  if [[ ${#uid0[@]} -gt 0 ]]; then
    fail "Users with UID 0 (root privileges) other than root:"
    for username in "${uid0[@]}"; do print_list_item "$username"; done
  fi
  if [[ ${#interactive[@]} -gt 0 ]]; then
    warn "Interactive user accounts (UID >= 1000 with login shell):"
    for username in "${interactive[@]}"; do print_list_item "$username"; done
  elif [[ $valid == true ]]; then
    ok "No interactive regular user accounts found"
  fi
  if [[ ${#empty_passwords[@]} -gt 0 ]]; then
    warn "Regular users with empty password fields:"
    for username in "${empty_passwords[@]}"; do print_list_item "$username"; done
  fi
  info "System users (UID < 1000): $system_count; locked system passwords: $locked_system"
}

# Check sudo configuration
check_sudo() {
  section "SUDO"
  local group members count
  if ! group=$(getent group sudo 2>/dev/null) || [[ ! $group =~ ^sudo:[^:]*:[0-9]+:[^:]*$ ]]; then
    warn "Cannot check sudo users (getent group sudo failed or returned no group)"
    return
  fi
  members=$(printf '%s\n' "$group" | cut -d: -f4 | tr ',' '\n')
  count=$(printf '%s\n' "$members" | awk 'NF {count++} END {print count+0}')
  if [[ $count -eq 0 ]]; then
    info "No users in sudo group"
  else
    ok "Sudo users ($count):"
    while IFS= read -r user; do
      [[ -n $user ]] && print_list_item "$user"
    done <<< "$members"
  fi
  if [[ -f /etc/sudoers ]]; then
    local entries status=0
    entries=$(grep -vE '^[[:space:]]*(#|$|Defaults|%|@)' /etc/sudoers 2>/dev/null) || status=$?
    if [[ $status -gt 1 ]]; then
      warn "Cannot read custom sudoers entries"
    elif [[ -n $entries ]]; then
      info "Custom sudoers entries found (review recommended)"
    fi
  fi
}

# Check SSH configuration
check_ssh() {
  section "SSH"
  local config=${1:-/etc/ssh/sshd_config} effective
  if [[ ! -r $config ]]; then
    warn "Cannot read SSH configuration"
    return
  fi
  if ! check_command sshd || ! effective=$(sshd -T -f "$config" 2>/dev/null); then
    warn "Cannot check SSH global defaults (sshd -T unavailable or failed)"
    return
  fi
  info "SSH global defaults from configuration files (Includes expanded)"
  info "Connection-specific Match rules and the running daemon are not evaluated; review with sshd -T -C for the relevant connection."
  local root_login password_auth public_key port
  root_login=$(printf '%s\n' "$effective" | awk '$1 == "permitrootlogin" {n++; v=$2} END {if (n==1) print v}')
  password_auth=$(printf '%s\n' "$effective" | awk '$1 == "passwordauthentication" {n++; v=$2} END {if (n==1) print v}')
  public_key=$(printf '%s\n' "$effective" | awk '$1 == "pubkeyauthentication" {n++; v=$2} END {if (n==1) print v}')
  case $root_login in
    no) ok "Global root login: DISABLED" ;;
    yes) fail "Global root login: ENABLED (review required)" ;;
    prohibit-password|without-password|forced-commands-only) warn "Global root login: RESTRICTED ($root_login), not fully disabled" ;;
    *) warn "Cannot determine global root login (incomplete sshd -T output)" ;;
  esac
  case $password_auth in
    no) ok "Global password authentication: DISABLED" ;;
    yes) warn "Global password authentication: ENABLED (consider disabling)" ;;
    *) warn "Cannot determine global password authentication (incomplete sshd -T output)" ;;
  esac
  case $public_key in
    yes) ok "Global public key authentication: ENABLED" ;;
    no) warn "Global public key authentication: DISABLED" ;;
    *) warn "Cannot determine global public key authentication (incomplete sshd -T output)" ;;
  esac
  local accounts total_keys=0 count key_file username home
  if accounts=$(getent passwd 2>/dev/null) && [[ -n $accounts ]]; then
    while IFS=: read -r username _ _ _ _ home _; do
      [[ -n $username && -n $home ]] || continue
      key_file="$home/.ssh/authorized_keys"
      if [[ -f $key_file ]]; then
        # Count key lines without printing their content; zero matches is success.
        if ! count=$(awk '!/^[[:space:]]*(#|$)/ && /(^|[[:space:]])(ssh-|ecdsa-|sk-)[^[:space:]]+[[:space:]]/ {n++} END {print n+0}' "$key_file" 2>/dev/null); then
          warn "Cannot read an authorized_keys file for $username"
          continue
        fi
        total_keys=$((total_keys + count))
        [[ $count -eq 0 ]] || print_list_item "$username: $count key(s)"
      fi
    done <<< "$accounts"
    info "Authorized keys: $total_keys total (conventional authorized_keys files only)"
  else
    warn "Cannot enumerate users for authorized-key inventory"
  fi
  port=$(printf '%s\n' "$effective" | awk '$1 == "port" {print $2}')
  if [[ -z $port ]]; then
    warn "Cannot determine configured SSH ports (incomplete sshd -T output)"
  else
    info "Global configured SSH port(s): $(printf '%s\n' "$port" | paste -sd, -)"
  fi
}

# Check network listeners - fixed parsing
check_network() {
  section "NETWORK"
  local listeners
  if ! listeners=$(ss -H -tulpn 2>/dev/null); then
    warn "Cannot check network listeners (ss unavailable or failed)"
    return
  fi
  local displayed=0 protocol address port process line
  local suspicious=()
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    read -r protocol _ _ _ address _ <<< "$line"
    case $protocol in tcp|tcp6|udp|udp6) ;; *) continue ;; esac
    case $address in 127.*:*|\[::1\]:*|::1:*) continue ;; esac
    port=${address##*:}
    if [[ ! $port =~ ^[0-9]+$ ]]; then
      warn "Cannot parse a network listener port"
      continue
    fi
    process=$(printf '%s\n' "$line" | sed -n 's/.*users:(("\([^"]*\)".*/\1/p')
    [[ -n $process ]] || process=unknown
    if [[ $displayed -eq 0 ]]; then ok "External TCP/UDP listeners:"; fi
    displayed=$((displayed + 1))
    print_list_item "$port/${protocol^^} ($process)"
    case $port in 4444|5555|6666|12345|31337|54321) suspicious+=("$port/${protocol^^}") ;; esac
  done <<< "$listeners"
  if [[ $displayed -eq 0 ]]; then info "No external TCP/UDP listeners found"; fi
  if [[ ${#suspicious[@]} -gt 0 ]]; then
    warn "Potentially suspicious ports detected:"
    for port in "${suspicious[@]}"; do print_list_item "$port"; done
  fi
}

# Check cron jobs and autostart
check_cron() {
  section "CRON / AUTOSTART"
  local root_cron status=0 count line
  root_cron=$(LC_ALL=C crontab -l -u root 2>&1) || status=$?
  if [[ $status -eq 1 && $root_cron == "no crontab for root" ]]; then
    ok "Root crontab: none"
  elif [[ $status -ne 0 ]]; then
    warn "Cannot check root crontab (crontab unavailable or failed)"
  else
    count=$(printf '%s\n' "$root_cron" | awk '!/^[[:space:]]*(#|$)/ {n++} END {print n+0}')
    if [[ $count -eq 0 ]]; then
      ok "Root crontab: empty or only comments"
    else
      info "Root crontab entries: $count"
      while IFS= read -r line; do
        [[ $line =~ ^[[:space:]]*(#|$) ]] || print_list_item "$line"
      done <<< "$root_cron"
    fi
  fi
  local dirs=(/etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly)
  local total=0 directory files targets=()
  [[ ! -f /etc/crontab ]] || targets+=(/etc/crontab)
  for directory in "${dirs[@]}"; do
    [[ -d $directory ]] || continue
    targets+=("$directory")
    if ! files=$(find "$directory" -type f 2>/dev/null); then
      warn "Cannot inventory cron files in $directory (find failed)"
      continue
    fi
    count=$(printf '%s\n' "$files" | awk 'NF {n++} END {print n+0}')
    total=$((total + count))
  done
  info "System cron files: $total"
  if [[ ${#targets[@]} -gt 0 ]]; then
    local suspicious
    status=0
    suspicious=$(grep -rE '(wget|curl|bash|sh)[[:space:]]+.*https?://' "${targets[@]}" 2>/dev/null) || status=$?
    if [[ $status -gt 1 ]]; then warn "Cannot complete suspicious-cron scan (grep failed)"; fi
    if [[ -n $suspicious ]]; then
      warn "Potentially suspicious cron entries (downloading from internet):"
      while IFS= read -r line; do print_list_item "$line"; done <<< "$suspicious"
    fi
  fi
}

# Check system services
check_services() {
  section "SERVICES"
  
  if ! check_command "systemctl"; then
    warn "Cannot check services (systemctl not available)"
    return
  fi
  
  local enabled_services
  if ! enabled_services=$(systemctl list-unit-files --type=service --state=enabled --no-legend --plain --no-pager 2>/dev/null); then
    warn "Cannot check services (systemctl list-unit-files failed)"
    return
  fi
  enabled_services=$(printf '%s\n' "$enabled_services" | awk '$1 ~ /\.service$/ {print $1}')
  local service_count
  service_count=$(printf '%s\n' "$enabled_services" | awk 'NF {count++} END {print count+0}')
  
  ok "Enabled services: $service_count"
  
  # Check for failed services
  local failed_services
  if ! failed_services=$(systemctl list-units --type=service --state=failed --no-legend --plain --no-pager 2>/dev/null); then
    warn "Cannot check failed services (systemctl list-units failed)"
    return
  fi
  failed_services=$(printf '%s\n' "$failed_services" | awk '$1 ~ /\.service$/ {print $1}')
  if [[ -n "$failed_services" ]]; then
    warn "Failed services detected:"
    while IFS= read -r service; do
      [[ -n "$service" ]] && print_list_item "$service"
    done <<< "$failed_services"
  fi
}

# Check package integrity - handles symlinks correctly
check_integrity() {
  section "PACKAGE INTEGRITY"
  
  # Check with debsums if available
  if check_command "debsums"; then
    local debsums_output
    local debsums_status=0
    debsums_output=$(debsums -s 2>&1) || debsums_status=$?
    local debsums_errors
    debsums_errors=$(echo "$debsums_output" | grep -iE "FAILED|MISSING|changed|modified" || true)
    
    if [[ -n "$debsums_errors" ]]; then
      fail "Package integrity issues detected (debsums):"
      while IFS= read -r line; do
        [[ -n "$line" ]] && print_list_item "$line"
      done <<< "$debsums_errors"
    elif [[ $debsums_status -ne 0 ]]; then
      warn "Cannot verify package integrity (debsums exited with status $debsums_status)"
    else
      ok "Package integrity: OK (debsums)"
    fi
  else
    info "debsums not installed (optional: apt-get install debsums)"
  fi
  
  # Check critical binaries - handle symlinks properly
  local critical_bins=("/bin/bash" "/bin/sh" "/usr/bin/sudo" "/usr/bin/su")
  local unowned_bins=()
  
  for bin in "${critical_bins[@]}"; do
    if [[ -f "$bin" || -L "$bin" ]]; then
      if ! is_package_owned "$bin"; then
        unowned_bins+=("$bin")
      fi
    fi
  done
  
  if [[ ${#unowned_bins[@]} -gt 0 ]]; then
    warn "Critical binaries not owned by any package:"
    for bin in "${unowned_bins[@]}"; do
      local resolved
      resolved=$(resolve_symlink "$bin")
      if [[ "$resolved" != "$bin" ]]; then
        info "  $bin → $resolved (symlink, checking resolved path)"
      else
        print_list_item "$bin"
      fi
    done
  else
    ok "Critical binaries: all owned by packages"
  fi
}

# Check processes
check_processes() {
  section "PROCESSES"
  local processes count suspicious
  if ! processes=$(ps aux 2>/dev/null) || [[ -z $processes ]]; then
    warn "Cannot check processes (ps unavailable, failed or returned no inventory)"
    return
  fi
  count=$(printf '%s\n' "$processes" | awk '$1 == "root" {n++} END {print n+0}')
  info "Processes running as root: $count"
  suspicious=$(printf '%s\n' "$processes" | awk 'tolower($0) ~ /(backdoor|trojan|malware|virus|hack|exploit)/')
  if [[ -n $suspicious ]]; then
    fail "Potentially suspicious processes detected:"
    while IFS= read -r line; do print_list_item "$line"; done <<< "$suspicious"
  fi
}

# Check filesystem
check_filesystem() {
  section "FILESYSTEM"
  local dirs=(/etc /usr/bin /usr/sbin /bin /sbin)
  local found=false complete=true directory writable disk usage
  for directory in "${dirs[@]}"; do
    [[ -d $directory ]] || continue
    # awk drains find's output so a valid long result cannot become SIGPIPE.
    if ! writable=$(find "$directory" -type f -perm -002 2>/dev/null | awk 'NR <= 5'); then
      warn "Cannot check world-writable files in $directory (find failed)"
      complete=false
      continue
    fi
    if [[ -n $writable ]]; then
      [[ $found == true ]] || warn "World-writable files in sensitive directories:"
      found=true
      while IFS= read -r file; do print_list_item "$file"; done <<< "$writable"
    fi
  done
  if [[ $found == false && $complete == true ]]; then
    ok "No world-writable files in sensitive directories"
  fi
  if ! disk=$(df -P / 2>/dev/null); then
    warn "Cannot check disk usage (df unavailable or failed)"
    return
  fi
  usage=$(printf '%s\n' "$disk" | awk 'NR==2 {print $(NF-1)}')
  usage=${usage%\%}
  if [[ ! $usage =~ ^[0-9]{1,3}$ ]]; then
    warn "Cannot determine disk usage (unexpected df output)"
  elif [[ $((10#$usage)) -gt 90 ]]; then
    warn "Disk usage: ${usage}% (critical)"
  elif [[ $((10#$usage)) -gt 80 ]]; then
    warn "Disk usage: ${usage}% (high)"
  else
    ok "Disk usage: ${usage}%"
  fi
}

# Final summary with proper status levels
summary() {
  section "RESULT"
  
  local failures
  failures=$(get_failures)
  local warnings
  warnings=$(get_warnings)
  
  if [[ $failures -gt 0 ]]; then
    echo ""
    fail "🔴 OVERALL STATUS: ATTENTION REQUIRED"
    fail "Critical issues detected: $failures"
    if [[ $warnings -gt 0 ]]; then
      warn "Warnings: $warnings"
    fi
    echo ""
    info "Please review the issues above before using this VPS in production."
  elif [[ $warnings -gt 0 ]]; then
    echo ""
    warn "🟡 OVERALL STATUS: REVIEW RECOMMENDED"
    warn "Warnings: $warnings"
    echo ""
    info "System appears functional, but some items should be reviewed."
  else
    echo ""
    ok "🟢 OVERALL STATUS: NO FINDINGS IN COMPLETED CHECKS"
    echo ""
    ok "No findings in the selected completed checks; this does not establish that the system is uncompromised."
  fi
  
  echo ""
  info "Note: This tool checks what can be verified from inside the VPS."
  info "VPS providers have hypervisor-level access (this is expected)."
  
  echo ""
  sub_section "Report generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
}
