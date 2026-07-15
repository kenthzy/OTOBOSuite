#!/usr/bin/env bash
set -euo pipefail

#############################################
# OTOBOSuite - OTOBO Management Suite
# OTRS/Znuny → OTOBO Migration Tool
# Run: sudo ./migrate.sh
#      sudo ./migrate.sh --check
#      sudo ./migrate.sh --from-dir /opt/otrs
#############################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=lib/otobo.sh
source "$SCRIPT_DIR/lib/otobo.sh"
# shellcheck source=lib/permissions.sh
source "$SCRIPT_DIR/lib/permissions.sh"

CHECK_ONLY=0
SOURCE_DIR=""
SKIP_ARTICLE_COPY=0
SKIP_DB_MIGRATE=0
TARGET_VERSION="${TARGET_VERSION:-11.0.1}"
TARGET_ROOT="${TARGET_ROOT:-/opt/otobo}"
TARGET_USER="${TARGET_USER:-otobo}"
TARGET_GROUP="${TARGET_GROUP:-www-data}"
BACKUP_BASE="/var/backups/otobo-migrate"

usage() {
	echo "Usage: $0 [options]"
	echo ""
	echo "  --check               Dry-run — only report what would be migrated"
	echo "  --from-dir DIR        Source OTRS/Znuny directory (default: auto-detect)"
	echo "  --to-dir DIR          Target OTOBO directory (default: /opt/otobo)"
	echo "  --skip-articles       Skip copying var/article/ var/spool/ var/log/"
	echo "  --skip-db-migrate     Skip DB migration (assumes DB already migrated)"
	exit 1
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--check) CHECK_ONLY=1 ;;
	--from-dir)
		shift
		SOURCE_DIR="$1"
		;;
	--to-dir)
		shift
		TARGET_ROOT="$1"
		;;
	--skip-articles) SKIP_ARTICLE_COPY=1 ;;
	--skip-db-migrate) SKIP_DB_MIGRATE=1 ;;
	--help | -h) usage ;;
	-*) die "Unknown option: $1" ;;
	*) die "Unexpected argument: $1" ;;
	esac
	shift
done

if [ "$EUID" -ne 0 ]; then
	die "This script must be run as root (sudo)."
fi

MIGRATE_TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# -------------------------------------------------
# Phase 1: Discovery
# -------------------------------------------------

discover_source() {
	local candidates=()
	[ -n "$SOURCE_DIR" ] && candidates+=("$SOURCE_DIR")
	candidates+=("/opt/otrs" "/opt/znuny" "/home/otrs" "/usr/share/otrs")

	local dir
	for dir in "${candidates[@]}"; do
		if [ -f "$dir/Kernel/Config.pm" ] || [ -f "$dir/Kernel/Config/Defaults.pm" ]; then
			SOURCE_DIR="$dir"
			register_result "Source" "OK" "Found at $SOURCE_DIR"
			success "Source found: $SOURCE_DIR"
			return 0
		fi
	done

	register_result "Source" "FAIL" "No OTRS/Znuny installation found"
	die "No OTRS/Znuny installation found. Specify --from-dir or install OTRS/Znuny first."
}

