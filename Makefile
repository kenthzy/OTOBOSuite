SHELL := bash
SCRIPTS := $(shell find . -name '*.sh' -not -path './.git/*')

.PHONY: lint format format-check check

lint:
	@shellcheck $(SCRIPTS)

format:
	@shfmt -w $(SCRIPTS)

format-check:
	@shfmt -d $(SCRIPTS) | grep .; test $$? -eq 1

check: lint format-check
	@echo "All checks passed."
