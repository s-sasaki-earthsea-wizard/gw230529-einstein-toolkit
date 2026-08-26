# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Syota Sasaki
# Analysis targets
# =======================================================
# Post-processing of simulation output. Analysis runs inside the
# container, where the Python stack (kuibit, matplotlib, h5py) that the
# image installs from requirements.txt is available; this doubles as the
# rehearsal for in-cloud analysis in Phase 6.

# Reference dataset files needed by the Phase 3 comparison.
REF_DIR := upstream/bhns_20252103
REF_TARBALL := upstream/bhns_20252103.tar.gz

.PHONY: analyze-phase3
analyze-phase3: ## Compare the Phase 3 dx=28 run against the reference dataset
	@test -f $(REF_DIR)/mp_psi4_l2_m2_r500.00.asc -a -f $(REF_DIR)/rho.xy.h5 \
		|| (echo "Reference data missing. Extract it first with:"; \
		    echo "  tar -C upstream -xzf $(REF_TARBALL) \\"; \
		    echo "      bhns_20252103/mp_psi4_l2_m2_r500.00.asc \\"; \
		    echo "      bhns_20252103/rho.xy.h5"; \
		    exit 1)
	$(COMPOSE) exec et python3 scripts/analyze_phase3.py
	@echo ""
	@echo "Figures and summary.md written to reports/phase3/"
