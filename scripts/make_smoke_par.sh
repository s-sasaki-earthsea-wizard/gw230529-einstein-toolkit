#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Syota Sasaki
#
# Derive a reduced-resolution parfile from the upstream BH-NS gallery parfile.
#
# The upstream parfile (upstream/bhns_gw230529.par) is an Einstein Toolkit
# gallery artifact and is NOT redistributed from this repository, so the
# derived parfiles are gitignored too. This script is the committed, and
# therefore reproducible, description of how they are produced.
#
# Results derived from the upstream parfile must cite arXiv:2603.07374.
#
# Usage:
#   scripts/make_smoke_par.sh <dx> [itlast] [levels] [checkpoint_id] \
#                             [checkpoint_hours] [out2d_every]
#
# Example:
#   scripts/make_smoke_par.sh 28.0 256 8 yes  # dev resolution, checkpoint the ID
#   scripts/make_smoke_par.sh 67.2 256 5      # fast smoke, 5 refinement levels
#   scripts/make_smoke_par.sh 67.2 256        # cheap smoke, upstream's 8 levels
#   scripts/make_smoke_par.sh 28.0 10240 8 no 6 512   # multi-day Phase 3 run
#
# checkpoint_hours and out2d_every override the upstream cadences and default
# to leaving them alone. Upstream targets a 30 h batch job on COSMA8, so it
# checkpoints every 29 walltime hours; a multi-day unattended run wants
# something far shorter, because a host crash costs a whole checkpoint
# interval. A checkpoint costs about 60 s at dx=28, so 6 h is a 0.3 % tax.
# out2d_every trades disk for comparison points against the reference run,
# whose rho.xy.h5 lands every 1024 iterations at dt=0.06 M, i.e. every 61.4 M.
#
# checkpoint_id=yes adds ``IO::checkpoint_ID = "yes"``, which writes a
# checkpoint straight after the initial data is set up. That matters because
# the FUKA/Kadath import is the dominant start-up cost (see below): paying it
# once and recovering from the checkpoint afterwards turns a ~90 min start-up
# into seconds for every later evolution test. Recovery is already automatic,
# since the upstream parfile sets IOUtil::recover = "autoprobe".
#
# Note that IO::checkpoint_dir is "../CHECKPOINTS", relative to the run
# directory. Give each resolution its own parent directory, otherwise autoprobe
# will happily recover a checkpoint written at a different resolution.
#
# Dropping refinement levels is the most effective way to shorten a smoke run.
# The FUKA/Kadath initial data import dominates start-up cost: it runs once per
# refinement level and gets more expensive as levels get finer, because finer
# levels sit on top of the compact objects where the spectral evaluation costs
# most. Measured at dx=67.2, np=4 (seconds to fill each level):
#     level 0: 12.2   level 1: 42.7   level 2: 224.2   level 3: 232.4
# The per-level cost saturates from level 2 onwards rather than growing without
# bound, so a full 8-level import costs roughly 25 min at this resolution.
# Note that dropping levels changes the physics: the finest level is what
# resolves the neutron star (radius 7.2 M), so reduced-level runs are for
# pipeline validation only, never for physics.
#
# Resolution constraints (coordbase::dx is the only resolution knob, because
# this setup does not use the Llama multipatch grid):
#
#   1. 1344/dx must be an integer, since the coarse grid spans +/-672 M.
#      dx=19.2 (upstream, 70 cells), 28.0 (48), 33.6 (40), 67.2 (20).
#
#   2. The coarse grid must survive domain decomposition. Carpet splits the
#      1344/dx cells across MPI ranks in 3D and needs each chunk to stay
#      wider than Carpet::ghost_size (3). Too few coarse cells for the rank
#      count aborts at startup with
#          "The grid structure is inconsistent.  It is impossible to continue."
#      reported for ml=0 rl=0.
#      Measured: dx=67.2 (20 cells) runs at np=4 but fails at np=16.
#      Pick dx and the rank count together, not independently.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_PAR="${REPO_ROOT}/upstream/bhns_gw230529.par"
ID_DIR_HOST="${REPO_ROOT}/upstream/bhns_gw230529_ID"

# Path to the initial data as seen from inside the container, where the repo
# root is bind-mounted at /home/etuser/work (see docker-compose.yml).
ID_DIR_CONTAINER="/home/etuser/work/upstream/bhns_gw230529_ID"
ID_INFO_BASENAME="BHNS_ECC_RED.gam2.30.0.0.5.q0.388889.0.0.13.info"

