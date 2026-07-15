#!/usr/bin/env bash

#############################################
# OTOBOSuite - OTOBO Management Suite
# Post-Install Verification Module
# Reusable verification functions for
# verify.sh, install.sh, repair.sh
#############################################

# shellcheck source=lib/permissions.sh
source "$(dirname "${BASH_SOURCE[0]}")/permissions.sh"

detect_webserver() {
	if command -v nginx >/dev/null 2>&1 && systemctl is-active --quiet nginx 2>/dev/null; then
		echo "nginx"
	elif command -v apache2 >/dev/null 2>&1; then
		echo "apache"
	else
		echo ""
	fi
}

detect_db_engine() {
	if [[ -f /root/.otobo_db_credentials ]]; then
		source /root/.otobo_db_credentials
		echo "${DB_ENGINE:-mariadb}"
	else
		echo "mariadb"
	fi
}

verify_webserver() {
	local otobo_root="${1:-/opt/otobo}"
	local apache_site="${2:-zzz_otobo}"
	local ws
	ws=$(detect_webserver)

	if [[ "$ws" == "nginx" ]]; then
		verify_nginx
		return
	fi

	info "Verifying Apache..."

	if ! command -v apache2 >/dev/null 2>&1; then
		register_result "Apache" "FAIL" "Apache is not installed"
		return
	fi

	if ! systemctl is-active --quiet apache2 2>/dev/null; then
		register_result "Apache" "FAIL" "Apache is not running"
		return
	fi

	local issues=""
	if ! a2query -s "$apache_site" 2>/dev/null | grep -q "enabled"; then
		issues="${issues}OTBO vhost not enabled; "
	fi
	if ! apache2ctl configtest 2>/dev/null; then
		issues="${issues}config syntax error; "
	fi

	if [[ -n "$issues" ]]; then
		register_result "Apache" "WARN" "Running but issues: ${issues%%; }"
	else
		register_result "Apache" "PASS" "Running, OTOBO site enabled, config valid"
		success "Apache verified."
	fi
}

verify_nginx() {
	info "Verifying nginx..."

	if ! command -v nginx >/dev/null 2>&1; then
		register_result "Nginx" "FAIL" "Nginx is not installed"
		return
	fi

	if ! systemctl is-active --quiet nginx 2>/dev/null; then
		register_result "Nginx" "FAIL" "Nginx is not running"
		return
	fi

	local issues=""
	if [[ ! -f /etc/nginx/sites-available/otobo ]]; then
		issues="${issues}OTBO site config missing; "
	fi
	if ! nginx -t 2>/dev/null; then
		issues="${issues}config syntax error; "
	fi
	if command -v starman >/dev/null 2>&1; then
		if systemctl is-active --quiet otobo-starman 2>/dev/null; then
			register_result "Starman" "PASS" "Starman is running"
		else
			issues="${issues}Starman not running; "
		fi
	fi

	if [[ -n "$issues" ]]; then
		register_result "Nginx" "WARN" "Running but issues: ${issues%%; }"
	else
		register_result "Nginx" "PASS" "Running, OTOBO site configured, config valid"
		success "Nginx verified."
	fi
}

verify_mariadb() {
	local engine
	engine=$(detect_db_engine)

	if [[ "$engine" == "postgresql" ]]; then
		verify_postgresql
		return
	fi

	info "Verifying MariaDB..."

	if ! command -v mariadb >/dev/null 2>&1 && ! command -v mysql >/dev/null 2>&1; then
		register_result "MariaDB" "FAIL" "MariaDB is not installed"
		return
	fi

	if ! systemctl is-active --quiet mariadb 2>/dev/null; then
		register_result "MariaDB" "FAIL" "MariaDB is not running"
		return
	fi

	local issues=""
	if ! mysql -e "USE otobo" 2>/dev/null; then
		issues="${issues}database 'otobo' missing; "
	fi
	if ! mysql -e "SELECT User FROM mysql.user WHERE User='otobo'" 2>/dev/null | grep -q "otobo"; then
		issues="${issues}user 'otobo' missing; "
	fi

	if [[ -n "$issues" ]]; then
		register_result "MariaDB" "WARN" "Running but: ${issues%%; }"
	else
		register_result "MariaDB" "PASS" "Running, DB 'otobo' and user exist"
		success "MariaDB verified."
	fi
}