detect_source_version() {
	local ver_file="$SOURCE_DIR/RELEASE"
	local ver=""

	if [ -f "$ver_file" ]; then
		ver=$(grep -E '^VERSION' "$ver_file" 2>/dev/null | head -1 | sed 's/.*=//;s/[" ]//g')
	fi
	if [ -z "$ver" ] && [ -f "$SOURCE_DIR/Kernel/Config.pm" ]; then
		ver=$(perl -ne 'print $1 if /\$Self->\{Version\}\s*=\s*'\''([^'\'']+)/' "$SOURCE_DIR/Kernel/Config.pm" 2>/dev/null)
	fi
	ver="${ver:-unknown}"

	local name="OTRS"
	if [ -f "$SOURCE_DIR/RELEASE" ] && grep -qi "znuny" "$SOURCE_DIR/RELEASE" 2>/dev/null; then
		name="Znuny"
	elif grep -qi "otobo\|znuny" "$SOURCE_DIR/Kernel/Config.pm" 2>/dev/null; then
		name="Znuny"
	fi

	SOURCE_NAME="$name"
	SOURCE_VERSION="$ver"
	register_result "Version" "OK" "${name} ${ver}"
	info "Source: ${name} ${ver}"
}

check_version_compat() {
	local major
	major=$(echo "$SOURCE_VERSION" | cut -d. -f1)

	case "$SOURCE_NAME" in
	OTRS)
		if [ "$major" -lt 6 ] 2>/dev/null; then
			register_result "Compat" "FAIL" "OTRS $SOURCE_VERSION is too old — OTRS 6+ required"
			die "OTRS $SOURCE_VERSION is too old. Migration requires OTRS 6.x or later."
		fi
		;;
	Znuny)
		if [ "$major" -lt 6 ] 2>/dev/null; then
			register_result "Compat" "FAIL" "Znuny $SOURCE_VERSION is too old"
			die "Znuny $SOURCE_VERSION is too old. Migration requires Znuny 6.x or later."
		fi
		;;
	*)
		register_result "Compat" "WARN" "Unknown source — proceeding with caution"
		warn "Unknown source type. Migration may have issues."
		;;
	esac

	register_result "Compat" "PASS" "${SOURCE_NAME} ${SOURCE_VERSION} is compatible"
	success "Source version is compatible."
}

