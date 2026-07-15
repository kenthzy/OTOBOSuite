#!/usr/bin/env bash

OTOBOTAR_URL="${OTOBOTAR_URL:-https://github.com/RotherOSS/otobo/archive/refs/tags}"

deb_resolve_latest_tag() {
	curl -s https://api.github.com/repos/RotherOSS/otobo/releases/latest 2>/dev/null |
		grep '"tag_name"' | head -1 | sed 's/.*"tag_name": "\(.*\)",/\1/' || echo "rel-11_0_16"
}

deb_control_file() {
	local version="$1"
	local arch="${2:-amd64}"

	cat <<CONTROL
Package: otobo
Version: ${version}
Section: web
Priority: optional
Architecture: ${arch}
Maintainer: OTOBOSuite <root@localhost>
Depends: libarchive-zip-perl, libtimedate-perl, libdatetime-perl,
 libconvert-binhex-perl, libcgi-psgi-perl, libdbi-perl,
 libdbix-connector-perl, libfile-chmod-perl, liblist-allutils-perl,
 libmoo-perl, libnamespace-autoclean-perl, libnet-dns-perl,
 libnet-smtp-ssl-perl, libpath-class-perl, libsub-exporter-perl,
 libtemplate-perl, libtext-trim-perl, libtry-tiny-perl, libxml-libxml-perl,
 libyaml-libyaml-perl, libdbd-mysql-perl, libapache2-mod-perl2,
 libmail-imapclient-perl, libauthen-sasl-perl, libauthen-ntlm-perl,
 libjson-xs-perl, libtext-csv-xs-perl, libplack-perl,
 libplack-middleware-header-perl, libplack-middleware-reverseproxy-perl,
 libencode-hanextra-perl, libio-socket-ssl-perl, libnet-ldap-perl,
 libcrypt-eksblowfish-perl, libxml-libxslt-perl, libxml-parser-perl,
 libconst-fast-perl
Recommends: mariadb-client | postgresql-client, nginx | apache2,
 mariadb-server | postgresql
Description: OTOBO Help Desk System
 OTOBO is one of the most flexible web-based ticketing systems
 used for Customer Service, Help Desk, IT Service Management.
 This package installs OTOBO to /opt/otobo with the otobo system
 user and recommended Perl dependencies.
CONTROL
}

deb_postinst_script() {
	cat <<'POSTINST'
#!/bin/sh
set -e

case "$1" in
configure)
	if ! getent passwd otobo >/dev/null 2>&1; then
		useradd -r -d /opt/otobo -s /bin/bash otobo 2>/dev/null || true
	fi
	if ! getent group www-data >/dev/null 2>&1; then
		groupadd -r www-data 2>/dev/null || true
	fi
	chown -R otobo:www-data /opt/otobo 2>/dev/null || true
	;;
abort-upgrade|abort-remove|abort-deconfigure)
	exit 0
	;;
*)
	exit 0
	;;
esac
POSTINST
}

deb_prerm_script() {
	cat <<'PRERM'
#!/bin/sh
set -e

case "$1" in
remove|upgrade|deconfigure)
	if command -v systemctl >/dev/null 2>&1; then
		systemctl stop otobo-starman.service 2>/dev/null || true
		systemctl disable otobo-starman.service 2>/dev/null || true
		systemctl stop otobo-daemon.service 2>/dev/null || true
		systemctl disable otobo-daemon.service 2>/dev/null || true
	fi
	;;
failed-upgrade)
	exit 0
	;;
*)
	exit 0
	;;
esac
PRERM
}

deb_extract_version() {
	local tarball="$1"
	local entry
	local raw

	entry=$(tar tzf "$tarball" 2>/dev/null | head -1) || {
		echo "unknown"
		return
	}
	raw="${entry#otobo-}"
	raw="${raw%/}"
	if [[ "$raw" == rel-* ]]; then
		raw="${raw#rel-}"
		raw="${raw//_/.}"
	fi
	echo "${raw:-unknown}"
}

