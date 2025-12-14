#!/usr/bin/env bash

# VPS Sanity Check - Security Checks Module
# All security checks are implemented here

source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Check OS and system information
check_os() {
  section "SYSTEM"
  
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    ok "OS detected: ${PRETTY_NAME:-$NAME}"
  else
    warn "Cannot detect OS (no /etc/os-release)"
    return
  fi
  
  local kernel=$(uname -r)
  ok "Kernel: $kernel"
  
  local uptime=$(get_uptime)
  ok "Uptime: $uptime"
  
  local hostname=$(hostname 2>/dev/null || echo "unknown")
  info "Hostname: $hostname"
}

# Check users - uses UID and shell logic, not hardcoded lists
check_users() {
  section "USERS"
  
  local suspicious_users=()
  local system_users=()
  local uid0_users=()
  local no_passwd_warn=()
  local no_passwd_info=()
  
  # Read /etc/passwd and analyze each user
  while IFS=: read -r username _ uid _ _ _ shell; do
    [[ -z "$username" ]] && continue
    
    # Check for UID 0 users other than root
    if [[ $uid -eq 0 && "$username" != "root" ]]; then
      uid0_users+=("$username")
      continue
    fi
    
    # System users (UID < 1000) - informational only
    if [[ $uid -lt 1000 ]]; then
      system_users+=("$username")
      
      # Check password status for system users (INFO level)
      if [[ -f /etc/shadow ]]; then
        local passwd_status=$(awk -F: -v u="$username" '$1 == u {print $2}' /etc/shadow 2>/dev/null)
        if [[ -z "$passwd_status" || "$passwd_status" == "!" || "$passwd_status" == "*" ]]; then
          no_passwd_info+=("$username")
        fi
      fi
      continue
    fi
    
    # Regular users (UID >= 1000)
    # Suspicious if shell is NOT nologin/false (i.e., has interactive shell)
    if [[ "$shell" != "/usr/sbin/nologin" && "$shell" != "/bin/false" && "$shell" != "/sbin/nologin" ]]; then
      suspicious_users+=("$username")
    fi
    
    # Check password status for regular users (WARN level)
    if [[ -f /etc/shadow ]]; then
      local passwd_status=$(awk -F: -v u="$username" '$1 == u {print $2}' /etc/shadow 2>/dev/null)
      if [[ -z "$passwd_status" || "$passwd_status" == "!" || "$passwd_status" == "*" ]]; then
        no_passwd_warn+=("$username")
      fi
    fi
  done < /etc/passwd
  
  # Report findings
  if [[ ${#uid0_users[@]} -gt 0 ]]; then
    fail "Users with UID 0 (root privileges) other than root:"
    for user in "${uid0_users[@]}"; do
      print_list_item "$user"
    done
  fi
  
  if [[ ${#suspicious_users[@]} -gt 0 ]]; then
    warn "Interactive user accounts (UID >= 1000 with login shell):"
    for user in "${suspicious_users[@]}"; do
      local uid=$(id -u "$user" 2>/dev/null || echo "?")
      local shell=$(getent passwd "$user" | cut -d: -f7)
      print_list_item "$user (UID: $uid, Shell: $shell)"
    done
  else
    ok "No suspicious interactive user accounts found"
  fi
  
  if [[ ${#no_passwd_warn[@]} -gt 0 ]]; then
    warn "Regular users without passwords:"
    for user in "${no_passwd_warn[@]}"; do
      print_list_item "$user"
    done
  fi
  
  if [[ ${#no_passwd_info[@]} -gt 0 ]]; then
    info "System users without passwords (expected): ${#no_passwd_info[@]}"
  fi
  
  if [[ ${#system_users[@]} -gt 0 ]]; then
    info "System users (UID < 1000): ${#system_users[@]}"
  fi
}

# Check sudo configuration
check_sudo() {
  section "SUDO"
  
  if ! check_command "getent"; then
    warn "Cannot check sudo users (getent not available)"
    return
  fi
  
  local sudo_users=$(getent group sudo 2>/dev/null | cut -d: -f4 | tr ',' '\n' | grep -v '^$' || true)
  local sudo_count=$(echo "$sudo_users" | grep -c . || echo "0")
  
  if [[ $sudo_count -eq 0 ]]; then
    info "No users in sudo group"
  else
    ok "Sudo users ($sudo_count):"
    while IFS= read -r user; do
      [[ -n "$user" ]] && print_list_item "$user"
    done <<< "$sudo_users"
  fi
  
  # Check for custom sudoers entries (informational)
  if [[ -f /etc/sudoers ]]; then
    local sudoers_entries=$(grep -vE '^#|^$|^Defaults|^%' /etc/sudoers 2>/dev/null | grep -v '^@' || true)
    if [[ -n "$sudoers_entries" ]]; then
      info "Custom sudoers entries found (review recommended)"
    fi
  fi
}

# Check SSH configuration
check_ssh() {
  section "SSH"
  
  local sshd_config="/etc/ssh/sshd_config"
  
  if [[ ! -f "$sshd_config" ]]; then
    warn "SSH config file not found"
    return
  fi
  
  # Check PermitRootLogin
  if grep -qE "^PermitRootLogin\s+no" "$sshd_config"; then
    ok "Root login: DISABLED"
  elif grep -qE "^PermitRootLogin\s+yes" "$sshd_config"; then
    fail "Root login: ENABLED (security risk)"
  else
    warn "Root login: not explicitly disabled (default may allow)"
  fi
  
  # Check PasswordAuthentication
  if grep -qE "^PasswordAuthentication\s+no" "$sshd_config"; then
    ok "Password authentication: DISABLED"
  elif grep -qE "^PasswordAuthentication\s+yes" "$sshd_config"; then
    warn "Password authentication: ENABLED (consider disabling)"
  else
    info "Password authentication: using default (usually enabled)"
  fi
  
  # Check PubkeyAuthentication
  if grep -qE "^PubkeyAuthentication\s+yes" "$sshd_config" || ! grep -qE "^PubkeyAuthentication" "$sshd_config"; then
    ok "Public key authentication: ENABLED"
  else
    warn "Public key authentication: DISABLED"
  fi
  
  # Check authorized keys (informational)
  local total_keys=0
  local key_users=()
  
  while IFS=: read -r username _ _ _ _ home _; do
    [[ -z "$username" || -z "$home" ]] && continue
    local user_keys="$home/.ssh/authorized_keys"
    if [[ -f "$user_keys" ]]; then
      local count=$(grep -c "^ssh-" "$user_keys" 2>/dev/null || echo "0")
      if [[ $count -gt 0 ]]; then
        ((total_keys += count))
        key_users+=("$username: $count")
      fi
    fi
  done < /etc/passwd
  
  if [[ $total_keys -gt 0 ]]; then
    ok "Authorized keys: $total_keys total"
    for entry in "${key_users[@]}"; do
      print_list_item "$entry key(s)"
    done
  else
    info "No authorized keys found"
  fi
  
  # Check SSH port (informational)
  local ssh_port=$(grep -E "^Port\s+" "$sshd_config" | awk '{print $2}' | head -1)
  if [[ -n "$ssh_port" && "$ssh_port" != "22" ]]; then
    info "SSH listening on non-standard port: $ssh_port"
  fi
}

# Check network listeners - fixed parsing
check_network() {
  section "NETWORK"
  
  if ! check_command "ss"; then
    warn "Cannot check network (ss command not available)"
    return
  fi
  
  local listening=$(ss -tulpn 2>/dev/null | grep LISTEN || true)
  
  if [[ -z "$listening" ]]; then
    info "No listening ports found"
    return
  fi
  
  local ports_displayed=0
  local suspicious_ports=()
  
  # Parse ss output properly
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    
    # Extract address:port from the 5th field
    local addr_port=$(echo "$line" | awk '{print $5}')
    
    # Skip if localhost only
    if echo "$addr_port" | grep -qE "^127\.0\.0\.1:|^::1:"; then
      continue
    fi
    
    # Extract port (everything after last colon)
    local port=$(echo "$addr_port" | awk -F: '{print $NF}' | awk '{print $1}')
    local protocol=$(echo "$line" | awk '{print $1}' | tr '[:lower:]' '[:upper:]')
    
    # Extract process name from last field
    local process="unknown"
    if echo "$line" | grep -q "users:"; then
      # Extract process name from users:((("name",pid=...)) format
      process=$(echo "$line" | sed -n 's/.*users:((("\([^"]*\)".*/\1/p' | head -1)
      # If that didn't work, try alternative format
      if [[ -z "$process" || "$process" == "$line" ]]; then
        process=$(echo "$line" | sed -n 's/.*users:((\([^,]*\).*/\1/p' | sed 's/"//g' | head -1)
      fi
      # Clean up - remove path, keep just basename
      if [[ -n "$process" && "$process" != "unknown" ]]; then
        process=$(basename "$process" 2>/dev/null || echo "$process")
      fi
    fi
    
    # Skip if port is empty
    [[ -z "$port" || "$port" == "/" ]] && continue
    
    # Skip systemd/init processes
    if [[ "$process" == "systemd" || "$process" == "init" || "$process" == "1" ]]; then
      continue
    fi
    
    # Display port
    if [[ $ports_displayed -eq 0 ]]; then
      ok "Listening ports:"
      ports_displayed=1
    fi
    print_list_item "$port/$protocol ($process)"
    
    # Check for suspicious ports
    if echo "$port" | grep -qE "^(4444|5555|6666|12345|31337|54321)$"; then
      suspicious_ports+=("$port/$protocol")
    fi
  done <<< "$listening"
  
  if [[ $ports_displayed -eq 0 ]]; then
    info "No external listening ports found (localhost only)"
  fi
  
  # Report suspicious ports
  if [[ ${#suspicious_ports[@]} -gt 0 ]]; then
    warn "Potentially suspicious ports detected:"
    for port in "${suspicious_ports[@]}"; do
      print_list_item "$port"
    done
  fi
}

# Check cron jobs and autostart
check_cron() {
  section "CRON / AUTOSTART"
  
  # Root crontab
  local root_cron=$(crontab -l -u root 2>/dev/null || true)
  if [[ -n "$root_cron" ]]; then
    local root_cron_lines=$(echo "$root_cron" | grep -vE '^#|^$' | wc -l)
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
  
  # System-wide cron directories (informational)
  local cron_dirs=("/etc/cron.d" "/etc/cron.daily" "/etc/cron.hourly" "/etc/cron.weekly" "/etc/cron.monthly")
  local total_cron_files=0
  for dir in "${cron_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      local files=$(find "$dir" -type f 2>/dev/null | wc -l)
      ((total_cron_files += files))
    fi
  done
  if [[ $total_cron_files -gt 0 ]]; then
    info "System cron files: $total_cron_files"
  fi
  
  # Check for suspicious cron entries (downloading from internet)
  local suspicious_cron=$(grep -rE "(wget|curl|bash|sh)\s+.*https?://" /etc/cron* 2>/dev/null | grep -vE '^#|^$' || true)
  if [[ -n "$suspicious_cron" ]]; then
    warn "Potentially suspicious cron entries (downloading from internet):"
    while IFS= read -r line; do
      [[ -n "$line" ]] && print_list_item "$line"
    done <<< "$suspicious_cron"
  fi
}

# Check system services
check_services() {
  section "SERVICES"
  
  if ! check_command "systemctl"; then
    warn "Cannot check services (systemctl not available)"
    return
  fi
  
  local enabled_services=$(systemctl list-unit-files --type=service --state=enabled 2>/dev/null | grep -E "\.service$" | awk '{print $1}' || true)
  local service_count=$(echo "$enabled_services" | grep -c . || echo "0")
  
  ok "Enabled services: $service_count"
  
  # Check for failed services
  local failed_services=$(systemctl list-units --type=service --state=failed 2>/dev/null | grep -E "\.service$" | awk '{print $1}' || true)
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
    local debsums_output=$(debsums -s 2>&1)
    local debsums_errors=$(echo "$debsums_output" | grep -iE "FAILED|MISSING|changed|modified" || true)
    
    if [[ -z "$debsums_errors" ]]; then
      ok "Package integrity: OK (debsums)"
    else
      fail "Package integrity issues detected (debsums):"
      while IFS= read -r line; do
        [[ -n "$line" ]] && print_list_item "$line"
      done <<< "$debsums_errors"
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
      local resolved=$(resolve_symlink "$bin")
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
  
  if ! check_command "ps"; then
    warn "Cannot check processes (ps not available)"
    return
  fi
  
  # Count root processes (informational)
  local root_proc_count=$(ps aux 2>/dev/null | awk '$1 == "root" {count++} END {print count+0}')
  info "Processes running as root: $root_proc_count"
  
  # Check for suspicious process names (only real matches)
  local suspicious_procs=$(ps aux 2>/dev/null | grep -iE "(backdoor|trojan|malware|virus|hack|exploit)" | grep -v grep || true)
  if [[ -n "$suspicious_procs" ]]; then
    fail "Potentially suspicious processes detected:"
    while IFS= read -r line; do
      [[ -n "$line" ]] && print_list_item "$line"
    done <<< "$suspicious_procs"
  fi
}

# Check filesystem
check_filesystem() {
  section "FILESYSTEM"
  
  # Check for world-writable files in sensitive directories
  local sensitive_dirs=("/etc" "/usr/bin" "/usr/sbin" "/bin" "/sbin")
  local found_writable=false
  
  for dir in "${sensitive_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      local writable=$(find "$dir" -type f -perm -002 2>/dev/null | head -5 || true)
      if [[ -n "$writable" ]]; then
        if [[ "$found_writable" == false ]]; then
          warn "World-writable files in sensitive directories:"
          found_writable=true
        fi
        while IFS= read -r file; do
          [[ -n "$file" ]] && print_list_item "$file"
        done <<< "$writable"
      fi
    fi
  done
  
  if [[ "$found_writable" == false ]]; then
    ok "No world-writable files in sensitive directories"
  fi
  
  # Check disk usage
  local disk_usage=$(df -h / 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//' || echo "0")
  if [[ $disk_usage -gt 90 ]]; then
    warn "Disk usage: ${disk_usage}% (critical)"
  elif [[ $disk_usage -gt 80 ]]; then
    warn "Disk usage: ${disk_usage}% (high)"
  else
    ok "Disk usage: ${disk_usage}%"
  fi
}

# Final summary with proper status levels
summary() {
  section "RESULT"
  
  local failures=$(get_failures)
  local warnings=$(get_warnings)
  
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
    ok "🟢 OVERALL STATUS: SYSTEM CLEAN"
    echo ""
    ok "No critical issues or warnings detected."
  fi
  
  echo ""
  info "Note: This tool checks what can be verified from inside the VPS."
  info "VPS providers have hypervisor-level access (this is expected)."
  
  echo ""
  sub_section "Report generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
}
