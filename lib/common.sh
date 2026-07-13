#!/usr/bin/env bash

VALIDATION_NAMES=()
VALIDATION_STATUSES=()
VALIDATION_MESSAGES=()

register_result() {
	local name="$1"
	local status="$2"
	local message="$3"
	VALIDATION_NAMES+=("$name")
	VALIDATION_STATUSES+=("$status")
	VALIDATION_MESSAGES+=("$message")
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

die() {
	echo "[FATAL] $*" >&2
	exit 1
}

info() {
	echo "[INFO] $*"
}

warn() {
	echo "[WARN] $*" >&2
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
