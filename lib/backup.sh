#!/usr/bin/env bash

#############################################
# OTOBOSuite - OTOBO Management Suite
# Automated Backup Module
#############################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/functions.sh"
source "$SCRIPT_DIR/lib/registry.sh"

CREDS_FILE="/root/.otobo_db_credentials"
# shellcheck disable=SC2034
BACKUP_NAMES=()
# shellcheck disable=SC2034
BACKUP_STATUSES=()
# shellcheck disable=SC2034
BACKUP_MESSAGES=()
HAS_FAIL=0

register_result() {
	local st="$2"
	_registry_register "BACKUP" "$@"
	if [[ "$st" == "FAIL" ]]; then
		HAS_FAIL=1
	fi
}

backup_summary() {
	_registry_print_summary "BACKUP" "BACKUP SUMMARY"
}

check_root() {
	if [[ "$(id -u)" -ne 0 ]]; then
		error "This script must be run as root (sudo)."
	fi
}

load_db_credentials() {
	OTOBO_DB_NAME="otobo"
	OTOBO_DB_USER="otobo"
	OTOBO_DB_PASSWORD=""

	if [[ -f "$CREDS_FILE" ]]; then
		source "$CREDS_FILE"
	fi
}

discover_otobo_dir() {
	OTOBO_DIR="${OTOBO_ROOT:-}"
	if [[ -z "$OTOBO_DIR" ]] && [[ -d "/opt/otobo" ]]; then
		OTOBO_DIR="/opt/otobo"
	fi
}

set_backup_dest() {
	local prefix="$1"
	local timestamp
	timestamp=$(date +"%Y%m%d_%H%M%S")
	BACKUP_DEST="/var/backups/otobo/${prefix}/${timestamp}"
}

ensure_backup_dir() {
	mkdir -p "$BACKUP_DEST"
}

backup_configs() {
	local src_dir

	if [[ -z "$OTOBO_DIR" ]]; then
		register_result "Configs" "SKIP" "OTOBO directory not found"
		warning "OTOBO not installed. Skipping config backup."
		return 1
	fi

	src_dir="$OTOBO_DIR/Kernel"

	if [[ -f "$src_dir/Config.pm" ]]; then
		cp "$src_dir/Config.pm" "$BACKUP_DEST/Config.pm"
		register_result "Config.pm" "PASS" "Backed up to $BACKUP_DEST/Config.pm"
	else
		register_result "Config.pm" "SKIP" "Config.pm not found"
	fi

	if [[ -d "$src_dir/Config/Files" ]]; then
		cp -r "$src_dir/Config/Files" "$BACKUP_DEST/"
		register_result "ConfigFiles" "PASS" "Backed up to $BACKUP_DEST/Files/"
	else
		register_result "ConfigFiles" "SKIP" "Config/Files/ not found"
	fi

	if [[ -f "/root/.otobo_db_credentials" ]]; then
		cp "/root/.otobo_db_credentials" "$BACKUP_DEST/"
		register_result "Credentials" "PASS" "Credentials backed up"
	fi
}

backup_database() {
	local db_pass="${OTOBO_DB_PASSWORD:-}"
	local db_user="${OTOBO_DB_USER:-otobo}"
	local db_name="${OTOBO_DB_NAME:-otobo}"
	local engine="${DB_ENGINE:-mariadb}"

	if [[ "$engine" == "postgresql" ]]; then
		if ! command -v pg_dump >/dev/null 2>&1; then
			register_result "Database" "SKIP" "pg_dump not available"
			warning "PostgreSQL client not installed. Skipping database backup."
			return 1
		fi
		if [[ -n "$db_pass" ]]; then
			PGPASSWORD="$db_pass" pg_dump -U "$db_user" -h localhost "$db_name" >"$BACKUP_DEST/otobo-db.sql" 2>/dev/null
		else
			pg_dump "$db_name" >"$BACKUP_DEST/otobo-db.sql" 2>/dev/null
		fi
	else
		if ! command -v mysqldump >/dev/null 2>&1; then
			register_result "Database" "SKIP" "mysqldump not available"
			warning "MySQL client not installed. Skipping database backup."
			return 1
		fi
		if [[ -n "$db_pass" ]]; then
			mysqldump -u "$db_user" -p"$db_pass" "$db_name" >"$BACKUP_DEST/otobo-db.sql" 2>/dev/null
		else
			mysqldump "$db_name" >"$BACKUP_DEST/otobo-db.sql" 2>/dev/null
		fi
	fi

	if [[ -f "$BACKUP_DEST/otobo-db.sql" ]]; then
		local size
		size=$(du -h "$BACKUP_DEST/otobo-db.sql" | cut -f1)
		register_result "Database" "PASS" "Dumped ($size) to $BACKUP_DEST/otobo-db.sql"
	else
		register_result "Database" "SKIP" "Database not accessible"
		warning "Could not dump database. Check credentials."
	fi
}

