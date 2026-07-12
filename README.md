# OTOBOSuite

[![Lint](https://github.com/kenthzy/otobo11-native-installer/actions/workflows/lint.yml/badge.svg)](https://github.com/kenthzy/otobo11-native-installer/actions/workflows/lint.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Shell Script](https://img.shields.io/badge/language-Bash-4EAA25.svg)](https://www.shellcheck.net/)

A fully automated, modular Bash installer for **OTOBO 11** on **Ubuntu 24.04 LTS** using **Apache** and **MariaDB**.

## Features

- **Fully automated** — runs end-to-end with minimal user input
- **System validation** — pre-flight checks (OS, RAM, disk, internet, dependencies)
- **Modular architecture** — 12 lib modules, each with a single responsibility
- **Automatic repair** — diagnose and fix common issues with `repair.sh`
- **Post-install verification** — health check with `verify.sh`
- **Code quality enforced** — ShellCheck + shfmt via Makefile and GitHub Actions
- **Idempotent** — safe to re-run; skips existing installations

## Prerequisites

- Ubuntu 24.04 LTS
- Sudo access
- Internet connection
- Minimum 2 GB RAM (recommended), 10 GB disk

## Quick Start

```bash
git clone https://github.com/kenthzy/otobo11-native-installer.git
cd otobo11-native-installer
sudo ./install.sh
```

Follow the on-screen prompts. After installation completes, open the displayed URL in your browser to finish the OTOBO web installer.

## Usage

| Script | Status | Description |
|---|---|---|
| `install.sh` | ✅ | Full automated installation (Phases 1–4) |
| `verify.sh` | ✅ | Post-installation health check |
| `repair.sh` | ✅ | Diagnose and fix common issues |
| `repair.sh --check` | ✅ | Diagnostics only (read-only mode) |
| `uninstall.sh` | 🚧 | Coming soon |

### What gets installed

| Component | Version | Details |
|---|---|---|
| Apache | 2.4 | mod_perl, mpm_prefork, required modules |
| MariaDB | 10.11+ | UTF-8 config, OTOBO-optimized settings |
| Perl | \(\ge\)5.24 | 40+ OTOBO CPAN modules via apt |
| OTOBO | 11.x | Latest stable release from ftp.otobo.org |
| UFW | — | Rules for SSH (22), HTTP (80), HTTPS (443) |

## Project Structure

```
otobo11-native-installer/
├── install.sh              # Main installer entry point
├── repair.sh               # Automatic repair (diagnose + fix)
├── verify.sh               # Post-installation verification
├── uninstall.sh            # Coming soon
├── Makefile                # lint, format, check targets
├── VERSION                 # 1.0.0
├── .shellcheckrc           # ShellCheck project config
│
├── lib/
│   ├── apache.sh           # Apache installation module
│   ├── mariadb.sh          # MariaDB installation module
│   ├── perl.sh             # Perl module installation
│   ├── otobo.sh            # OTOBO download, configure, DB, systemd
│   ├── firewall.sh         # UFW configuration module
│   ├── validation.sh       # Validation checks + summary report
│   ├── functions.sh        # Generic helper functions
│   ├── banner.sh           # ASCII banner display
│   └── colors.sh           # ANSI color definitions
│
├── .github/workflows/
│   └── lint.yml            # GitHub Actions CI for ShellCheck + shfmt
│
├── configs/                # Configuration file templates
├── tests/                  # Test scripts (future)
├── logs/                   # Installation logs
│
├── CHANGELOG.md
├── CONTRIBUTING.md
└── LICENSE
```

## Development

```bash
make lint           # ShellCheck on all scripts
make format         # Auto-format with shfmt (write)
make format-check   # Format check (diff only, CI-safe)
make check          # lint + format-check in one command
```

All code must pass `make check` before merging.

## Roadmap

| Phase | Description | Status |
|---|---|---|
| 1 | Framework (banner, colors, helpers, installer) | ✅ |
| 2 | System validation with registry + summary report | ✅ |
| 3 | Package installation (Apache, MariaDB, Perl, firewall) | ✅ |
| 4 | OTOBO installation (download, configure, DB, systemd) | ✅ |
| 5 | Automatic repair (diagnose and fix common issues) | ✅ |
| 6 | Post-installation verification | ✅ |

## Author

**Kenneth Gonzales** — System Administrator

- GitHub: [kenthzy](https://github.com/kenthzy)
- Project: [OTOTO 11 Native Installer](https://github.com/kenthzy/otobo11-native-installer)

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
