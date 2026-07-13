#!/usr/bin/env bash

install_perl_deps() {
	local db_engine="$1"
	info "Installing Perl dependencies..."
	DEBCONF_FRONTEND=noninteractive apt-get install -y perl libcrypt-eksblowfish-perl libjson-perl libxml-libxml-perl libyaml-libyaml-perl libnet-dns-perl libmail-imapclient-perl libauthen-sasl-perl libdatetime-perl libwww-perl || die "Failed to install Perl packages"

	if [ "$db_engine" = "postgresql" ]; then
		DEBCONF_FRONTEND=noninteractive apt-get install -y libdbd-pg-perl || die "Failed to install DBD::Pg"
	else
		DEBCONF_FRONTEND=noninteractive apt-get install -y libdbd-mysql-perl || die "Failed to install DBD::mysql"
	fi
	register_result "Perl Deps" "OK" "Perl dependencies installed for $db_engine"
}
