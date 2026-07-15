# OTOBOSuite

[![Lint](https://github.com/kenthzy/otobo11-native-installer/actions/workflows/lint.yml/badge.svg)](https://github.com/kenthzy/otobo11-native-installer/actions/workflows/lint.yml)
[![Release](https://github.com/kenthzy/otobo11-native-installer/actions/workflows/release.yml/badge.svg)](https://github.com/kenthzy/otobo11-native-installer/actions/workflows/release.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Shell Script](https://img.shields.io/badge/language-Bash-4EAA25.svg)](https://www.shellcheck.net/)

A fully automated, modular Bash management suite for **OTOBO 11** supporting **Ubuntu 22.04**, **Ubuntu 24.04**, and **Debian 12**.

## Features

- **Full OTOBO installation** — Apache or nginx+Starman, MariaDB or PostgreSQL, all Perl dependencies
- **Unattended mode** — `./install.sh --unattended --config /etc/otobo-installer.conf` for zero-input deployment
- **Interactive menu** — `sudo ./otobosuite.sh` provides all operations in one place
- **AI integration** — Install, configure, fine-tune, evaluate, and dashboard Open Ticket AI
- **SSL management** — Let's Encrypt or self-signed certificates
- **Backup & restore** — Full, config-only, DB-only, articles-only with rotation
- **Security hardening** — fail2ban, UFW rate limiting, unattended-upgrades
- **Monitoring** — Prometheus node_exporter, OTOBO health check cron
- **Multi-distro** — Automatic package abstraction for Ubuntu 22.04, 24.04, Debian 12
- **Vagrant + Ansible** — Development VMs with automated provisioning
- **CI/CD** — GitHub Actions lint + release workflow
- **Modular** — 25+ lib modules, each with a single responsibility
- **Code quality** — ShellCheck-clean, shfmt-formatted, enforced via Makefile and CI

## Prerequisites

- Ubuntu 22.04 / 24.04 LTS or Debian 12
- Sudo or root access
- Internet connection
- Minimum 2 GB RAM (recommended), 10 GB disk

## Quick Start

```bash
git clone https://github.com/kenthzy/otobo11-native-installer.git
cd otobo11-native-installer
sudo ./install.sh
```

Follow the on-screen prompts. After completion, open the displayed URL to finish via the OTOBO web installer.

### Unattended Installation

```bash
sudo ./install.sh --unattended --config /etc/otobo-installer.conf
```

Create a config file with required keys (see `configs/config.env.example`):

```
FQDN=otobo.example.com
DB_ENGINE=mariadb
DB_NAME=otobo
DB_USER=otobo
DB_PASS=your_secure_password
ADMIN_USER=admin
ADMIN_PASS=your_admin_password
```

## Menu System

Run the main menu with `sudo ./otobosuite.sh`:

| Option | Description |
|---|---|
| 1) Install | Full OTOBO installation with prompts |
| 2) Repair | Diagnose and fix common issues |
| 3) Verify | Post-installation health check |
| 4) Uninstall | Remove OTOBO, DB, configs, and systemd services |
| 5) Upgrade | Run database migrations and restart services |
| 6) SSL Setup | Let's Encrypt or self-signed certificate |
| 7) Backup | Full, partial, or scheduled backups |
| 8) Security | Firewall, fail2ban, unattended-upgrades |
| 9) AI Management | Fine-tune, dashboard, evaluate, switch models |
| 10) Exit | |

## CLI Scripts

| Script | Description |
|---|---|
| `install.sh` | Full OTOBO installation (interactive or unattended) |
| `otobosuite.sh` | Interactive management menu |
| `verify.sh` | Post-installation health check |
| `repair.sh` | Diagnose and fix common issues (`--check` for read-only) |
| `uninstall.sh` | Full or selective uninstall (`--full` for automatic) |
| `upgrade.sh` | Database migration and service restart |
| `backup.sh` | Command-line backup with cron support (`--cron`, `--cron-install`) |

## What Gets Installed

