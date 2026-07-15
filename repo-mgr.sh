#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/pkg.sh
source "$SCRIPT_DIR/lib/pkg.sh"
# shellcheck source=lib/deb.sh
source "$SCRIPT_DIR/lib/deb.sh"
# shellcheck source=lib/apt_repo.sh
source "$SCRIPT_DIR/lib/apt_repo.sh"

usage() {
	cat <<USAGE
Usage: $0 <command> [options]

Commands:
  init                  Initialize a new apt repository
    --repo-dir DIR      Repository directory (default: /var/www/apt-repo)
    --codename DIST     Distribution codename (default: lsb_release -cs)
    --gpg-key KEY       GPG key fingerprint for signing

  build-deb [VERSION]   Build a .deb package from OTOBO tarball
    --output DIR        Output directory (default: current dir)

  add <deb_path>        Add a .deb package to the repository
    --repo-dir DIR      Repository directory
    --codename DIST     Distribution codename

  list                  List packages in the repository
    --repo-dir DIR      Repository directory

  sign                  Sign repository release files
    --repo-dir DIR      Repository directory
    --gpg-key KEY       GPG key fingerprint

  install <repo_url>    Install OTOBO from an apt repository
    --gpg-key-url URL   URL to GPG key
    --version VER       Package version to install

  remove                Remove the OTOBO apt source from this system

  help                  Show this help message
USAGE
	exit 0
}

[ $# -lt 1 ] && usage

COMMAND="$1"
shift

case "$COMMAND" in
init)
	REPO_DIR=""
	CODENAME=""
	GPG_KEY=""
	while [ $# -gt 0 ]; do
		case "$1" in
		--repo-dir)
			shift
			REPO_DIR="$1"
			;;
		--codename)
			shift
			CODENAME="$1"
			;;
		--gpg-key)
			shift
			GPG_KEY="$1"
			;;
		*) die "Unknown option: $1" ;;
		esac
		shift
	done
	apt_repo_init "$REPO_DIR" "$CODENAME" "$GPG_KEY"
	;;

build-deb)
	VERSION="${1:-latest}"
	OUTPUT_DIR="."
	[ $# -gt 1 ] && shift
	while [ $# -gt 0 ]; do
		case "$1" in
		--output)
			shift
			OUTPUT_DIR="$1"
			;;
		*) die "Unknown option: $1" ;;
		esac
		shift
	done
	deb_build_package "$VERSION" "$OUTPUT_DIR"
	;;

add)
	[ $# -lt 1 ] && die "Usage: $0 add <deb_path> [--repo-dir DIR] [--codename DIST]"
	DEB_PATH="$1"
	shift
	REPO_DIR=""
	CODENAME=""
	while [ $# -gt 0 ]; do
		case "$1" in
		--repo-dir)
			shift
			REPO_DIR="$1"
			;;
		--codename)
			shift
			CODENAME="$1"
			;;
		*) die "Unknown option: $1" ;;
		esac
		shift
	done
	apt_repo_add_deb "$REPO_DIR" "$DEB_PATH" "$CODENAME"
	;;

list)
	REPO_DIR=""
	while [ $# -gt 0 ]; do
		case "$1" in
		--repo-dir)
			shift
			REPO_DIR="$1"
			;;
		*) die "Unknown option: $1" ;;
		esac
		shift
	done
	apt_repo_list "$REPO_DIR"
	;;

sign)
	REPO_DIR=""
	GPG_KEY=""
	while [ $# -gt 0 ]; do
		case "$1" in
		--repo-dir)
			shift
			REPO_DIR="$1"
			;;
		--gpg-key)
			shift
			GPG_KEY="$1"
			;;
		*) die "Unknown option: $1" ;;
		esac
		shift
	done
	apt_repo_sign "$REPO_DIR" "$GPG_KEY"
	;;

install)
	[ $# -lt 1 ] && die "Usage: $0 install <repo_url> [--gpg-key-url URL] [--version VER]"
	REPO_URL="$1"
	shift
	GPG_KEY_URL=""
	PKG_VERSION=""
	while [ $# -gt 0 ]; do
		case "$1" in
		--gpg-key-url)
			shift
			GPG_KEY_URL="$1"
			;;
		--version)
			shift
			PKG_VERSION="$1"
			;;
		*) die "Unknown option: $1" ;;
		esac
		shift
	done
	apt_repo_install_otobo "$REPO_URL" "$GPG_KEY_URL" "$PKG_VERSION"
	;;

remove)
	SOURCE="${1:-otobo}"
	apt_repo_remove_source "$SOURCE"
	;;

help | --help | -h) usage ;;
*) die "Unknown command: $COMMAND. Use '$0 help' for usage." ;;
esac
