#!/usr/bin/env bash

# Color definitions
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
MAGENTA="\e[35m"
BOLD="\e[1m"
DIM="\e[2m"
RESET="\e[0m"

# Status icons
ICON_OK="✔"
ICON_WARN="!"
ICON_FAIL="✘"
ICON_INFO="*"

# Output functions
ok() {
  echo -e "${GREEN}[${ICON_OK}]${RESET} $1"
}

warn() {
  echo -e "${YELLOW}[${ICON_WARN}]${RESET} $1"
}

fail() {
  echo -e "${RED}[${ICON_FAIL}]${RESET} $1"
}

info() {
  echo -e "${BLUE}[${ICON_INFO}]${RESET} $1"
}

# Status tracking
STATUS_CLEAN=0
STATUS_WARNINGS=0
STATUS_FAILURES=0

add_warning() {
  STATUS_WARNINGS=$((STATUS_WARNINGS + 1))
}

add_failure() {
  STATUS_FAILURES=$((STATUS_FAILURES + 1))
}

