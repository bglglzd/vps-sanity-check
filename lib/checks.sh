#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Standard system users (not suspicious)
STANDARD_USERS=(
  "root" "daemon" "bin" "sys" "sync" "games" "man" "lp" "mail" "news"
  "uucp" "proxy" "www-data" "backup" "list" "irc" "_apt" "nobody"
  "systemd-network" "systemd-resolve" "systemd-timesync" "messagebus"
  "sshd" "syslog" "uuidd" "tcpdump" "tss" "landscape" "pollinate"
  "ubuntu" "deploy" "admin" "user"
)

check_os() {
  section "SYSTEM"
  
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    ok "OS detected: ${PRETTY_NAME:-$NAME}"
  else
    warn "Cannot detect OS (no /etc/os-release)"
    add_warning
  fi
  
  local kernel=$(uname -r)
  ok "Kernel: $kernel"
  
  local uptime=$(get_uptime)
  ok "Uptime: $uptime"
  
  local hostname=$(hostname)
  info "Hostname: $hostname"
}

check_users() {
  section "USERS"
  
  local suspicious_users=()
  local all_users=$(cut -d: -f1 /etc/passwd)
  
  while IFS= read -r user; do
    local is_standard=0
    for standard_user in "${STANDARD_USERS[@]}"; do
      if [[ "$user" == "$standard_user" ]]; then
        is_standard=1
        break
      fi
    done
    
    if [[ $is_standard -eq 0 ]]; then
      suspicious_users+=("$user")
    fi
  done <<< "$all_users"
  
  if [[ ${#suspicious_users[@]} -eq 0 ]]; then
    ok "No suspicious users found"
  else
    warn "Found ${#suspicious_users[@]} potentially suspicious user(s):"
    add_warning
    for user in "${suspicious_users[@]}"; do
      local uid=$(id -u "$user" 2>/dev/null || echo "?")
      local shell=$(getent passwd "$user" | cut -d: -f7)
      print_list_item "$user (UID: $uid, Shell: $shell)"
    done
  fi
  
  # Check for users with UID 0 (other than root)
  local uid0_users=$(awk -F: '$3 == 0 && $1 != "root" {print $1}' /etc/passwd)
  if [[ -n "$uid0_users" ]]; then
    fail "Users with UID 0 (root privileges):"
    add_failure
    while IFS= read -r user; do
      print_list_item "$user"
    done <<< "$uid0_users"
  fi
  
  # Check for users without passwords
  local no_passwd=$(awk -F: '($2 == "" || $2 == "!") && $1 != "root" {print $1}' /etc/shadow 2>/dev/null || true)
  if [[ -n "$no_passwd" ]]; then
    warn "Users without passwords:"
    add_warning
    while IFS= read -r user; do
      print_list_item "$user"
    done <<< "$no_passwd"
  fi
}

check_sudo() {
  section "SUDO"
  
  if ! check_command "getent"; then
    warn "Cannot check sudo users (getent not available)"
    add_warning
    return
  fi
  
  local sudo_users=$(getent group sudo 2>/dev/null | cut -d: -f4 | tr ',' '\n' | grep -v '^$')
  local sudo_count=$(echo "$sudo_users" | grep -c . || echo "0")
  
  if [[ $sudo_count -eq 0 ]]; then
    info "No users in sudo group"
  else
    ok "Sudo users ($sudo_count):"
    while IFS= read -r user; do
      [[ -n "$user" ]] && print_list_item "$user"
    done <<< "$sudo_users"
  fi
  
  # Check sudoers file
  if [[ -f /etc/sudoers ]]; then
    local sudoers_entries=$(grep -v '^#' /etc/sudoers | grep -v '^$' | grep -v '^Defaults' | grep -v '^%' || true)
    if [[ -n "$sudoers_entries" ]]; then
      info "Custom sudoers entries found"
      while IFS= read -r entry; do
        [[ -n "$entry" ]] && sub_section "  $entry"
      done <<< "$sudoers_entries"
    fi
  fi
}

check_ssh() {
  section "SSH"
  
  local sshd_config="/etc/ssh/sshd_config"
  
  if [[ ! -f "$sshd_config" ]]; then
    warn "SSH config file not found"
    add_warning
    return
  fi
  
  # Check PermitRootLogin
  if grep -qE "^PermitRootLogin\s+no" "$sshd_config"; then
    ok "Root login: DISABLED"
  elif grep -qE "^PermitRootLogin\s+yes" "$sshd_config"; then
    fail "Root login: ENABLED (security risk!)"
    add_failure
  else
    warn "Root login: not explicitly disabled (default may allow)"
    add_warning
  fi
  
  # Check PasswordAuthentication
  if grep -qE "^PasswordAuthentication\s+no" "$sshd_config"; then
    ok "Password authentication: DISABLED"
  elif grep -qE "^PasswordAuthentication\s+yes" "$sshd_config"; then
    warn "Password authentication: ENABLED (consider disabling)"
    add_warning
  else
    info "Password authentication: using default (usually enabled)"
  fi
  
  # Check PubkeyAuthentication
  if grep -qE "^PubkeyAuthentication\s+yes" "$sshd_config" || ! grep -qE "^PubkeyAuthentication" "$sshd_config"; then
    ok "Public key authentication: ENABLED"
  else
    warn "Public key authentication: DISABLED"
    add_warning
  fi
  
  # Check authorized keys
  local root_keys="/root/.ssh/authorized_keys"
  local root_key_count=0
  if [[ -f "$root_keys" ]]; then
    root_key_count=$(grep -c "^ssh-" "$root_keys" 2>/dev/null || echo "0")
  fi
  
  # Check all users' authorized_keys
  local total_keys=0
  while IFS= read -r user; do
    local user_home=$(getent passwd "$user" | cut -d: -f6)
    local user_keys="$user_home/.ssh/authorized_keys"
    if [[ -f "$user_keys" ]]; then
      local count=$(grep -c "^ssh-" "$user_keys" 2>/dev/null || echo "0")
      ((total_keys += count))
      if [[ $count -gt 0 ]]; then
        print_list_item "$user: $count key(s)"
      fi
    fi
  done < <(cut -d: -f1 /etc/passwd)
  
  if [[ $total_keys -gt 0 ]]; then
    ok "Total authorized keys: $total_keys"
  else
    info "No authorized keys found"
  fi
  
  # Check SSH port
  local ssh_port=$(grep -E "^Port\s+" "$sshd_config" | awk '{print $2}' | head -1)
  if [[ -n "$ssh_port" && "$ssh_port" != "22" ]]; then
    info "SSH listening on non-standard port: $ssh_port"
  fi
}

check_network() {
  section "NETWORK"
  
  if ! check_command "ss"; then
    warn "Cannot check network (ss command not available)"
    add_warning
    return
  fi
  
  local listening=$(ss -tulpn 2>/dev/null | grep LISTEN || true)
  
  if [[ -z "$listening" ]]; then
    info "No listening ports found"
    return
  fi
  
  ok "Listening ports:"
  
  while IFS= read -r line; do
    local port=$(echo "$line" | awk '{print $5}' | cut -d: -f2 | cut -d' ' -f1)
    local protocol=$(echo "$line" | awk '{print $1}')
    local process=$(echo "$line" | awk '{print $7}' | sed 's/users:((//' | sed 's/,.*//' || echo "unknown")
    
    # Skip localhost only
    if echo "$line" | grep -q "127.0.0.1"; then
      continue
    fi
    
    print_list_item "$port/$protocol ($process)"
  done <<< "$listening"
  
  # Check for suspicious ports
  local suspicious_ports=$(echo "$listening" | grep -E ":(4444|5555|6666|12345|31337|54321)" || true)
  if [[ -n "$suspicious_ports" ]]; then
    warn "Potentially suspicious ports detected:"
    add_warning
    while IFS= read -r line; do
      print_list_item "$line"
    done <<< "$suspicious_ports"
  fi
}

check_cron() {
  section "CRON / AUTOSTART"
  
  # Root crontab
  local root_cron=$(crontab -l -u root 2>/dev/null || true)
  if [[ -n "$root_cron" ]]; then
    local root_cron_lines=$(echo "$root_cron" | grep -v '^#' | grep -v '^$' | wc -l)
    if [[ $root_cron_lines -gt 0 ]]; then
      info "Root crontab entries: $root_cron_lines"
      while IFS= read -r line; do
        if [[ -n "$line" && ! "$line" =~ ^# ]]; then
          print_list_item "$line"
        fi
      done <<< "$root_cron"
    else
      ok "Root crontab: empty or only comments"
    fi
  else
    ok "Root crontab: none"
  fi
  
  # System-wide cron
  local cron_dirs=("/etc/cron.d" "/etc/cron.daily" "/etc/cron.hourly" "/etc/cron.weekly" "/etc/cron.monthly")
  for dir in "${cron_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      local files=$(find "$dir" -type f 2>/dev/null | wc -l)
      if [[ $files -gt 0 ]]; then
        info "Cron files in $dir: $files"
      fi
    fi
  done
  
  # Check for suspicious cron entries
  local suspicious_cron=$(grep -rE "(wget|curl|bash|sh)\s+.*http" /etc/cron* 2>/dev/null || true)
  if [[ -n "$suspicious_cron" ]]; then
    warn "Potentially suspicious cron entries (downloading from internet):"
    add_warning
    while IFS= read -r line; do
      print_list_item "$line"
    done <<< "$suspicious_cron"
  fi
}

check_services() {
  section "SERVICES"
  
  if ! check_command "systemctl"; then
    warn "Cannot check services (systemctl not available)"
    add_warning
    return
  fi
  
  local enabled_services=$(systemctl list-unit-files --type=service --state=enabled 2>/dev/null | grep -E "\.service" | awk '{print $1}' || true)
  local service_count=$(echo "$enabled_services" | grep -c . || echo "0")
  
  ok "Enabled services: $service_count"
  
  # Filter out standard system services
  local suspicious_services=()
  while IFS= read -r service; do
    [[ -z "$service" ]] && continue
    
    # Skip standard services
    if [[ "$service" =~ ^(systemd|dbus|network|ssh|rsyslog|cron|getty|user@) ]]; then
      continue
    fi
    
    suspicious_services+=("$service")
  done <<< "$enabled_services"
  
  if [[ ${#suspicious_services[@]} -gt 0 ]]; then
    info "Non-standard enabled services:"
    for service in "${suspicious_services[@]}"; do
      print_list_item "$service"
    done
  fi
  
  # Check for failed services
  local failed_services=$(systemctl list-units --type=service --state=failed 2>/dev/null | grep -E "\.service" | awk '{print $1}' || true)
  if [[ -n "$failed_services" ]]; then
    warn "Failed services detected:"
    add_warning
    while IFS= read -r service; do
      [[ -n "$service" ]] && print_list_item "$service"
    done <<< "$failed_services"
  fi
}

check_integrity() {
  section "PACKAGE INTEGRITY"
  
  if check_command "debsums"; then
    info "Checking package integrity with debsums..."
    local debsums_output=$(debsums -s 2>&1)
    local debsums_errors=$(echo "$debsums_output" | grep -i "FAILED\|MISSING\|changed" || true)
    
    if [[ -z "$debsums_errors" ]]; then
      ok "Package integrity: OK"
    else
      fail "Package integrity issues detected:"
      add_failure
      while IFS= read -r line; do
        [[ -n "$line" ]] && print_list_item "$line"
      done <<< "$debsums_errors"
    fi
  else
    warn "debsums not installed (install with: apt-get install debsums)"
    info "Skipping package integrity check"
    add_warning
  fi
  
  # Check for modified system binaries
  local critical_bins=("/bin/bash" "/bin/sh" "/usr/bin/sudo" "/usr/bin/su")
  for bin in "${critical_bins[@]}"; do
    if [[ -f "$bin" ]]; then
      if ! dpkg -S "$bin" >/dev/null 2>&1; then
        warn "Critical binary not owned by any package: $bin"
        add_warning
      fi
    fi
  done
}

check_processes() {
  section "PROCESSES"
  
  if ! check_command "ps"; then
    warn "Cannot check processes (ps not available)"
    add_warning
    return
  fi
  
  # Check for processes running as root
  local root_procs=$(ps aux | awk '$1 == "root" && $11 !~ /^\[/ {print $11}' | sort -u | head -20)
  local root_proc_count=$(ps aux | awk '$1 == "root" {count++} END {print count+0}')
  
  info "Processes running as root: $root_proc_count"
  
  # Check for suspicious process names
  local suspicious_procs=$(ps aux | grep -iE "(backdoor|trojan|malware|virus|hack|exploit)" | grep -v grep || true)
  if [[ -n "$suspicious_procs" ]]; then
    fail "Potentially suspicious processes detected:"
    add_failure
    while IFS= read -r line; do
      print_list_item "$line"
    done <<< "$suspicious_procs"
  fi
  
  # Check for processes listening on network
  if check_command "netstat"; then
    local listening_procs=$(netstat -tulpn 2>/dev/null | grep LISTEN | awk '{print $7}' | cut -d'/' -f2 | sort -u || true)
    if [[ -n "$listening_procs" ]]; then
      info "Processes with network listeners:"
      while IFS= read -r proc; do
        [[ -n "$proc" && "$proc" != "-" ]] && print_list_item "$proc"
      done <<< "$listening_procs"
    fi
  fi
}

check_filesystem() {
  section "FILESYSTEM"
  
  # Check for world-writable files in sensitive directories
  local sensitive_dirs=("/etc" "/usr/bin" "/usr/sbin" "/bin" "/sbin")
  for dir in "${sensitive_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      local writable=$(find "$dir" -type f -perm -002 2>/dev/null | head -10 || true)
      if [[ -n "$writable" ]]; then
        warn "World-writable files in $dir:"
        add_warning
        while IFS= read -r file; do
          print_list_item "$file"
        done <<< "$writable"
      fi
    fi
  done
  
  # Check disk usage
  local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
  if [[ $disk_usage -gt 90 ]]; then
    warn "Disk usage: ${disk_usage}% (critical)"
    add_warning
  elif [[ $disk_usage -gt 80 ]]; then
    warn "Disk usage: ${disk_usage}% (high)"
    add_warning
  else
    ok "Disk usage: ${disk_usage}%"
  fi
}

summary() {
  section "RESULT"
  
  if [[ $STATUS_FAILURES -gt 0 ]]; then
    fail "STATUS: ${RED}${BOLD}SYSTEM HAS ISSUES${RESET}"
    fail "Failures detected: $STATUS_FAILURES"
    if [[ $STATUS_WARNINGS -gt 0 ]]; then
      warn "Warnings: $STATUS_WARNINGS"
    fi
    echo ""
    fail "⚠️  Review the issues above before using this VPS in production"
  elif [[ $STATUS_WARNINGS -gt 0 ]]; then
    warn "STATUS: ${YELLOW}${BOLD}SYSTEM LOOKS MOSTLY CLEAN${RESET}"
    warn "Warnings: $STATUS_WARNINGS"
    echo ""
    info "⚠️  Review warnings above for potential improvements"
  else
    ok "STATUS: ${GREEN}${BOLD}SYSTEM LOOKS CLEAN${RESET}"
    echo ""
    ok "✓ No critical issues detected"
  fi
  
  echo ""
  info "NOTE: This tool checks what can be checked from inside the VPS."
  info "VPS host/provider may still have hypervisor-level access."
  info "This is normal and expected for VPS services."
  
  echo ""
  sub_section "Report generated: $(date)"
}

