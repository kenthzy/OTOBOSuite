#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=lib/otobo.sh
source "$SCRIPT_DIR/lib/otobo.sh"

load_config

echo ""
echo "========================================"
echo "  OTOBO 11 Upgrade"
echo "========================================"

OTOBO_ROOT="${OTOBO_ROOT:-/opt/otobo}"
OTOBO_USER="${OTOBO_USER:-otobo}"

if [ ! -d "$OTOBO_ROOT" ]; then
	die "OTOBO not found at $OTOBO_ROOT"
fi

if ! prompt_yes_no "Proceed with upgrade? Backup recommended." "y"; then
	echo "Upgrade cancelled."
	exit 0
fi

# Backup before upgrade
# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/lib/backup.sh"
do_full_backup "$OTOBO_ROOT" "${DB_ENGINE:-mariadb}" "${DB_NAME:-otobo}" "${DB_USER:-otobo}" "${DB_PASS:-}"

info "Running OTOBO upgrade scripts..."
cd "$OTOBO_ROOT" || die "Cannot cd to $OTOBO_ROOT"
sudo -u "$OTOBO_USER" perl bin/otobo.Console.pl Maint::Database::Upgrade || warn "DB upgrade had issues"
sudo -u "$OTOBO_USER" perl bin/otobo.Console.pl Maint::Cache::Delete || warn "Cache clear had issues"

# Restart services
if systemctl is-enabled starman 2>/dev/null | grep -q enabled; then
	systemctl restart starman
	info "Starman restarted"
fi
if systemctl is-enabled apache2 2>/dev/null | grep -q enabled; then
	systemctl reload apache2 2>/dev/null || true
fi
if systemctl is-enabled nginx 2>/dev/null | grep -q enabled; then
	systemctl reload nginx 2>/dev/null || true
fi

# Restart AI service if present
if systemctl is-enabled open-ticket-ai.service 2>/dev/null | grep -q enabled; then
	systemctl restart open-ticket-ai.service
	info "Open Ticket AI service restarted"
fi

register_result "Upgrade" "OK" "OTOBO upgraded successfully"
validation_summary || die "Upgrade completed with errors"

echo "========================================"
echo "  Upgrade Complete"
echo "========================================"
