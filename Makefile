# SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
# SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
# SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
# SPDX-License-Identifier: Apache-2.0

# Makefile — sentin8-auth-ui (app repo, RS §4.5)
#
# Self-contained dev controls for THIS app. Sources the root .env for
# fleet env, guarantees the dev infra, and uses an ABSOLUTE
# SENTIN8_CAPTAIN_BINARY_PREFIX (cwd-independent — RS §4.5.1-1).
SHELL := /bin/bash

APP_PORT := 3200
RELEASE ?=
PROFILED := build start
PROFILE := $(if $(RELEASE),release,debug)

TREE_ROOT := $(abspath ../..)
GROUP := $(abspath ..)
PLATFORM := $(TREE_ROOT)/sentin8
CLI_DIR := $(abspath ../sentin8-cli)
ROOT_ENV := $(TREE_ROOT)/.env
CLI_BIN := $(firstword $(wildcard $(CLI_DIR)/target/$(PROFILE)/sentin8-cli))
ifeq ($(CLI_BIN),)
CLI_BIN := $(shell command -v sentin8-cli 2>/dev/null)
endif
CLI_RUN = $(if $(CLI_BIN),$(CLI_BIN),cargo run $(RELEASE) --quiet --manifest-path $(CLI_DIR)/Cargo.toml --bin sentin8-cli --)

# Absolute binary-prefix chain for the backend-deps boot (RS §4.5.1-1).
PREFIX_DIRS := $(foreach d,$(wildcard $(PLATFORM)/sentin8-*),$(if $(wildcard $(d)/target/$(PROFILE)),$(d)/target/$(PROFILE),))
space := $(empty) $(empty)
PREFIX := $(subst $(space),:,$(strip $(PREFIX_DIRS)))

# Backend deps before the dev server is useful (BFF pattern — tokens never
# reach the client; RS §4.5.5).
APP_PIN := sentin8:acme,sentin8:auth,sentin8:proxy,sentin8:bus,sentin8:sys,sentin8:bff,sentin8:web

# Catalog-path hardening (RS §4.5.1): make every root-.env CATALOG_PATHS
# entry absolute (they are TREE_ROOT-relative in .env.example), then append
# this group's own catalog.json when it is missing.
define catalog_fix
if [ -n "$$SENTIN8_CAPTAIN_CATALOG_PATHS" ]; then \
	ABS=""; oldIFS=$$IFS; IFS=','; \
	for p in $$SENTIN8_CAPTAIN_CATALOG_PATHS; do \
		case "$$p" in /*) ABS="$$ABS$$p," ;; *) ABS="$$ABS$(TREE_ROOT)/$$p," ;; esac; \
	done; IFS=$$oldIFS; \
	export SENTIN8_CAPTAIN_CATALOG_PATHS="$${ABS%,}"; \
fi; \
if [ -f "$(GROUP)/catalog.json" ]; then \
	export SENTIN8_CAPTAIN_CATALOG_PATHS="$${SENTIN8_CAPTAIN_CATALOG_PATHS:+$$SENTIN8_CAPTAIN_CATALOG_PATHS,}$(GROUP)/catalog.json"; \
fi
endef
# Infra guarantee (RS §4.5.1-5): PG 18 + Valkey are HARD deps for most of
# the fleet (RS §5.1). When the platform group's compose stack is down,
# `start` brings it up and waits for accept-connections (bounded).
define infra_check
if [ -z "$$(docker compose -f $(PLATFORM)/docker-compose.yml ps --status=running -q 2>/dev/null)" ]; then \
	echo "→ dev infra down — starting PG 18 + Valkey (RS §2.2.1)"; \
	docker compose -f $(PLATFORM)/docker-compose.yml up -d >/dev/null || exit 1; \
	for i in $$(seq 1 30); do \
		n=$$(docker compose -f $(PLATFORM)/docker-compose.yml ps --status=running -q 2>/dev/null | wc -l); \
		[ "$$n" -ge 2 ] && break; \
		sleep 1; \
	done; \
fi
endef
.PHONY: help build run start test test-integration lint pub-get format format-check check clean \
	$(PROFILED:%=%-release) $(PROFILED:%=%-debug)

help: ## Show this help
	@echo "sentin8-auth-ui (Flutter app)"
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

build: ## Build the web bundle (version-stamped; copies repo .env into build/web/)
	@BUILD_HASH=$$(git log -1 --format=%cd --date=format:%y%m%d-%H%M 2>/dev/null); \
	flutter build web --release --dart-define=SENTIN8_VERSION=$${BUILD_HASH}; \
	if [ -f .env ]; then cp .env build/web/.env; echo "→ copied .env into build/web/"; fi

run: ## Flutter web dev server (port $(APP_PORT))
	@flutter run -d web --web-hostname=0.0.0.0 --web-port=$(APP_PORT)

start: ## Backend deps up (infra + trimmed boot) + Flutter web dev server
	@test -f $(ROOT_ENV) || { echo "ERROR: no root env — create $(ROOT_ENV)" >&2; exit 1; }
	@if [ -z "$(CLI_BIN)" ] && [ ! -f "$(CLI_DIR)/Cargo.toml" ] && ! command -v sentin8-cli >/dev/null 2>&1; then \
		echo "ERROR: sentin8-cli not found — clone the platform group or install it" >&2; exit 1; fi
	@export SENTIN8_CAPTAIN_BINARY_PREFIX="$(PREFIX)"; \
	set -a; . $(ROOT_ENV); set +a; \
	$(call run_dir_fix); \
	$(call infra_check); \
	if $(CLI_RUN) captain services --no-infra >/dev/null 2>&1; then \
		echo "→ captain running — ensuring auth/bff/web are up"; \
		$(CLI_RUN) captain start sentin8:auth sentin8:bff sentin8:web; \
	else \
		echo "→ captain down — trimmed backend boot"; \
		export SENTIN8_SERVICES="$(APP_PIN)"; \
		$(CLI_RUN) captain start; \
	fi; \
	flutter run -d web --web-hostname=0.0.0.0 --web-port=$(APP_PORT)

test: ## Flutter unit/widget tests
	@flutter test

test-integration: ## Integration tests (integration_test/)
	@flutter test integration_test

lint: ## flutter analyze
	@flutter analyze

pub-get: ## flutter pub get
	@flutter pub get

format: ## dart format
	@dart format lib/ test/

format-check: ## dart format --set-exit-if-changed
	@dart format --set-exit-if-changed lib/ test/

check: lint test ## lint + tests

clean: ## flutter clean
	@flutter clean
	@rm -rf build/

# Profile wrappers — make foo-release == RELEASE=--release make foo (§4.5).
$(PROFILED:%=%-release):
	@$(MAKE) --no-print-directory RELEASE=--release $(patsubst %-release,%,$@)

$(PROFILED:%=%-debug):
	@$(MAKE) --no-print-directory RELEASE= $(patsubst %-debug,%,$@)
