#!/usr/bin/env bash

# VPS Sanity Check - Helper Functions Module

source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"

# Display banner with version
banner() {
  clear
  cat <<EOF
${BOLD}${CYAN}
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║         VPS SANITY CHECK v1.1.0 — by bglglzd                 ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
${RESET}
EOF
}

# Display section header
section() {
  local title="$1"
  local width=60
  local padding=$((width - ${#title} - 2))
  local dashes=$(printf '%*s' $padding '' | tr ' ' '─')
  echo -e "\n${BOLD}${CYAN}── ${title} ${dashes}${RESET}"
}

# Display sub-section (dimmed text)
sub_section() {
  echo -e "${DIM}    $1${RESET}"
}

# Print list item with bullet
print_list_item() {
  echo -e "    ${CYAN}•${RESET} $1"
}

# Print table row (for structured data)
print_table_row() {
  printf "    %-30s %s\n" "$1" "$2"
}

# Check if running as root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    fail "This script must be run as root (use sudo)"
    exit 1
  fi
}

# Check if command exists
check_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

# Get formatted uptime
get_uptime() {
  local uptime_seconds=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "0")
  local days=$((uptime_seconds / 86400))
  local hours=$(((uptime_seconds % 86400) / 3600))
  local minutes=$(((uptime_seconds % 3600) / 60))
  
  if [[ $days -gt 0 ]]; then
    echo "${days}d ${hours}h ${minutes}m"
  elif [[ $hours -gt 0 ]]; then
    echo "${hours}h ${minutes}m"
  else
    echo "${minutes}m"
  fi
}

# Resolve symlink to real path
resolve_symlink() {
  local path="$1"
  if [[ -L "$path" ]]; then
    readlink -f "$path" 2>/dev/null || echo "$path"
  else
    echo "$path"
  fi
}

# Check if file is owned by a package (handles symlinks)
is_package_owned() {
  local file="$1"
  local resolved
  
  # Try direct path first
  if dpkg -S "$file" >/dev/null 2>&1; then
    return 0
  fi
  
  # If it's a symlink, resolve and check
  resolved=$(resolve_symlink "$file")
  if [[ "$resolved" != "$file" ]] && dpkg -S "$resolved" >/dev/null 2>&1; then
    return 0
  fi
  
  return 1
}