verify_postgresql() {
	info "Verifying PostgreSQL..."

	if ! command -v psql >/dev/null 2>&1; then
		register_result "PostgreSQL" "FAIL" "PostgreSQL is not installed"
		return
	fi

	if ! systemctl is-active --quiet postgresql 2>/dev/null; then
		register_result "PostgreSQL" "FAIL" "PostgreSQL is not running"
		return
	fi

	local issues=""
	if ! su - postgres -c "psql -lqt 2>/dev/null" | cut -d \| -f 1 | grep -qw "otobo"; then
		issues="${issues}database 'otobo' missing; "
	fi
	if ! su - postgres -c "psql -t -c \"SELECT 1 FROM pg_roles WHERE rolname='otobo'\"" 2>/dev/null | grep -q 1; then
		issues="${issues}user 'otobo' missing; "
	fi

	if [[ -n "$issues" ]]; then
		register_result "PostgreSQL" "WARN" "Running but: ${issues%%; }"
	else
		register_result "PostgreSQL" "PASS" "Running, DB 'otobo' and user exist"
		success "PostgreSQL verified."
	fi
}

verify_perl() {
	local otobo_root="${1:-/opt/otobo}"

	info "Verifying Perl..."

	if ! command -v perl >/dev/null 2>&1; then
		register_result "Perl" "FAIL" "Perl is not installed"
		return
	fi

	local perl_version
	perl_version=$(perl -e 'print $^V')
	register_result "Perl" "PASS" "Installed (${perl_version})"
	success "Perl ${perl_version}."

	local check_script="${otobo_root}/bin/otobo.CheckModules.pl"
	if [[ ! -x "$check_script" ]]; then
		register_result "PerlModules" "INFO" "Module check script not available"
		info "OTBO module checker not found. Skipping module check."
		return
	fi

	if "$check_script" --list >/dev/null 2>&1; then
		register_result "PerlModules" "PASS" "All required Perl modules present"
		success "All required Perl modules installed."
	else
		register_result "PerlModules" "WARN" "Some Perl modules missing"
		warning "Some Perl modules are missing."
	fi
}

verify_otobo() {
	local otobo_root="${1:-/opt/otobo}"
	local config_file="${otobo_root}/Kernel/Config.pm"

	info "Verifying OTOBO installation..."

	if [[ ! -d "$otobo_root" ]]; then
		register_result "OTOBO" "FAIL" "${otobo_root} does not exist"
		return
	fi

	local issues=""
	if [[ ! -f "$config_file" ]]; then
		issues="${issues}Kernel/Config.pm missing; "
	fi
	if [[ -z "$issues" ]]; then
		if ! perl -c "$config_file" >/dev/null 2>&1; then
			issues="${issues}Config.pm has syntax errors; "
		fi
	fi

	if [[ -n "$issues" ]]; then
		register_result "OTOBO" "WARN" "Installed but: ${issues%%; }"
	else
		register_result "OTOBO" "PASS" "${otobo_root} present, Config.pm valid"
		success "OTOBO installation verified."
	fi
}

