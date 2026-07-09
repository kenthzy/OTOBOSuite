#!/usr/bin/env bash

#####################################################
# OTOBO 11 Native Installer
# Ubuntu 24.04 LTS — Apache — MariaDB
#####################################################

set -e

source lib/colors.sh
source lib/banner.sh
source lib/functions.sh
source lib/validation.sh

show_banner
pause

run_system_checks

if ! validation_summary; then
    echo
    warning "One or more validation checks failed."
    echo "Review the report above before proceeding."
    echo

    if confirm "Continue with installation anyway?" "N"; then
        echo
        info "Proceeding with installation..."
    else
        error "Installation aborted by user."
    fi
fi

echo
success "System validation complete. Ready for package installation."
echo