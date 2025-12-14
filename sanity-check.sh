#!/usr/bin/env bash

# VPS Sanity Check v1.1.0
# A comprehensive security audit tool for VPS instances
# Author: bglglzd
#
# This tool performs security checks that can be done from inside a VPS.
# It does NOT claim to detect hypervisor-level access by the provider.

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
  
  # Run all security checks
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
  
  # Show final summary
  summary
}

# Run main function
main "$@"
