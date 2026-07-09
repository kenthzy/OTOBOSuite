# Contributing

Thank you for considering contributing to the OTOBO 11 Native Installer.

## Code Style

- All scripts must be written in **Bash** and be compatible with **Bash 3.2+**.
- Use `#!/usr/bin/env bash` as the shebang line.
- Follow the existing modular pattern: one responsibility per lib module.
- Use the helper functions from `lib/functions.sh`:
  - `info()`, `success()`, `warning()`, `error()` for user output
  - `line()` for visual separators
  - `pause()` and `confirm()` for user interaction
- Use `register_result()` from `lib/validation.sh` for recording check outcomes.

## Linting and Formatting

Before submitting a pull request, ensure your code passes:

```bash
make check
```

This runs both:

- **ShellCheck** — static analysis for common Bash bugs and quoting issues
- **shfmt** — auto-formatting (4-space indent, case-indent enabled)

Configuration is in `.shellcheckrc` at the project root.

## How to Submit Changes

1. Fork the repository.
2. Create a feature branch: `git checkout -b feature/my-change`
3. Make your changes.
4. Run `make check` and fix any issues.
5. Commit with a clear, descriptive message.
6. Push and open a pull request.

## Reporting Issues

Open an issue at [github.com/kenthzy/otobo11-native-installer/issues](https://github.com/kenthzy/otobo11-native-installer/issues).

Include:

- A clear description of the problem
- Steps to reproduce
- Expected vs actual behavior
- Ubuntu version and relevant logs if applicable