DX="${1:-}"
ITLAST="${2:-256}"
LEVELS="${3:-8}"
CHECKPOINT_ID="${4:-no}"
CHECKPOINT_HOURS="${5:-}"
OUT2D_EVERY="${6:-}"

if [[ -z "${DX}" ]]; then
    echo "usage: $0 <dx> [itlast] [levels] [checkpoint_id] [checkpoint_hours] [out2d_every]" >&2
    exit 2
fi

if [[ ! "${LEVELS}" =~ ^[1-8]$ ]]; then
    echo "error: levels must be an integer in 1..8 (upstream uses 8)" >&2
    exit 2
fi

if [[ "${CHECKPOINT_ID}" != "yes" && "${CHECKPOINT_ID}" != "no" ]]; then
    echo "error: checkpoint_id must be 'yes' or 'no'" >&2
    exit 2
fi

if [[ -n "${CHECKPOINT_HOURS}" && ! "${CHECKPOINT_HOURS}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "error: checkpoint_hours must be a non-negative number" >&2
    exit 2
fi

if [[ -n "${OUT2D_EVERY}" && ! "${OUT2D_EVERY}" =~ ^[0-9]+$ ]]; then
    echo "error: out2d_every must be a non-negative integer" >&2
    exit 2
fi

if [[ ! -f "${UPSTREAM_PAR}" ]]; then
    echo "error: upstream parfile not found: ${UPSTREAM_PAR}" >&2
    echo "       fetch it from https://einsteintoolkit.org/gallery/bhns/bhns_gw230529.par" >&2
    exit 1
fi

if [[ ! -f "${ID_DIR_HOST}/${ID_INFO_BASENAME}" ]]; then
    echo "error: initial data not found: ${ID_DIR_HOST}/${ID_INFO_BASENAME}" >&2
    echo "       extract upstream/bhns_gw230529_ID.tar.gz first" >&2
    exit 1
fi

# Warn when 1344/dx is not an integer (constraint 1 above).
if ! python3 -c "
import sys
n = 1344.0 / float('${DX}')
sys.exit(0 if abs(n - round(n)) < 1e-9 else 1)
"; then
    echo "error: 1344/dx = $(python3 -c "print(1344.0/float('${DX}'))") is not an integer" >&2
    echo "       the coarse grid spans +/-672 M and must divide evenly" >&2
    exit 1
fi

CELLS="$(python3 -c "print(int(round(1344.0/float('${DX}'))))")"

OUT_DIR="${REPO_ROOT}/upstream/par-smoke"

# Build the suffix with a plain if rather than `$(cond && echo ...)`: under
# `set -e` the substitution would exit non-zero whenever the condition is
# false, taking the whole script with it.
CKID_SUFFIX=""
if [[ "${CHECKPOINT_ID}" == "yes" ]]; then
    CKID_SUFFIX="_ckid"
fi

# The iteration count is part of the name because runs at one resolution are
# routinely restarted with a longer horizon, and autoprobe recovery keys off
# the checkpoint directory rather than the parfile. Overwriting the parfile
# that produced an existing checkpoint set would erase the record of how that
# checkpoint was made.
OUT_PAR="${OUT_DIR}/bhns_smoke_dx${DX/./p}_l${LEVELS}_it${ITLAST}${CKID_SUFFIX}.par"
mkdir -p "${OUT_DIR}"

# Rewrite four things relative to the upstream parfile:
#   - the Kadath initial data path (upstream ships a "/path/to/" placeholder)
#   - the coarse grid spacing
#   - the termination condition, from physical time to a fixed iteration count
#   - the refinement level count, when asked for fewer than upstream's 8
# Optionally also the checkpoint and 2D output cadences.
SED_ARGS=(
    -e "s|^kadathimporter::filename= \"/path/to/\(.*\)\"|kadathimporter::filename= \"${ID_DIR_CONTAINER}/\1\"|"
    -e "s|^coordbase::dx  *= 19.2|coordbase::dx                            = ${DX}|"
    -e "s|^coordbase::dy  *= 19.2|coordbase::dy                            = ${DX}|"
    -e "s|^coordbase::dz  *= 19.2|coordbase::dz                            = ${DX}|"
    -e "s|^Cactus::terminate\t= \"time\"|Cactus::terminate = \"iteration\"\nCactus::cctk_itlast = ${ITLAST}|"
    -e "s|^Carpet::max_refinement_levels  *= 8$|Carpet::max_refinement_levels            = ${LEVELS}|"
    -e "s|^Carpetregrid2::num_levels_\([123]\)  *= 8$|Carpetregrid2::num_levels_\1              = ${LEVELS}|"
)

if [[ -n "${CHECKPOINT_HOURS}" ]]; then
    SED_ARGS+=(
        -e "s|^IO::checkpoint_every_walltime_hours  *= 29$|IO::checkpoint_every_walltime_hours = ${CHECKPOINT_HOURS}|"
    )
fi

if [[ -n "${OUT2D_EVERY}" ]]; then
    SED_ARGS+=(
        -e "s|^IOHDF5::out2D_every  *= 1024$|IOHDF5::out2D_every                     = ${OUT2D_EVERY}|"
    )
fi

sed "${SED_ARGS[@]}" "${UPSTREAM_PAR}" > "${OUT_PAR}"

# The upstream parfile never mentions IO::checkpoint_ID, so append rather than
# substitute. Cactus rejects a parameter that is set twice, hence the guard.
if [[ "${CHECKPOINT_ID}" == "yes" ]]; then
    grep -qi '^ *IO\(Util\)\?::checkpoint_ID' "${OUT_PAR}" \
        && { echo "error: checkpoint_ID is already set upstream; update this script" >&2; exit 1; }
    printf '\n%s\n%s\n' \
        '# Added by scripts/make_smoke_par.sh: checkpoint right after initial data,' \
        'IO::checkpoint_ID = "yes"' >> "${OUT_PAR}"
fi

# Fail loudly if any substitution silently missed: a placeholder path left in
# place would only surface much later, as a Kadath import error at run time.
grep -q "kadathimporter::filename= \"${ID_DIR_CONTAINER}/" "${OUT_PAR}" \
    || { echo "error: initial data path substitution failed" >&2; exit 1; }
grep -q "^coordbase::dx  *= ${DX}$" "${OUT_PAR}" \
    || { echo "error: dx substitution failed" >&2; exit 1; }
grep -q "^Cactus::cctk_itlast = ${ITLAST}$" "${OUT_PAR}" \
    || { echo "error: termination substitution failed" >&2; exit 1; }
grep -q "^Carpet::max_refinement_levels  *= ${LEVELS}$" "${OUT_PAR}" \
    || { echo "error: refinement level substitution failed" >&2; exit 1; }
[[ "$(grep -c "^Carpetregrid2::num_levels_[123]  *= ${LEVELS}$" "${OUT_PAR}")" == "3" ]] \
    || { echo "error: per-centre refinement level substitution failed" >&2; exit 1; }
if [[ -n "${CHECKPOINT_HOURS}" ]]; then
    grep -q "^IO::checkpoint_every_walltime_hours = ${CHECKPOINT_HOURS}$" "${OUT_PAR}" \
        || { echo "error: checkpoint interval substitution failed" >&2; exit 1; }
fi
if [[ -n "${OUT2D_EVERY}" ]]; then
    grep -q "^IOHDF5::out2D_every  *= ${OUT2D_EVERY}$" "${OUT_PAR}" \
        || { echo "error: 2D output interval substitution failed" >&2; exit 1; }
fi

# dt is set on the finest grid: dtfac * dx / 2**(levels-1).
DT="$(python3 -c "print(0.4 * float('${DX}') / 2**(int('${LEVELS}') - 1))")"

echo "wrote ${OUT_PAR}"
echo "  coarse grid : dx = ${DX} M, ${CELLS} cells across +/-672 M"
echo "  finest grid : dx = $(python3 -c "print(float('${DX}')/2**(int('${LEVELS}')-1))") M (${LEVELS} refinement levels)"
echo "  terminates  : iteration ${ITLAST} (dt = ${DT} M, t_final = $(python3 -c "print(${DT} * int('${ITLAST}'))") M)"
echo "  ID checkpoint: ${CHECKPOINT_ID}"
echo "  checkpoint every: ${CHECKPOINT_HOURS:-29 (upstream)} walltime hours"
echo "  2D output every : ${OUT2D_EVERY:-1024 (upstream)} iterations"
echo ""
echo "Choose the MPI rank count to suit ${CELLS} coarse cells; too many ranks"
echo "abort at startup with an inconsistent grid structure at ml=0 rl=0."