verify_db_connection() {
	local config_file="${1:-/opt/otobo/Kernel/Config.pm}"

	info "Verifying database connection..."

	if [[ ! -f "$config_file" ]]; then
		register_result "DBConnect" "SKIP" "Config.pm not found"
		info "Config.pm not found. Skipping database verification."
		return
	fi

	local db_host db_user db_pw dsn
	db_host=$(perl -ne 'print $1 if /\$Self->\{DatabaseHost\}\s*=\s*'\''([^'\'']+)/' "$config_file" 2>/dev/null)
	db_user=$(perl -ne 'print $1 if /\$Self->\{DatabaseUser\}\s*=\s*'\''([^'\'']+)/' "$config_file" 2>/dev/null)
	db_pw=$(perl -ne 'print $1 if /\$Self->\{DatabasePw\}\s*=\s*'\''([^'\'']+)/' "$config_file" 2>/dev/null)
	dsn=$(perl -ne 'print $1 if /\$Self->\{DatabaseDSN\}\s*=\s*'\''([^'\'']+)/' "$config_file" 2>/dev/null)

	db_host="${db_host:-localhost}"
	db_user="${db_user:-otobo}"

	if [[ -z "$db_pw" || "$db_pw" == "some-pass" ]]; then
		register_result "DBConnect" "WARN" "Password not set or still default"
		return
	fi

	if echo "$dsn" | grep -q "^DBI:Pg:"; then
		if PGPASSWORD="$db_pw" psql -h "$db_host" -U "$db_user" -d otobo -c "SELECT 1" >/dev/null 2>&1; then
			register_result "DBConnect" "PASS" "Connection successful (PostgreSQL)"
		else
			register_result "DBConnect" "FAIL" "Cannot connect using Config.pm credentials"
		fi
	else
		if mysql -u "$db_user" -p"$db_pw" -h "$db_host" -e "SELECT 1" >/dev/null 2>&1; then
			register_result "DBConnect" "PASS" "Connection successful"
		else
			register_result "DBConnect" "FAIL" "Cannot connect using Config.pm credentials"
		fi
	fi
}

verify_file_permissions() {
	local otobo_root="${1:-/opt/otobo}"
	check_otobo_permissions "$otobo_root"
}

verify_firewall() {
	info "Verifying firewall..."

	if ! command -v ufw >/dev/null 2>&1; then
		register_result "Firewall" "INFO" "UFW is not installed"
		return
	fi

	if ! ufw status | grep -q "Status: active"; then
		register_result "Firewall" "WARN" "UFW is not active"
		return
	fi

	local missing=""
	if ! ufw status | grep -qE '22.*ALLOW'; then
		missing="${missing}SSH(22); "
	fi
	if ! ufw status | grep -qE '80.*ALLOW'; then
		missing="${missing}HTTP(80); "
	fi
	if ! ufw status | grep -qE '443.*ALLOW'; then
		missing="${missing}HTTPS(443); "
	fi

	if [[ -n "$missing" ]]; then
		register_result "Firewall" "WARN" "Missing rules: ${missing%%; }"
	else
		register_result "Firewall" "PASS" "Active and all ports allowed"
		success "Firewall verified."
	fi
}

verify_url() {
	info "Verifying installer URL..."

	if ! command -v curl >/dev/null 2>&1; then
		register_result "InstallerURL" "INFO" "curl not installed"
		return
	fi

	local status_code
	status_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://localhost/otobo/installer.pl 2>/dev/null || echo "000")
	status_code="${status_code:0:3}"

	case "$status_code" in
	200)
		register_result "InstallerURL" "PASS" "HTTP 200 at /otobo/installer.pl"
		success "Installer URL responding (HTTP 200)."
		;;
	302)
		register_result "InstallerURL" "INFO" "HTTP 302 — installer already completed"
		;;
	000)
		register_result "InstallerURL" "FAIL" "Cannot reach web server (connection refused)"
		;;
	*)
		register_result "InstallerURL" "WARN" "Unexpected HTTP ${status_code}"
		;;
	esac
}

verify_ai_service() {
	if systemctl is-enabled open-ticket-ai.service 2>/dev/null | grep -q enabled; then
		if systemctl is-active open-ticket-ai.service &>/dev/null; then
			register_result "AI" "PASS" "Open Ticket AI service is enabled and running"
		else
			register_result "AI" "FAIL" "Open Ticket AI service is enabled but not running"
		fi
	else
		register_result "AI" "INFO" "Open Ticket AI service not installed"
		return
	fi

	if [[ -f /etc/open-ticket-ai/config.yml ]]; then
		register_result "AIConfig" "PASS" "AI config found"
	else
		register_result "AIConfig" "FAIL" "AI config missing at /etc/open-ticket-ai/config.yml"
	fi

	if [[ -d /opt/open-ticket-ai/models ]] && [[ "$(ls -A /opt/open-ticket-ai/models 2>/dev/null)" ]]; then
		register_result "AIModels" "PASS" "AI model(s) present"
	else
		register_result "AIModels" "WARN" "No AI models found"
	fi
}

run_all_verifications() {
	local otobo_root="${1:-/opt/otobo}"

	line
	info "Running post-installation verification..."
	line

	verify_webserver "$otobo_root"
	verify_mariadb
	verify_perl "$otobo_root"
	verify_otobo "$otobo_root"
	verify_db_connection "${otobo_root}/Kernel/Config.pm"
	verify_file_permissions "$otobo_root"
	verify_firewall
	verify_url
	verify_ai_service

	line
}
