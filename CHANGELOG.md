# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-07-09

### Added

- **Phase 6**: Post-installation verification (`verify.sh`)
  - Apache, MariaDB, Perl, OTOBO, database, permissions, firewall, URL checks
  - Reuses Phase 2 validation registry and summary report
  - CI/CD-compatible exit codes (0 = pass, 1 = fail)

- **Phase 5**: Automatic repair (`repair.sh`, 22 functions)
  - 8 diagnose + 8 repair functions covering all OTOBO components
  - `--check` flag for diagnostics-only mode
  - Issue registry with parallel arrays

- **Phase 4**: OTOBO installation (`lib/otobo.sh`, 9 functions)
  - Download, extract, system user, Apache config, systemd, permissions
  - MariaDB database setup, Kernel/Config.pm generation
  - Completion banner with installer URL

- **Phase 3**: Package installation
  - `lib/apache.sh` — Apache 2.4 + mod_perl + mpm_prefork
  - `lib/mariadb.sh` — MariaDB, secure installation, OTOBO-optimized config
  - `lib/perl.sh` — 40+ Perl modules via apt, build-essential, cpanminus
  - `lib/firewall.sh` — UFW rules, no auto-enable

- **Phase 2**: System validation (`lib/validation.sh`)
  - Validation results registry with parallel arrays
  - 9 individual checks (root, OS, internet, RAM, disk, Apache, MariaDB, Perl, OTOBO)
  - Professional summary report table with PASS/WARN/FAIL/INFO/SKIP

- **Phase 1**: Project framework
  - Repository structure with modular lib directory
  - `lib/colors.sh`, `lib/banner.sh`, `lib/functions.sh`
  - Main installer entry point (`install.sh`)
  - Helper functions (info, success, warning, error, line, pause, confirm)

- **Lint infrastructure**
  - `.shellcheckrc` — project-wide ShellCheck configuration
  - `Makefile` with lint, format, format-check, check targets
  - `.github/workflows/lint.yml` — GitHub Actions CI
  - `shfmt` auto-formatting with 4-space indent (`.sh` files)

### Changed

- `lib/functions.sh` — extracted validation logic to `lib/validation.sh`
- `lib/banner.sh` — added TERM guard for non-interactive terminals
- `VERSION` — updated from empty to `1.0.0`

### Fixed

- All 18 `.sh` files pass ShellCheck (zero warnings)
- All 18 `.sh` files pass `shfmt` (zero diffs)
