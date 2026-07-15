#!/usr/bin/env bash

#############################################
# OTOBOSuite - OTOBO Management Suite
# Helper Functions
#############################################

LOGFILE="${LOGFILE:-/var/log/otobo-suite-$(date +%Y%m%d-%H%M%S).log}"
touch "$LOGFILE" 2>/dev/null || true

line() {
	printf '%*s\n' "${COLUMNS:-60}" '' | tr ' ' '='
}

info() {
	echo -e "${LIGHT_BLUE}[INFO]${NC} $1"
	echo "[INFO] $1" >>"$LOGFILE"
}

success() {
	echo -e "${GREEN}[ OK ]${NC} $1"
	echo "[ OK ] $1" >>"$LOGFILE"
}

warning() {
	echo -e "${YELLOW}[WARN]${NC} $1"
	echo "[WARN] $1" >>"$LOGFILE"
}

error() {
	echo -e "${RED}[FAIL]${NC} $1"
	echo "[FAIL] $1" >>"$LOGFILE"
	exit 1
}

pause() {
	echo
	read -rp "Press Enter to continue..."
	echo
}

confirm() {
	local message="$1"
	local default="${2:-Y}"
	local prompt
	local answer

	if [[ "$default" == "Y" ]]; then
		prompt="Y/n"
	else
		prompt="N/y"
	fi

	read -rp "${message} [${prompt}] " answer

	if [[ -z "$answer" ]]; then
		answer="$default"
	fi

	case "${answer:0:1}" in
	[Yy]) return 0 ;;
	*) return 1 ;;
	esac
}
