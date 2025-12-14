#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"

banner() {
  clear
  cat <<EOF
${BOLD}${CYAN}
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║         VPS SANITY CHECK — by bglglzd                        ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
${RESET}
EOF
}

section() {
  local title="$1"
  local width=60
  local padding=$((width - ${#title} - 2))
  local dashes=$(printf '%*s' $padding '' | tr ' ' '─')
  echo -e "\n${BOLD}${CYAN}── ${title} ${dashes}${RESET}"
}

sub_section() {
  echo -e "${DIM}    $1${RESET}"
}

print_list_item() {
  echo -e "    ${CYAN}•${RESET} $1"
}

print_table_row() {
  printf "    %-30s %s\n" "$1" "$2"
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    fail "This script must be run as root (use sudo)"
    exit 1
  fi
}

check_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

get_uptime() {
  local uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
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

