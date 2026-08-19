# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Syota Sasaki
# GW230529 BH-NS Einstein Toolkit Simulation
# ==========================================
# Run `make help` for the list of targets.
# Functionality is split across sub-makefiles under makefiles/.
# Only docker.mk exists as of Phase 1; sim and analyze follow in Phase 2+.

.DEFAULT_GOAL := help

# Include the sub-makefiles.
include makefiles/docker.mk

.PHONY: help
help: ## Show this help
	@echo "GW230529 BH-NS Einstein Toolkit Simulation -- available targets:"
	@echo ""
	@awk 'BEGIN{FS=":.*?## "} \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5); next } \
		/^[a-zA-Z0-9_.-]+:.*?## / { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' \
		$(MAKEFILE_LIST)
	@echo ""
