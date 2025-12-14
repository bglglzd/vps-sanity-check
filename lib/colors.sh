#!/usr/bin/env bash

# VPS Sanity Check - Color and Output Module
# Handles TTY detection and color output

# Detect if stdout is a TTY and colors should be used
if [[ -t 1 ]]; then
  USE_COLOR=true
else
  USE_COLOR=false
fi

# Color wrapper function - returns color code only if colors are enabled
color() {
  if [[ "$USE_COLOR" == "true" ]]; then
    echo -ne "$1"
  fi
  # If colors disabled, return empty string (captured by $())
}

# Color definitions - empty if not TTY, actual codes if TTY
GREEN=$(color "\033[32m")
RED=$(color "\033[31m")
YELLOW=$(color "\033[33m")
BLUE=$(color "\033[34m")
CYAN=$(color "\033[36m")
BOLD=$(color "\033[1m")
DIM=$(color "\033[2m")
RESET=$(color "\033[0m")

# Status icons (Unicode, safe for UTF-8 terminals)
ICON_OK="✔"
ICON_INFO="ℹ"
ICON_WARN="!"
ICON_FAIL="✘"

# Status tracking counters
STATUS_WARNINGS=0
STATUS_FAILURES=0

# Output functions with proper severity levels

# OK - Everything is fine (green)
ok() {
  echo -e "${GREEN}[${ICON_OK}]${RESET} $1"
}

# INFO - Informational message, normal system behavior (blue)
# Does NOT increment warning counter
info() {
  echo -e "${BLUE}[${ICON_INFO}]${RESET} $1"
}

# WARN - Warning, should be reviewed (yellow)
# Increments warning counter
warn() {
  echo -e "${YELLOW}[${ICON_WARN}]${RESET} $1"
  STATUS_WARNINGS=$((STATUS_WARNINGS + 1))
}

# FAIL - Critical security issue (red)
# Increments failure counter
fail() {
  echo -e "${RED}[${ICON_FAIL}]${RESET} $1"
  STATUS_FAILURES=$((STATUS_FAILURES + 1))
}

# Helper to get current warning count
get_warnings() {
  echo "$STATUS_WARNINGS"
}

# Helper to get current failure count
get_failures() {
  echo "$STATUS_FAILURES"
}
