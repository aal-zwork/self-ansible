# Targets here only ever run on the machine that invoked `make`. There is
# no ssh dispatch — to apply changes on ADM, `ssh yandex-cloud-adm` first,
# then run `make` there, like on any other machine. See AGENTS.md.
#
# Written for Ubuntu/GNU Make as the target platform (ADM's own OS). On
# macOS the same Makefile picks GNU tools via Homebrew instead of BSD ones
# — see _detect-os below and ../docs/os-toolchain.md.

SHELL := /bin/bash
.DEFAULT_GOAL := help

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  SED  := gsed
  GREP := ggrep
  MAKE_BIN := gmake
else
  SED  := sed
  GREP := grep
  MAKE_BIN := make
endif

GANIEVRF_MAKE_ASK_SKIP ?= no

# Roles escalate per-task via `become: true` only where root is actually
# needed (apt, /usr/local/bin, /etc) — not globally. If sudo on ADM is
# NOPASSWD, this is a no-op; if sudo needs a password, set
# GANIEVRF_ASK_BECOME_PASS=yes to have ansible-playbook prompt for it once
# per run (not stored anywhere). See docs/ssh-and-sudo.md.
GANIEVRF_ASK_BECOME_PASS ?= no
ifeq ($(GANIEVRF_ASK_BECOME_PASS),yes)
  ANSIBLE_BECOME_FLAGS := --ask-become-pass
else
  ANSIBLE_BECOME_FLAGS :=
endif

.PHONY: help _detect-os _confirm ping workspace update upgrade

help:
	@echo "Targets: ping, workspace, update, upgrade"
	@echo "Set GANIEVRF_MAKE_ASK_SKIP=yes to skip confirmation prompts (automation mode)."

# Small, side-effect-free, safe to run as a dependency of every real target.
_detect-os:
	@command -v $(SED) >/dev/null 2>&1 || { echo "Missing $(SED); on macOS: brew install gnu-sed"; exit 1; }
	@command -v $(GREP) >/dev/null 2>&1 || { echo "Missing $(GREP); on macOS: brew install grep"; exit 1; }
	@command -v $(MAKE_BIN) >/dev/null 2>&1 || { echo "Missing $(MAKE_BIN); on macOS: brew install make"; exit 1; }
	@case "$(MAKE_VERSION)" in \
		"") echo "ERROR: not running under GNU Make (MAKE_VERSION is unset)."; \
		    echo "On macOS this Makefile only parses correctly under GNU Make: brew install make, then run 'gmake' instead of 'make'."; \
		    exit 1 ;; \
		*) echo "OK: running under GNU Make $(MAKE_VERSION) (invoked as '$(MAKE)')." ;; \
	esac
ifeq ($(UNAME_S),Darwin)
	@case "$(MAKE)" in \
		*gmake*) ;; \
		*) echo "ERROR: on macOS, invoke this Makefile as 'gmake', not 'make' (Homebrew GNU Make)."; exit 1 ;; \
	esac
endif

# $(call _confirm,<description>) — ask unless GANIEVRF_MAKE_ASK_SKIP=yes.
define _confirm
	@if [ "$(GANIEVRF_MAKE_ASK_SKIP)" != "yes" ]; then \
		read -p "$(1) — apply? [y/N] " ans; \
		case "$$ans" in [yY]*) ;; *) echo "Aborted."; exit 1;; esac; \
	fi
endef

# Read-only connectivity check (ansible ping module) — no state change, no
# confirmation prompt needed.
ping: _detect-os
	ansible all -m ping

workspace: _detect-os
	$(call _confirm,Run full bootstrap (ansible/playbooks/bootstrap.yml))
	ansible-playbook $(ANSIBLE_BECOME_FLAGS) playbooks/bootstrap.yml

update: _detect-os
	$(call _confirm,Pull latest roles/secrets and refresh the session (ansible/playbooks/update.yml))
	ansible-playbook $(ANSIBLE_BECOME_FLAGS) playbooks/update.yml

upgrade: _detect-os
	$(call _confirm,Bump pinned tool versions and reinstall binaries (ansible/playbooks/upgrade.yml))
	ansible-playbook $(ANSIBLE_BECOME_FLAGS) playbooks/upgrade.yml
