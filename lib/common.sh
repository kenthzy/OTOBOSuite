#!/usr/bin/env bash

# shellcheck source=lib/registry.sh
source "$(dirname "${BASH_SOURCE[0]}")/registry.sh"

VALIDATION_NAMES=()
VALIDATION_STATUSES=()
VALIDATION_MESSAGES=()

register_result() {
	_registry_register "VALIDATION" "$@"
}

validation_summary() {
	local has_failure=0
	echo ""
	echo "========================================"
	echo "  Validation Summary"
	echo "========================================"
	for i in "${!VALIDATION_NAMES[@]}"; do
		printf "  %-30s [%s] %s\n" "${VALIDATION_NAMES[$i]}" "${VALIDATION_STATUSES[$i]}" "${VALIDATION_MESSAGES[$i]}"
		if [ "${VALIDATION_STATUSES[$i]}" != "OK" ]; then
			has_failure=1
		fi
	done
	echo "========================================"
	return $has_failure
}

LOGFILE="${LOGFILE:-/var/log/otobo-suite-$(date +%Y%m%d-%H%M%S).log}"
touch "$LOGFILE" 2>/dev/null || true

die() {
	echo "[FATAL] $*" | tee -a "$LOGFILE" >&2
	exit 1
}

info() {
	echo "[INFO] $*" | tee -a "$LOGFILE"
}

warn() {
	echo "[WARN] $*" | tee -a "$LOGFILE" >&2
}

success() {
	echo "[ OK ] $*" | tee -a "$LOGFILE"
}

error() {
	echo "[FAIL] $*" | tee -a "$LOGFILE" >&2
	exit 1
}

warning() { warn "$@"; }

line() {
	printf '%*s\n' "${COLUMNS:-60}" '' | tr ' ' '='
}

prompt_yes_no() {
	local question="$1"
	local default="${2:-n}"
	local answer
	while true; do
		if [ "$default" = "y" ]; then
			read -r -p "$question [Y/n] " answer
			answer="${answer:-y}"
		else
			read -r -p "$question [y/N] " answer
			answer="${answer:-n}"
		fi
		case "$answer" in
		y | Y) return 0 ;;
		n | N) return 1 ;;
		*) echo "Please answer y or n." ;;
		esac
	done
}

prompt_with_default() {
	local prompt="$1"
	local default="$2"
	local input
	read -r -p "$prompt [$default] " input
	echo "${input:-$default}"
}