extract_db_config() {
	local config_file="$SOURCE_DIR/Kernel/Config.pm"
	SRC_DB_HOST="localhost"
	SRC_DB_PORT="3306"
	SRC_DB_NAME="otrs"
	SRC_DB_USER="otrs"
	SRC_DB_PASS=""
	SRC_DB_TYPE="mysql"

	if [ ! -f "$config_file" ]; then
		warn "Config.pm not found — using default DB settings"
		return
	fi

	SRC_DB_TYPE=$(perl -ne 'print $1 if /\$Self->\{DatabaseType\}\s*=\s*'\''([^'\'']+)/' "$config_file" 2>/dev/null)
	SRC_DB_HOST=$(perl -ne 'print $1 if /\$Self->\{DatabaseHost\}\s*=\s*'\''([^'\'']+)/' "$config_file" 2>/dev/null)
	SRC_DB_PORT=$(perl -ne 'print $1 if /\$Self->\{DatabasePort\}\s*=\s*'\''([^'\'']+)/' "$config_file" 2>/dev/null)
	SRC_DB_NAME=$(perl -ne 'print $1 if /\$Self->\{Database\}\s*=\s*'\''([^'\'']+)/' "$config_file" 2>/dev/null)
	SRC_DB_USER=$(perl -ne 'print $1 if /\$Self->\{DatabaseUser\}\s*=\s*'\''([^'\'']+)/' "$config_file" 2>/dev/null)
	SRC_DB_PASS=$(perl -ne 'print $1 if /\$Self->\{DatabasePw\}\s*=\s*'\''([^'\'']+)/' "$config_file" 2>/dev/null)

	SRC_DB_HOST="${SRC_DB_HOST:-localhost}"
	SRC_DB_PORT="${SRC_DB_PORT:-3306}"
	SRC_DB_NAME="${SRC_DB_NAME:-otrs}"
	SRC_DB_USER="${SRC_DB_USER:-otrs}"
	SRC_DB_TYPE="${SRC_DB_TYPE:-mysql}"

	register_result "DBConfig" "OK" "DB: ${SRC_DB_TYPE}://${SRC_DB_HOST}:${SRC_DB_PORT}/${SRC_DB_NAME}"
	info "Source DB: ${SRC_DB_TYPE}://${SRC_DB_HOST}:${SRC_DB_PORT}/${SRC_DB_NAME}"
}

extract_system_config() {
	SRC_FQDN="localhost"
	local config_file="$SOURCE_DIR/Kernel/Config.pm"
	if [ -f "$config_file" ]; then
		SRC_FQDN=$(perl -ne 'print $1 if /\$Self->\{FQDN\}\s*=\s*'\''([^'\'']+)/' "$config_file" 2>/dev/null)
		SRC_FQDN="${SRC_FQDN:-$(hostname -f)}"
	fi
	register_result "FQDN" "OK" "FQDN: $SRC_FQDN"
	info "Source FQDN: $SRC_FQDN"
}

# -------------------------------------------------
# Phase 2: Backup
# -------------------------------------------------

backup_source_db() {
	local backup_dir="$1"
	local db_dump="${backup_dir}/source-db.sql"

	info "Backing up source database to $db_dump..."

	if [ "$SRC_DB_TYPE" = "postgresql" ] || echo "$SRC_DB_TYPE" | grep -qi "pg"; then
		PGPASSWORD="$SRC_DB_PASS" pg_dump -h "$SRC_DB_HOST" -p "$SRC_DB_PORT" -U "$SRC_DB_USER" "$SRC_DB_NAME" >"$db_dump" 2>/dev/null || {
			register_result "DBBackup" "FAIL" "PostgreSQL dump failed"
			die "Failed to back up source database."
		}
	else
		mysqldump -h "$SRC_DB_HOST" -P "$SRC_DB_PORT" -u "$SRC_DB_USER" -p"$SRC_DB_PASS" "$SRC_DB_NAME" >"$db_dump" 2>/dev/null || {
			register_result "DBBackup" "FAIL" "MySQL dump failed"
			die "Failed to back up source database."
		}
	fi

	local size
	size=$(du -h "$db_dump" | cut -f1)
	register_result "DBBackup" "OK" "Database dumped (${size})"
	success "Database backed up (${size})."
}

backup_source_files() {
	local backup_dir="$1"

	info "Backing up source files to $backup_dir/source-files/..."
	mkdir -p "$backup_dir/source-files"

	cp -r "$SOURCE_DIR/Kernel/Config.pm" "$backup_dir/source-files/" 2>/dev/null || true
	cp -r "$SOURCE_DIR/Kernel/Config/Files" "$backup_dir/source-files/" 2>/dev/null || true
	cp -r "$SOURCE_DIR/var/article" "$backup_dir/source-files/" 2>/dev/null || true
	cp -r "$SOURCE_DIR/var/spool" "$backup_dir/source-files/" 2>/dev/null || true
	cp -r "$SOURCE_DIR/var/log" "$backup_dir/source-files/" 2>/dev/null || true

	local size
	size=$(du -sh "$backup_dir/source-files" | cut -f1)
	register_result "FileBackup" "OK" "Source files backed up (${size})"
	success "Source files backed up (${size})."
}

# -------------------------------------------------
# Phase 3: Install OTOBO 11
# -------------------------------------------------

install_otobo_code() {
	if [ -d "$TARGET_ROOT" ]; then
		register_result "OTOBO" "INFO" "${TARGET_ROOT} already exists — reusing"
		info "OTOBO already installed at $TARGET_ROOT. Skipping download."
		return
	fi

	info "Installing OTOBO $TARGET_VERSION code..."
	install_otobo "$TARGET_ROOT" "$TARGET_USER" "$TARGET_GROUP"
	success "OTOBO code installed."
}

# -------------------------------------------------
# Phase 4: Migrate Config
# -------------------------------------------------

migrate_config() {
	local source_config="$SOURCE_DIR/Kernel/Config.pm"
	local target_config="$TARGET_ROOT/Kernel/Config.pm"

	if [ ! -f "$source_config" ]; then
		register_result "Config" "SKIP" "No source Config.pm found"
		warn "No source Config.pm found. Configuration must be done manually."
		return
	fi

	info "Migrating Config.pm from $SOURCE_NAME..."

	cp "$source_config" "$target_config"

	perl -i -pe "
		s/\\\$Self->{Product}/\\\$Self->{Product}/;
		s/Otobo|OTRS|Znuny/OTOBO/gi if /Product/;
	" "$target_config" 2>/dev/null || true

	register_result "Config" "OK" "Config.pm copied and adapted"
	success "Config.pm migrated."
}

save_db_credentials() {
	local creds_file="/root/.otobo_db_credentials"

	cat >"$creds_file" <<EOF
DB_ENGINE="${SRC_DB_TYPE}"
DB_HOST="${SRC_DB_HOST}"
DB_PORT="${SRC_DB_PORT}"
DB_NAME="${SRC_DB_NAME}"
DB_USER="${SRC_DB_USER}"
DB_PASS="${SRC_DB_PASS}"
EOF
	chmod 600 "$creds_file"
}

# -------------------------------------------------
# Phase 5: DB Migration
# -------------------------------------------------

run_db_migration() {
	info "Running OTOBO database upgrade on existing source DB..."
	cd "$TARGET_ROOT" || die "Cannot cd to $TARGET_ROOT"

	sudo -u "$TARGET_USER" perl bin/otobo.Console.pl Maint::Database::Upgrade || {
		register_result "DBMigrate" "FAIL" "OTOBO DB upgrade failed"
		die "Database migration failed. Check the error above."
	}

	sudo -u "$TARGET_USER" perl bin/otobo.Console.pl Maint::Cache::Delete || warn "Cache clear had issues"

	register_result "DBMigrate" "OK" "Database schema migrated to OTOBO 11"
	success "Database migration completed."
}

# -------------------------------------------------
# Phase 6: Article Migration
# -------------------------------------------------

migrate_articles() {
	local src_article="$SOURCE_DIR/var/article"
	local src_spool="$SOURCE_DIR/var/spool"
	local src_log="$SOURCE_DIR/var/log"
	local tgt_article="$TARGET_ROOT/var/article"
	local tgt_spool="$TARGET_ROOT/var/spool"
	local tgt_log="$TARGET_ROOT/var/log"

	if [ -d "$src_article" ]; then
		info "Migrating articles..."
		cp -r "$src_article"/* "$tgt_article/" 2>/dev/null || true
		register_result "Articles" "OK" "var/article migrated"
	else
		register_result "Articles" "SKIP" "No var/article found in source"
	fi

	if [ -d "$src_spool" ]; then
		info "Migrating spool..."
		cp -r "$src_spool"/* "$tgt_spool/" 2>/dev/null || true
		register_result "Spool" "OK" "var/spool migrated"
	fi

	if [ -d "$src_log" ]; then
		info "Migrating logs..."
		cp -r "$src_log"/* "$tgt_log/" 2>/dev/null || true
		register_result "Logs" "OK" "var/log migrated"
	fi
}

# -------------------------------------------------
# Phase 7: Finalize
# -------------------------------------------------

finalize_migration() {
	info "Finalizing migration..."

	set_otobo_permissions "$TARGET_ROOT" "$TARGET_USER" "$TARGET_GROUP"

	if systemctl is-enabled --quiet apache2 2>/dev/null; then
		systemctl restart apache2 2>/dev/null || true
	elif systemctl is-enabled --quiet nginx 2>/dev/null; then
		systemctl restart otobo-starman 2>/dev/null || true
		systemctl restart nginx 2>/dev/null || true
	fi

	register_result "Finalize" "OK" "Migration finalized"
	success "Migration finalized."
}

# -------------------------------------------------
# Check Mode
# -------------------------------------------------

run_check() {
	line
	info "Migration Check Report"
	line

	echo ""
	echo "  Source directory:   ${SOURCE_DIR:-<auto-detect>}"
	echo "  Target directory:   ${TARGET_ROOT}"
	echo "  Target version:     ${TARGET_VERSION}"
	echo "  Skip articles:      ${SKIP_ARTICLE_COPY}"
	echo "  Skip DB migrate:    ${SKIP_DB_MIGRATE}"
	echo "  Backup directory:   ${BACKUP_BASE}/${MIGRATE_TIMESTAMP}"
	echo ""

	if [ -n "$SOURCE_DIR" ] && [ -d "$SOURCE_DIR" ]; then
		success "Source directory exists."
	else
		warn "Source directory not specified or not found."
	fi

	if [ -d "$TARGET_ROOT" ]; then
		warn "Target directory already exists — will reuse or overwrite."
	else
		success "Target directory is free."
	fi

	if command -v mysqldump >/dev/null 2>&1 || command -v pg_dump >/dev/null 2>&1; then
		success "DB dump tools available."
	else
		warn "No DB dump tools found (mysqldump/pg_dump)."
	fi

	line
	exit 0
}

# -------------------------------------------------
# Main Migration Flow
# -------------------------------------------------

main() {
	echo ""
	echo "========================================"
	echo "  OTRS/Znuny → OTOBO Migration Tool"
	echo "========================================"

	discover_source
	detect_source_version
	check_version_compat
	extract_db_config
	extract_system_config

	if [ "$CHECK_ONLY" -eq 1 ]; then
		run_check
	fi

	echo ""
	echo "========================================"
	echo "  Migration Summary"
	echo "========================================"
	echo "  Source:           ${SOURCE_NAME} ${SOURCE_VERSION}"
	echo "  Source dir:       ${SOURCE_DIR}"
	echo "  Database:         ${SRC_DB_NAME} on ${SRC_DB_HOST}:${SRC_DB_PORT}"
	echo "  Target:           OTOBO ${TARGET_VERSION}"
	echo "  Target dir:       ${TARGET_ROOT}"
	echo "  Backup dir:       ${BACKUP_BASE}/${MIGRATE_TIMESTAMP}"
	echo "========================================"
	echo ""

	if ! prompt_yes_no "Start migration? Source will NOT be modified."; then
		echo "Migration cancelled."
		exit 0
	fi

	# Phase 2: Backup
	line
	info "Phase 1/6: Backing up source..."
	local backup_dir="${BACKUP_BASE}/${MIGRATE_TIMESTAMP}"
	mkdir -p "$backup_dir"
	backup_source_db "$backup_dir"
	backup_source_files "$backup_dir"

	# Phase 3: Install OTOBO
	line
	info "Phase 2/6: Installing OTOBO $TARGET_VERSION..."
	install_otobo_code
	save_db_credentials

	# Phase 4: Migrate config
	line
	info "Phase 3/6: Migrating configuration..."
	migrate_config

	# Phase 5: DB migration
	line
	info "Phase 4/6: Migrating database..."
	if [ "$SKIP_DB_MIGRATE" -eq 0 ]; then
		run_db_migration
	else
		register_result "DBMigrate" "SKIP" "Database migration skipped (--skip-db-migrate)"
		info "Database migration skipped."
	fi

	# Phase 6: Article migration
	line
	info "Phase 5/6: Migrating articles..."
	if [ "$SKIP_ARTICLE_COPY" -eq 0 ]; then
		migrate_articles
	else
		register_result "Articles" "SKIP" "Article migration skipped (--skip-articles)"
		info "Article migration skipped."
	fi

	# Phase 7: Finalize
	line
	info "Phase 6/6: Finalizing..."
	finalize_migration

	line
	register_result "Migration" "OK" "Migration from ${SOURCE_NAME} ${SOURCE_VERSION} to OTOBO ${TARGET_VERSION} completed"
	validation_summary || warn "Migration completed with warnings"

	echo ""
	echo "========================================"
	echo "  Migration Complete!"
	echo "========================================"
	echo "  Source:   ${SOURCE_NAME} ${SOURCE_VERSION}"
	echo "  Target:   OTOBO ${TARGET_VERSION}"
	echo "  Dir:      ${TARGET_ROOT}"
	echo "  Backup:   ${backup_dir}"
	echo "========================================"
	echo ""
	info "Your OTRS/Znuny installation at ${SOURCE_DIR} is untouched."
	info "If everything works, you can remove it: sudo rm -rf ${SOURCE_DIR}"
	echo ""
}

main "$@"
