#!/usr/bin/env bash

set -uo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/helpers.sh"
source "$SCRIPT_DIR/lib/checks.sh"

# Main execution
main() {
  banner
  
  # Check if running as root
  check_root
  
  # Run all checks
  check_os
  check_users
  check_sudo
  check_ssh
  check_network
  check_processes
  check_cron
  check_services
  check_integrity
  check_filesystem
  
  # Show summary
  summary
}

# Run main function
main "$@"

