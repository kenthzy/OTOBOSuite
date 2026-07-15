#!/usr/bin/env bash

APT_REPO_DIR="${APT_REPO_DIR:-/var/www/apt-repo}"
APT_REPO_CODENAME="${APT_REPO_CODENAME:-$(lsb_release -cs 2>/dev/null || echo 'jammy')}"
APT_REPO_GPG_KEY="${APT_REPO_GPG_KEY:-}"
APT_REPO_SOURCE_NAME="${APT_REPO_SOURCE_NAME:-otobo}"

apt_repo_init() {
	local repo_dir="${1:-$APT_REPO_DIR}"
	local codename="${2:-$APT_REPO_CODENAME}"
	local gpg_key="${3:-$APT_REPO_GPG_KEY}"

	info "Initializing apt repository at $repo_dir..."

	pkg_install reprepro gnupg

	mkdir -p "${repo_dir}/conf"
	mkdir -p "${repo_dir}/incoming"
	mkdir -p "${repo_dir}/db"

	if [ ! -f "${repo_dir}/conf/distributions" ]; then
		cat >"${repo_dir}/conf/distributions" <<DIST
Codename: ${codename}
Architectures: amd64 source
Components: main
Description: OTOBO APT repository
SignWith: ${gpg_key:-default}
DIST
		info "Distributions config written"
	fi

	if [ ! -f "${repo_dir}/conf/options" ]; then
		echo "ask-passphrase" >"${repo_dir}/conf/options"
	fi

	register_result "APT Repo Init" "OK" "Repository initialized at ${repo_dir}"
}

apt_repo_add_deb() {
	local repo_dir="${1:-$APT_REPO_DIR}"
	local deb_path="$2"
	local codename="${3:-$APT_REPO_CODENAME}"

	if [ ! -f "$deb_path" ]; then
		die "Debian package not found: $deb_path"
	fi

	if [ ! -d "${repo_dir}/conf" ]; then
		die "Repository not initialized at $repo_dir. Run apt_repo_init first."
	fi

	info "Adding $(basename "$deb_path") to repository..."
	reprepro --dbdir "${repo_dir}/db" --confdir "${repo_dir}/conf" \
		--basedir "$repo_dir" includedeb "$codename" "$deb_path" 2>/dev/null || {
		die "reprepro failed to add package"
	}

	register_result "APT Repo Add" "OK" "$(basename "$deb_path") added to ${codename}"
}

apt_repo_sign() {
	local repo_dir="${1:-$APT_REPO_DIR}"
	local gpg_key="${2:-$APT_REPO_GPG_KEY}"

	info "Signing apt repository release files..."

	for dist_dir in "${repo_dir}/dists"/*/; do
		[ -d "$dist_dir" ] || continue
		local release_file="${dist_dir}Release"
		if [ -f "$release_file" ]; then
			if [ -n "$gpg_key" ]; then
				cat "$release_file" | gpg --default-key "$gpg_key" -abs -o "${dist_dir}Release.gpg" 2>/dev/null || true
				cat "$release_file" | gpg --default-key "$gpg_key" -abs --clearsign -o "${dist_dir}InRelease" 2>/dev/null || true
			else
				cat "$release_file" | gpg -abs -o "${dist_dir}Release.gpg" 2>/dev/null || true
				cat "$release_file" | gpg -abs --clearsign -o "${dist_dir}InRelease" 2>/dev/null || true
			fi
		fi
	done

	register_result "APT Repo Sign" "OK" "Release files signed"
}

apt_repo_list() {
	local repo_dir="${1:-$APT_REPO_DIR}"

	if [ ! -d "${repo_dir}/db" ]; then
		warn "Repository not initialized at $repo_dir"
		return 1
	fi

	reprepro --dbdir "${repo_dir}/db" --confdir "${repo_dir}/conf" \
		--basedir "$repo_dir" list 2>/dev/null || {
		warn "No packages in repository"
		return 1
	}
}

apt_repo_add_source() {
	local repo_url="$1"
	local gpg_key_url="$2"
	local source_name="${3:-$APT_REPO_SOURCE_NAME}"

	info "Adding apt source $repo_url..."

	if [ -n "$gpg_key_url" ]; then
		wget -qO- "$gpg_key_url" | apt-key add - 2>/dev/null || {
			warn "Failed to add GPG key from $gpg_key_url"
		}
	fi

	if [ ! -f "/etc/apt/sources.list.d/${source_name}.list" ]; then
		echo "deb ${repo_url} ${APT_REPO_CODENAME} main" >"/etc/apt/sources.list.d/${source_name}.list"
		info "Source added: /etc/apt/sources.list.d/${source_name}.list"
	else
		info "Source already exists at /etc/apt/sources.list.d/${source_name}.list"
	fi

	pkg_update
	register_result "APT Source" "OK" "Source ${repo_url} added"
}

apt_repo_remove_source() {
	local source_name="${1:-$APT_REPO_SOURCE_NAME}"

	info "Removing apt source ${source_name}..."
	rm -f "/etc/apt/sources.list.d/${source_name}.list"
	pkg_update
	register_result "APT Source" "OK" "Source ${source_name} removed"
}

apt_repo_install_otobo() {
	local repo_url="$1"
	local gpg_key_url="${2:-}"
	local package_version="${3:-}"

	apt_repo_add_source "$repo_url" "$gpg_key_url"

	info "Installing OTOBO via apt..."
	if [ -n "$package_version" ]; then
		DEBCONF_FRONTEND=noninteractive apt-get install -y "otobo=${package_version}" 2>/dev/null || {
			die "Failed to install otobo=${package_version} via apt"
		}
	else
		DEBCONF_FRONTEND=noninteractive apt-get install -y otobo 2>/dev/null || {
			die "Failed to install otobo via apt"
		}
	fi

	register_result "APT Install" "OK" "OTOBO installed via apt${package_version:+ (${package_version})}"
}

apt_repo_check_version() {
	local repo_url="${1:-}"
	local gpg_key_url="${2:-}"

	if [ -n "$repo_url" ]; then
		apt_repo_add_source "$repo_url" "$gpg_key_url"
	fi

	apt-cache policy otobo 2>/dev/null | grep -E 'Candidate|Installed' || {
		warn "otobo package not found in apt cache"
		return 1
	}
}

apt_repo_upgrade_otobo() {
	local repo_url="${1:-}"
	local gpg_key_url="${2:-}"

	if [ -n "$repo_url" ]; then
		apt_repo_add_source "$repo_url" "$gpg_key_url"
	fi

	info "Upgrading OTOBO via apt..."
	DEBCONF_FRONTEND=noninteractive apt-get install --only-upgrade -y otobo 2>/dev/null || {
		die "Failed to upgrade otobo via apt"
	}

	register_result "APT Upgrade" "OK" "OTOBO upgraded via apt"
}
