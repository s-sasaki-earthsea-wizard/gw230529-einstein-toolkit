# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Syota Sasaki
# Docker targets
# =======================================================
# Build, start and manage the GW230529 BH-NS Einstein Toolkit image,
# which builds the Kruskal release (ET_2025_05) plus the Fuka/Kadath and
# Boost thorns from source on Ubuntu 20.04.

# Load .env when present (SIM_OUTPUT_DIR, USER_UID and friends).
ifneq (,$(wildcard .env))
include .env
export
endif

# Defaults used when .env does not set them.
SIM_OUTPUT_DIR ?= $(HOME)/gw230529-output
SIM_CHECKPOINT_DIR ?= $(HOME)/gw230529-checkpoints

# Detect the host UID/GID (overridable via .env).
USER_UID ?= $(shell id -u)
USER_GID ?= $(shell id -g)
MAKE_PARALLEL ?= 8

COMPOSE := docker compose
BUILD_ARGS := \
	--build-arg USER_UID=$(USER_UID) \
	--build-arg USER_GID=$(USER_GID) \
	--build-arg MAKE_PARALLEL=$(MAKE_PARALLEL)

.PHONY: docker-setup
docker-setup: ## First-time setup (create .env and output directories)
	@test -f .env || (cp .env.example .env && echo "Created .env from .env.example")
	@mkdir -p $(SIM_OUTPUT_DIR) $(SIM_CHECKPOINT_DIR)
	@echo "Output directory    : $(SIM_OUTPUT_DIR)"
	@echo "Checkpoint directory: $(SIM_CHECKPOINT_DIR)"
	@echo "Host UID/GID        : $(USER_UID)/$(USER_GID)"

.PHONY: docker-build
docker-build: docker-setup ## Build the Docker image (60-120 min on first run)
	$(COMPOSE) build $(BUILD_ARGS)

.PHONY: docker-rebuild
docker-rebuild: docker-setup ## Rebuild the Docker image, ignoring the cache
	$(COMPOSE) build --no-cache --pull $(BUILD_ARGS)

.PHONY: docker-up
docker-up: docker-setup ## Start the container in the background (with Jupyter Lab)
	$(COMPOSE) up -d
	@echo ""
	@echo "Get the Jupyter Lab access URL with:"
	@echo "  make docker-token"

.PHONY: docker-down
docker-down: ## Stop and remove the container
	$(COMPOSE) down

.PHONY: docker-restart
docker-restart: docker-down docker-up ## Restart the container

.PHONY: docker-shell
docker-shell: ## Open a bash shell inside the container
	$(COMPOSE) exec et bash

.PHONY: docker-logs
docker-logs: ## Follow the container logs
	$(COMPOSE) logs -f et

.PHONY: docker-token
docker-token: ## Show the Jupyter Lab access URL (with token)
	@$(COMPOSE) exec et jupyter server list 2>/dev/null \
		|| $(COMPOSE) exec et jupyter notebook list 2>/dev/null \
		|| (echo "No Jupyter server found. Check 'make docker-logs'." && exit 1)

.PHONY: docker-ps
docker-ps: ## Show container status
	$(COMPOSE) ps

.PHONY: docker-check
docker-check: ## Verify the Einstein Toolkit installation inside the container
	@echo "== mpirun (system default) =="
	@$(COMPOSE) exec et mpirun --version | head -2 || true
	@echo ""
	@echo "== SimFactory (sim) =="
	@$(COMPOSE) exec et bash -lc 'ls -la /home/etuser/Cactus/simfactory/bin/sim' || echo "  sim not found"
	@echo ""
	@echo "== Cactus executable =="
	@$(COMPOSE) exec et bash -lc 'ls -la /home/etuser/Cactus/exe/cactus_sim' \
		|| echo "  cactus_sim not found (the build may be incomplete)"
	@echo ""
	@echo "== Thorns and arrangements used by GW230529 BH-NS =="
	@$(COMPOSE) exec et bash -lc '\
		check() { \
			if ls -d /home/etuser/Cactus/arrangements/$$1 >/dev/null 2>&1 \
			   || ls -d /home/etuser/Cactus/arrangements/*/$$1 >/dev/null 2>&1; then \
				echo "  OK      $$1"; \
			else \
				echo "  MISSING $$1"; \
			fi; \
		}; \
		check KadathImporter; \
		check KadathThorn; \
		check Boost; \
		check IllinoisGRMHD; \
		check ID_converter_ILGRMHD; \
		check Convert_to_HydroBase; \
		check EOS_Omni; \
		check VolumeIntegrals_GRMHD; \
		check ML_CCZ4; \
		check AHFinderDirect; \
		check QuasiLocalMeasures; \
		check PunctureTracker; \
		check WeylScal4; \
		check Multipole'
	@echo ""
	@echo "== Thorns actually compiled into the binary (CST ThornList) =="
	@$(COMPOSE) exec et bash -lc '\
		compiled() { \
			if grep -qx "$$1" /home/etuser/Cactus/configs/sim/ThornList 2>/dev/null; then \
				echo "  OK      $$1"; \
			else \
				echo "  MISSING $$1"; \
			fi; \
		}; \
		compiled Fuka/KadathImporter; \
		compiled Fuka/KadathThorn; \
		compiled LocalThorns/Boost; \
		compiled GRHayLET/IllinoisGRMHD; \
		compiled WVUThorns/ID_converter_ILGRMHD; \
		compiled WVUThorns/Convert_to_HydroBase; \
		compiled McLachlan/ML_CCZ4' || true
	@echo ""
	@echo "== MPI linkage of the binary (must be MPICH only) =="
	@$(COMPOSE) exec et bash -lc \
		'ldd /home/etuser/Cactus/exe/cactus_sim | grep -q libmpich \
			&& echo "  OK      linked against libmpich" \
			|| echo "  FAIL    not linked against libmpich"; \
		 if ldd /home/etuser/Cactus/exe/cactus_sim | grep -qE "libopen-pal|libopen-rte|libmpi\.so"; then \
			echo "  FAIL    Open MPI is also linked (mixed MPI stack)"; \
		 else \
			echo "  OK      no Open MPI contamination"; \
		 fi'
	@echo ""
	@echo "== MPI communicator test (mpirun.mpich -np 2) =="
	@echo "   A successful MPI_Init is not sufficient evidence: with a mixed"
	@echo "   MPI stack each rank falls back to singleton initialisation and"
	@echo "   runs as an independent job, so assert the process count that"
	@echo "   Carpet actually reports."
	@$(COMPOSE) exec et bash -lc \
		'cd /home/etuser/simulations && rm -rf .mpi_check && mkdir -p .mpi_check && cd .mpi_check && \
		 n=$$(mpirun.mpich -np 2 /home/etuser/Cactus/exe/cactus_sim \
		        /home/etuser/work/par/mpi_check.par 2>&1 \
		      | grep -m1 -oP "Carpet is running on \K[0-9]+"); \
		 if [ "$$n" = "2" ]; then \
			echo "  OK      2 ranks formed a single communicator"; \
		 else \
			echo "  FAIL    Carpet reported $${n:-unknown} processes (expected 2)"; \
		 fi'
