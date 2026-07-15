#!/usr/bin/env bash

#############################################
# OTOBOSuite - OTOBO Management Suite
# File Permissions Module
#############################################

set_otobo_permissions() {
	local otobo_root="${1:-/opt/otobo}"
	local otobo_user="${2:-otobo}"
	local otobo_group="${3:-www-data}"

	if [[ ! -d "$otobo_root" ]]; then
		warn "OTOBO directory $otobo_root not found — cannot set permissions"
		return 1
	fi

	info "Setting ownership to ${otobo_user}:${otobo_group}..."
	chown -R "${otobo_user}:${otobo_group}" "$otobo_root"

	info "Setting directory permissions to 755..."
	find "$otobo_root" -type d -exec chmod 755 {} \;

	info "Setting file permissions to 644..."
	find "$otobo_root" -type f -exec chmod 644 {} \;

	info "Making bin/ scripts executable..."
	chmod 755 "$otobo_root"/bin/* >/dev/null 2>&1 || true

	if [[ -f "$otobo_root/Kernel/Config.pm" ]]; then
		chmod 640 "$otobo_root/Kernel/Config.pm"
	fi

	if [[ -d "$otobo_root/var/httpd/htdocs" ]]; then
		chmod 755 "$otobo_root/var/httpd/htdocs"
	fi

	register_result "Permissions" "OK" "Ownership ${otobo_user}:${otobo_group}, files 644, dirs 755"
	success "File permissions set."
}

check_otobo_permissions() {
	local otobo_root="${1:-/opt/otobo}"

	if [[ ! -d "$otobo_root" ]]; then
		register_result "Permissions" "INFO" "OTBO not installed — skipping permissions check"
		return
	fi

	local owner
	owner=$(stat -c '%U:%G' "$otobo_root" 2>/dev/null || stat -f '%Su:%Sg' "$otobo_root" 2>/dev/null)

	if [[ "$owner" != "otobo:www-data" ]]; then
		register_result "Permissions" "WARN" "Ownership is ${owner} (expected otobo:www-data)"
	else
		register_result "Permissions" "PASS" "Ownership is otobo:www-data"
	fi
}
