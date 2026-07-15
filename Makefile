SHELL := bash
SCRIPTS := $(shell find . -name '*.sh' -not -path './.git/*')
VERSION := $(shell bash version.sh)
TARBALL := OTOBOSuite-$(VERSION).tar.gz

.PHONY: lint format format-check check tarball release

lint:
	@shellcheck $(SCRIPTS)

format:
	@shfmt -w $(SCRIPTS)

format-check:
	@shfmt -d $(SCRIPTS) | grep .; test $$? -eq 1

ci: check

check: lint format-check
	@echo "All checks passed."

tarball:
	@echo "Building $(TARBALL)..."
	@git archive --format=tar.gz --prefix=OTOBOSuite-$(VERSION)/ -o "$(TARBALL)" HEAD
	@echo "Created $(TARBALL)"

deb:
	@bash repo-mgr.sh build-deb latest --output .

release: check tarball
	@echo "Release $(VERSION) ready."
