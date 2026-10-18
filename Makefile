.DEFAULT_GOAL := help

SHELL_FILES := bin/kux test/helpers.bash
PREFIX ?= $(HOME)/.local

.PHONY: help lint fmt test check install uninstall

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'

lint: ## shellcheck + shfmt diff
	shellcheck $(SHELL_FILES)
	shfmt -d $(SHELL_FILES) test/*.bats

fmt: ## Format shell sources in place
	shfmt -w $(SHELL_FILES) test/*.bats

test: ## Run the bats suite
	bats test

check: lint test ## Lint then test

install: ## Symlink bin/kux into $(PREFIX)/bin
	mkdir -p $(PREFIX)/bin
	ln -sf $(CURDIR)/bin/kux $(PREFIX)/bin/kux
	@echo 'add to your rc file:  eval "$$(kux init zsh)"   # or bash'

uninstall: ## Remove the symlink
	rm -f $(PREFIX)/bin/kux
