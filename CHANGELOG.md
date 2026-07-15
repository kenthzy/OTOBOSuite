# Changelog

## [1.0.0] - 2026-07-13

### Added
- Full OTOBO installation with automated dependency resolution
- Repair tool with comprehensive diagnostics (20+ checks)
- Post-installation verification framework
- Full uninstall with data/config/systemd cleanup
- Upgrade support across OTOBO versions
- SSL management (Let's Encrypt + self-signed)
- Backup/restore with rotation and S3 support
- PostgreSQL support (automatic detection/migration)
- nginx + Starman production deployment
- Config-driven unattended install (`--unattended` / `--config`)
- Open Ticket AI module: Python env, config, model download, systemd service
- AI fine-tuning pipeline: ticket export, data prep, HuggingFace Trainer
- AI dashboard: model stats, prediction stats, HTML generation
- AI model evaluation: accuracy, speed benchmark, comparison
- Security hardening: fail2ban, UFW rate limiting, unattended-upgrades
- Monitoring: Prometheus node_exporter, health check cron
- Multi-distro support: Ubuntu 22.04, 24.04, Debian 12 (via lib/pkg.sh)
- CI/CD: GitHub Actions lint + release workflow
- Vagrant + Ansible provisioning for dev/test
- Menu-driven interface: install, repair, verify, uninstall, upgrade, SSL, backup, security, AI

### Changed
- All functions modularized under lib/*.sh
- Box-drawing borders replaced with clean `====` style
- ShellCheck-clean (zero warnings), shfmt-formatted