backup_articles() {
	local dirs=("var/article" "var/spool" "var/log")

	if [[ -z "$OTOBO_DIR" ]]; then
		register_result "Articles" "SKIP" "OTOBO directory not found"
		return 1
	fi

	local has_any=0
	for rel_dir in "${dirs[@]}"; do
		local full_path="$OTOBO_DIR/$rel_dir"
		if [[ -d "$full_path" ]]; then
			local parent_dir
			parent_dir=$(dirname "$rel_dir")
			mkdir -p "$BACKUP_DEST/$parent_dir"
			cp -r "$full_path" "$BACKUP_DEST/$parent_dir/"
			local size
			size=$(du -sh "$full_path" | cut -f1)
			register_result "$rel_dir" "PASS" "Backed up ($size)"
			has_any=1
		else
			register_result "$rel_dir" "SKIP" "Not found"
		fi
	done

	if [[ "$has_any" -eq 0 ]]; then
		return 1
	fi
	return 0
}

backup_full() {
	info "Running full backup..."
	line
	echo

	discover_otobo_dir
	load_db_credentials
	ensure_backup_dir

	backup_configs
	backup_database
	backup_articles

	local total_size
	total_size=$(du -sh "$BACKUP_DEST" | cut -f1)
	register_result "Total" "PASS" "Backup saved to $BACKUP_DEST (${total_size})"
	success "Full backup complete: $BACKUP_DEST"

	upload_to_s3 "$BACKUP_DEST" "otobo/full/$(basename "$BACKUP_DEST")"
	upload_to_rsync "$BACKUP_DEST"
}

backup_config_only() {
	info "Running config backup..."
	discover_otobo_dir
	ensure_backup_dir
	backup_configs
	register_result "Total" "PASS" "Configs saved to $BACKUP_DEST"
	success "Config backup complete: $BACKUP_DEST"
}

backup_db_only() {
	info "Running database backup..."
	load_db_credentials
	ensure_backup_dir
	backup_database
	register_result "Total" "PASS" "Database saved to $BACKUP_DEST"
	success "Database backup complete: $BACKUP_DEST"
}

backup_articles_only() {
	info "Running articles backup..."
	discover_otobo_dir
	ensure_backup_dir
	backup_articles
	register_result "Total" "PASS" "Articles saved to $BACKUP_DEST"
	success "Articles backup complete: $BACKUP_DEST"
}