| Component | Options |
|---|---|
| Web server | Apache 2.4 with mod_perl, or nginx reverse proxy to Starman |
| Database | MariaDB 10.11+ or PostgreSQL |
| Perl | 40+ OTOBO CPAN modules via apt |
| OTOBO | Latest stable from ftp.otobo.org |
| SSL | Let's Encrypt (certbot) or self-signed |
| AI | Open Ticket AI with MiniLM/DistilBERT/BERT/RoBERTa models |
| Firewall | UFW rules for SSH (22), HTTP (80), HTTPS (443) |
| Monitoring | Prometheus node_exporter, health check cron |

## Project Structure

```
otobo11-native-installer/
├── install.sh               # Main installation script
├── otobosuite.sh            # Interactive management menu
├── repair.sh                # Automatic repair (diagnose + fix)
├── verify.sh                # Post-installation verification
├── uninstall.sh             # Uninstall module
├── upgrade.sh               # Upgrade module
├── version.sh               # Version string
├── Makefile                 # lint, format, check, tarball, release
├── Vagrantfile              # Development VMs (Ubuntu 24.04, Debian 12)
├── CHANGELOG.md
├── README.md
├── LICENSE
│
├── lib/
│   ├── ai.sh                # AI integration (Python, uv, packages, config, service)
│   ├── ai_tune.sh           # AI fine-tuning pipeline
│   ├── ai_dashboard.sh      # AI stats dashboard (HTML generation)
│   ├── ai_eval.sh           # AI model evaluation and benchmarking
│   ├── apache.sh            # Apache installation and configuration
│   ├── backup.sh            # Full/partial backup with rotation
│   ├── banner.sh            # ASCII banner display
│   ├── colors.sh            # ANSI color definitions
│   ├── common.sh            # Shared helpers (register_result, prompts, validation_summary)
│   ├── config.sh            # Config file loading and saving
│   ├── firewall.sh          # UFW configuration
│   ├── functions.sh         # Generic helper functions
│   ├── mariadb.sh           # MariaDB installation
│   ├── monitoring.sh        # Prometheus node_exporter, health cron
│   ├── nginx.sh             # nginx reverse proxy configuration
│   ├── otobo.sh             # OTOBO download, DB config, admin user, systemd
│   ├── perl.sh              # Perl dependency installation
│   ├── pkg.sh               # Multi-distro package abstraction (apt)
│   ├── postgresql.sh        # PostgreSQL installation
│   ├── registry.sh          # Unified results registry for all modules
│   ├── security.sh          # fail2ban, UFW rate limiting, unattended-upgrades
│   ├── ssl.sh               # Let's Encrypt and self-signed SSL
│   ├── starman.sh           # Starman PSGI server
│   └── validation.sh        # Pre-flight validation checks
│
├── ansible/
│   ├── playbook.yml         # Ansible provisioning playbook
│   └── inventory.yml        # Static inventory for VMs
│
├── configs/                 # Configuration file templates
│
├── .github/workflows/
│   ├── lint.yml             # ShellCheck + shfmt on every push
│   └── release.yml          # Auto-build tarball on v* tag
│
├── tests/                   # Test scripts (future)
└── logs/                    # Installation logs
```

## Multi-Distribution Support

OTOBO Suite automatically detects the OS and installs the appropriate packages via `lib/pkg.sh`:

- **Ubuntu 22.04** — `apt` with Jammy repositories
- **Ubuntu 24.04** — `apt` with Noble repositories
- **Debian 12** — `apt` with Bookworm repositories

## Development

```bash
make lint           # ShellCheck on all scripts
make format         # Auto-format with shfmt (write)
make format-check   # Format check (diff only, CI-safe)
make check          # lint + format-check in one command
make tarball        # Build OTOBOSuite-<version>.tar.gz
```

All code must pass `make check` before merging.

### Vagrant

```bash
vagrant up          # Provisions Ubuntu 24.04 + Debian 12 VMs
vagrant provision   # Applies Ansible playbook to existing VMs
```

## CI/CD

- **Lint workflow** (`.github/workflows/lint.yml`) — Runs ShellCheck and format-check on every push
- **Release workflow** (`.github/workflows/release.yml`) — On `v*` tag push, builds a tarball and creates a GitHub Release with changelog

## Author

**Kenneth Gonzales** — System Administrator

- GitHub: [kenthzy](https://github.com/kenthzy)
- Project: [OTOBOSuite](https://github.com/kenthzy/otobo11-native-installer)

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