deb_download_tarball() {
	local version="$1"
	local dest_dir="$2"
	local tag
	local filename
	local url

	if [ "$version" = "latest" ]; then
		tag=$(deb_resolve_latest_tag)
	else
		tag="rel-${version//./_}"
	fi

	filename="${tag}.tar.gz"
	url="${OTOBOTAR_URL}/${filename}"
	dest_dir="${dest_dir%/}"

	if [ -f "${dest_dir}/${filename}" ]; then
		echo "${dest_dir}/${filename}"
		return 0
	fi

	wget -q "$url" -O "${dest_dir}/${filename}" || return 1
	echo "${dest_dir}/${filename}"
}

deb_build_package() {
	local version="$1"
	local output_dir="${2:-.}"
	local work_dir
	local extract_dir
	local deb_dir
	local package_path
	local arch
	local control_content

	output_dir="$(cd "$output_dir" 2>/dev/null && pwd || echo "$output_dir")"
	work_dir=$(mktemp -d)
	extract_dir="${work_dir}/extract"
	deb_dir="${work_dir}/deb"
	mkdir -p "$extract_dir" "$deb_dir"

	info "Downloading OTOBO ${version} tarball..."
	local tarball
	tarball=$(deb_download_tarball "$version" "$work_dir") || {
		rm -rf "$work_dir"
		die "Failed to download OTOBO tarball for version ${version}"
	}

	info "Extracting tarball..."
	tar xzf "$tarball" -C "$extract_dir" || {
		rm -rf "$work_dir"
		die "Failed to extract OTOBO tarball"
	}

	local otobo_src
	otobo_src=$(find "$extract_dir" -maxdepth 1 -type d -name 'otobo-*' | head -1)
	if [ -z "$otobo_src" ]; then
		rm -rf "$work_dir"
		die "No otobo-* directory found in extracted tarball"
	fi

	local actual_version
	actual_version=$(deb_extract_version "$tarball")
	[ "$version" = "latest" ] && version="$actual_version"

	info "Building otobo_${version}_amd64.deb..."
	arch="amd64"

	mkdir -p "${deb_dir}/DEBIAN"
	mkdir -p "${deb_dir}/opt"
	cp -a "$otobo_src" "${deb_dir}/opt/otobo"

	control_content=$(deb_control_file "$version" "$arch")
	echo "$control_content" >"${deb_dir}/DEBIAN/control"

	local postinst_content
	postinst_content=$(deb_postinst_script)
	echo "$postinst_content" >"${deb_dir}/DEBIAN/postinst"
	chmod 755 "${deb_dir}/DEBIAN/postinst"

	local prerm_content
	prerm_content=$(deb_prerm_script)
	echo "$prerm_content" >"${deb_dir}/DEBIAN/prerm"
	chmod 755 "${deb_dir}/DEBIAN/prerm"

	package_path="${output_dir}/otobo_${version}-1_${arch}.deb"
	dpkg-deb --build "${deb_dir}" "${package_path}" >/dev/null 2>&1 || {
		rm -rf "$work_dir"
		die "dpkg-deb failed to build package"
	}

	rm -rf "$work_dir"

	if [ -f "$package_path" ]; then
		info "Package built: $package_path"
		register_result "DEB Build" "OK" "otobo_${version}-1_${arch}.deb"
	else
		die "Package file not created at $package_path"
	fi

	echo "$package_path"
}

deb_install() {
	local deb_path="$1"

	if [ ! -f "$deb_path" ]; then
		die "Debian package not found: $deb_path"
	fi

	info "Installing OTOBO from $deb_path..."
	DEBCONF_FRONTEND=noninteractive dpkg -i "$deb_path" 2>/dev/null || {
		DEBCONF_FRONTEND=noninteractive apt-get install -f -y 2>/dev/null || true
		DEBCONF_FRONTEND=noninteractive dpkg -i "$deb_path" 2>/dev/null || {
			die "Failed to install OTOBO deb package"
		}
	}

	register_result "DEB Install" "OK" "OTOBO installed from ${deb_path}"
}

deb_remove() {
	info "Removing OTOBO deb package..."
	DEBCONF_FRONTEND=noninteractive dpkg --purge otobo 2>/dev/null || true
	register_result "DEB Remove" "OK" "OTODO deb package purged"
}