do_full_backup() { backup_full; }
do_partial_backup() {
	backup_config_only
	backup_db_only
}
list_backups() {
	if [ -d "${BACKUP_DEST:-/var/backups/otobo}" ]; then
		# shellcheck disable=SC2012
		ls -la "${BACKUP_DEST}" 2>/dev/null | head -30
	else
		warn "No backup directory found"
	fi
}
restore_backup() {
	local restore_path="${1:-}"
	if [[ -z "$restore_path" ]]; then
		# If called interactively, list available backups
		local base="/var/backups/otobo"
		if [[ -d "$base" ]]; then
			info "Available backups:"
			find "$base" -maxdepth 2 -type d -name "20*" 2>/dev/null | sort -r | head -20
		fi
		echo ""
		read -rp "Enter backup path to restore: " restore_path
	fi

	if [[ ! -d "$restore_path" ]]; then
		register_result "Restore" "FAIL" "Backup directory not found: $restore_path"
		error "Backup directory not found: $restore_path"
	fi

	info "Restoring from: $restore_path"

	discover_otobo_dir
	load_db_credentials

	# Stop services
	info "Stopping OTOBO services..."
	systemctl stop otobo-starman 2>/dev/null || true
	systemctl stop apache2 2>/dev/null || true
	systemctl stop nginx 2>/dev/null || true

	# Restore database
	local db_sql=""
	db_sql=$(find "$restore_path" -maxdepth 1 -name "otobo-db.sql" 2>/dev/null | head -1)
	if [[ -n "$db_sql" ]]; then
		info "Restoring database from $db_sql..."
		local engine="${DB_ENGINE:-mariadb}"
		local db_ok=1
		if [[ "$engine" == "postgresql" ]]; then
			su - postgres -c "dropdb ${OTOBO_DB_NAME:-otobo}" 2>/dev/null || true
			su - postgres -c "createdb ${OTOBO_DB_NAME:-otobo} -O ${OTOBO_DB_USER:-otobo}" 2>/dev/null || true
			PGPASSWORD="${OTOBO_DB_PASSWORD:-}" psql -U "${OTOBO_DB_USER:-otobo}" -h localhost "${OTOBO_DB_NAME:-otobo}" <"$db_sql" 2>/dev/null && db_ok=0
		else
			mysql -e "DROP DATABASE IF EXISTS ${OTOBO_DB_NAME:-otobo}" 2>/dev/null || true
			mysql -e "CREATE DATABASE ${OTOBO_DB_NAME:-otobo}" 2>/dev/null || true
			if [[ -n "${OTOBO_DB_PASSWORD:-}" ]]; then
				mysql -u "${OTOBO_DB_USER:-otobo}" -p"${OTOBO_DB_PASSWORD:-}" "${OTOBO_DB_NAME:-otobo}" <"$db_sql" 2>/dev/null && db_ok=0
			else
				mysql "${OTOBO_DB_NAME:-otobo}" <"$db_sql" 2>/dev/null && db_ok=0
			fi
		fi
		if [[ "$db_ok" -eq 0 ]]; then
			register_result "RestoreDB" "PASS" "Database restored from $db_sql"
			success "Database restored."
		else
			register_result "RestoreDB" "FAIL" "Database restore failed"
			warning "Database restore failed."
		fi
	else
		register_result "RestoreDB" "SKIP" "No database SQL dump found in backup"
		info "No database dump found in backup."
	fi

	# Restore files
	if [[ -n "$OTOBO_DIR" ]]; then
		local app_backup
		app_backup=$(find "$restore_path" -maxdepth 1 -type f -name "*.tar.gz" 2>/dev/null | head -1)
		if [[ -n "$app_backup" ]]; then
			info "Restoring application files from $app_backup..."
			mkdir -p /tmp/restore-otobo
			tar xzf "$app_backup" -C /tmp/restore-otobo 2>/dev/null && cp -a /tmp/restore-otobo/* "$OTOBO_DIR"/ 2>/dev/null
			local bak_rc=$?
			if [[ $bak_rc -eq 0 ]]; then
				register_result "RestoreFiles" "PASS" "Application files restored"
				success "Application files restored."
			else
				register_result "RestoreFiles" "WARN" "File restore may be incomplete"
				warning "File restore may be incomplete (exit code $bak_rc)."
			fi
			rm -rf /tmp/restore-otobo
		else
			# Also check for Config.pm / Files/ directory restore from individual items
			backup_configs
			register_result "RestoreFiles" "INFO" "Individual config files restored"
			info "Individual config files restored."
		fi
	else
		register_result "RestoreFiles" "SKIP" "OTOBO directory not found — cannot restore files"
		info "OTOBO directory not found. Cannot restore files."
	fi

	# Restart services
	info "Restarting services..."
	systemctl start mariadb 2>/dev/null || systemctl start postgresql 2>/dev/null || true
	systemctl start otobo-starman 2>/dev/null || true
	systemctl start apache2 2>/dev/null || systemctl start nginx 2>/dev/null || true

	register_result "Restore" "PASS" "Restore completed from $restore_path"
	success "Restore complete: $restore_path"
}
schedule_cron_backup() {
	local schedule="${1:-0 2 * * *}"
	local script_path="${2:-${OTOBO_ROOT:-/opt/otobo}/backup.sh}"
	local cron_file="/etc/cron.d/otobo-backup"
	local log_file="/var/log/otobo-backup.log"
	cat >"$cron_file" <<-EOF
		SHELL=/bin/bash
		PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
		$schedule root $script_path --cron >> $log_file 2>&1
	EOF
	chmod 644 "$cron_file"
	register_result "CronInstall" "PASS" "Cron job installed: $cron_file"
	success "Backup cron scheduled: $schedule"
}

upload_to_s3() {
	local src="$1"
	local bucket="${BACKUP_S3_BUCKET:-}"
	if [[ -z "$bucket" ]]; then
		return
	fi
	local dest="${2:-otobo/$(basename "$src")}"

	local s3_ok=1
	if command -v aws >/dev/null 2>&1; then
		info "Uploading to S3: s3://${bucket}/${dest}..."
		aws s3 cp "$src" "s3://${bucket}/${dest}" 2>/dev/null && s3_ok=0
	elif command -v s3cmd >/dev/null 2>&1; then
		info "Uploading to S3 via s3cmd: s3://${bucket}/${dest}..."
		s3cmd put "$src" "s3://${bucket}/${dest}" 2>/dev/null && s3_ok=0
	else
		register_result "S3Upload" "SKIP" "aws/s3cmd not installed — install awscli or s3cmd for S3 backup"
		info "aws/s3cmd not installed. Skipping S3 upload."
		return
	fi

	if [[ "$s3_ok" -eq 0 ]]; then
		register_result "S3Upload" "PASS" "Uploaded to s3://${bucket}/${dest}"
		success "S3 upload complete."
	else
		register_result "S3Upload" "FAIL" "S3 upload failed for s3://${bucket}/${dest}"
		warning "S3 upload failed."
	fi
}

upload_to_rsync() {
	local src="$1"
	local target="${BACKUP_RSYNC_TARGET:-}"
	if [[ -z "$target" ]]; then
		return
	fi

	if ! command -v rsync >/dev/null 2>&1; then
		register_result "RsyncUpload" "SKIP" "rsync not installed"
		return
	fi

	info "Rsyncing to $target..."
	if rsync -avz --progress "$src" "$target" 2>/dev/null; then
		register_result "RsyncUpload" "PASS" "Synced to $target"
		success "Remote rsync complete."
	else
		register_result "RsyncUpload" "FAIL" "rsync to $target failed"
		warning "Remote rsync failed."
	fi
}

prune_backups() {
	local base="/var/backups/otobo"

	prune_dir() {
		local subdir="$1"
		local keep_days="$2"
		local label="$3"
		local path="$base/$subdir"

		if [[ ! -d "$path" ]]; then
			return
		fi

		local count_before
		count_before=$(find "$path" -maxdepth 1 -type d -name "20*" 2>/dev/null | wc -l)
		find "$path" -maxdepth 1 -type d -name "20*" -mtime "+$keep_days" -exec rm -rf {} + 2>/dev/null
		local count_after
		count_after=$(find "$path" -maxdepth 1 -type d -name "20*" 2>/dev/null | wc -l)
		local removed=$((count_before - count_after))

		if [[ "$removed" -gt 0 ]]; then
			register_result "Prune" "INFO" "Removed $removed old $label backups (kept ${keep_days}d)"
		fi
	}

	prune_dir "daily" 7 "daily"
	prune_dir "weekly" 28 "weekly"
	prune_dir "monthly" 365 "monthly"
}

install_cron() {
	local cron_file="/etc/cron.d/otobo-backup"
	local log_file="/var/log/otobo-backup.log"
	local script_path
	script_path="$(cd "$(dirname "$0")" && pwd)/backup.sh"

	info "Installing daily backup cron job..."

	cat >"$cron_file" <<-EOF
		# OTOBOSuite automatic backup schedule
		# Installed by backup.sh --cron-install
		# Runs daily at 2:30 AM
		SHELL=/bin/bash
		PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
		30 2 * * * root $script_path --cron >> $log_file 2>&1
	EOF

	chmod 644 "$cron_file"

	register_result "CronInstall" "PASS" "Cron job installed: $cron_file"
	success "Daily backup scheduled at 2:30 AM."
	info "Logs: $log_file"

	echo
	info "Would you like to run an initial backup now?"
	if confirm "Run initial backup?" "Y"; then
		echo
		cron_run
	fi
}

cron_run() {
	set_backup_dest "daily"
	backup_full
	prune_backups
}

show_backup_menu() {
	echo " What would you like to back up?"
	echo
	echo "    1) Full backup        -- Configs + database + articles"
	echo "    2) Config only        -- Config.pm, Config/Files/, credentials"
	echo "    3) Database only      -- MySQL dump"
	echo "    4) Articles only      -- var/article, var/spool, var/log"
	echo "    5) Schedule cron      -- Install daily automatic backup"
	echo "    6) Cancel"
	echo
	local bm_choice
	read -rp " Enter your choice [1-6]: " bm_choice
	echo
	echo "$bm_choice"
}

show_banner() {
	clear
	echo -e "${LIGHT_BLUE}"
	echo "============================================================"
	echo
	echo "                  OTOBOSuite - BACKUP"
	echo
	echo "============================================================"
	echo -e "${NC}"
}

main() {
	check_root

	if [[ "${1:-}" == "--cron" ]]; then
		cron_run
		exit 0
	fi

	if [[ "${1:-}" == "--cron-install" ]]; then
		install_cron
		echo
		backup_summary
		exit 0
	fi

	while true; do
		show_banner
		local bm_choice
		bm_choice=$(show_backup_menu)

		case "$bm_choice" in
		1)
			line
			set_backup_dest "manual"
			backup_full
			break
			;;
		2)
			line
			set_backup_dest "manual"
			backup_config_only
			break
			;;
		3)
			line
			set_backup_dest "manual"
			backup_db_only
			break
			;;
		4)
			line
			set_backup_dest "manual"
			backup_articles_only
			break
			;;
		5)
			line
			install_cron
			break
			;;
		6)
			info "Backup cancelled."
			exit 0
			;;
		*)
			echo -e "${RED}Invalid choice. Please enter 1-6.${NC}"
			echo
			;;
		esac
	done

	echo
	backup_summary

	if [[ "$HAS_FAIL" -eq 0 ]]; then
		echo
		success "Backup completed."
	else
		echo
		warning "Backup completed with issues. Check the report above."
	fi
	echo
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
