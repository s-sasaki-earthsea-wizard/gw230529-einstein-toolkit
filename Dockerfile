# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 Syota Sasaki
# GW230529 BH-NS Einstein Toolkit build image
# =================================================================
# Derived from the GW150914 project's Dockerfile, with the thornlist
# adapted for the BH-NS gallery example
# (https://einsteintoolkit.org/gallery/bhns/index.html):
#   - enable Fuka/KadathImporter and Fuka/KadathThorn from the Kruskal manifest
#   - append the Boost thorn (github.com/dradice/Boost)
# All other layers (system dependencies, extra libraries) are kept identical
# to GW150914 so that the Docker layer cache is reused as much as possible.
#
# Upstream repository: https://github.com/einsteintoolkit/jupyter-et
# Upstream releases  : https://einsteintoolkit.org/download.html
#
# Expected cost:
#   - first build      : 60-120 min (30-60 min with cache hits)
#   - final image size : 5-8 GB
#   - rebuild (cached) : 10-20 min

FROM ubuntu:20.04

USER root
ENV DEBIAN_FRONTEND=noninteractive

# ============================================================
# Pinned versions (change only when moving to a new release)
# ============================================================
# Einstein Toolkit Kruskal release
ARG ET_RELEASE=ET_2025_05
ENV ET_RELEASE=${ET_RELEASE}
# Python version used upstream
# (Python package versions are managed in requirements.txt)
ENV PYVER=3.8

# ============================================================
# Host UID/GID, so bind-mounted volumes keep matching permissions
# Override at build time with --build-arg USER_UID=$(id -u) USER_GID=$(id -g)
# ============================================================
ARG USER_UID=1000
ARG USER_GID=1000

# ============================================================
# System dependencies (same set as the upstream base.docker)
# MPICH is the MPI implementation, following upstream jupyter-et
# ============================================================
RUN apt-get -qq update && \
    apt-get -qq install --no-install-recommends \
        locales locales-all \
        g++-10 gfortran-10 \
        python python3-pip python3-setuptools \
        libpython${PYVER}-dev libpython${PYVER}-dbg libpython3-dev \
        make cmake git m4 patch subversion mercurial \
        wget curl rsync unzip file pkg-config \
        gnuplot gnuplot-x11 time procps gdb \
        vim nano emacs openssh-client \
        libmpich-dev libhdf5-mpich-dev mpich \
        libscalapack-mpich-dev libscalapack-mpi-dev \
        libhdf5-dev hdf5-tools \
        gsl-bin libgsl-dev libgsl0-dev \
        libopenblas-dev liblapack-dev fftw3-dev \
        libpapi-dev libnuma-dev numactl \
        hwloc libhwloc-dev libudev-dev python3-pyudev libssl-dev \
        libmkl-dev libboost-dev libboost-all-dev \
        ffmpeg imagemagick && \
    apt-get -qq clean && \
    apt-get -qq autoclean && \
    apt-get -qq autoremove && \
    rm -rf /var/lib/apt/lists/*

# Pin g++ / gfortran to version 10, and pin MPI to MPICH.
#
# Pinning MPI MUST happen before every build below. Ubuntu's
# libscalapack-mpi-dev pulls in Open MPI and makes it the default
# update-alternatives target. Leaving that in place means:
#   - CMake FindMPI picks Open MPI for ADIOS2 and openPMD
#   - the Cactus MPI thorn picks /usr/bin/mpic++ (= Open MPI)
#   - while HDF5 comes from apt's libhdf5-mpich-dev (= MPICH)
# so a single binary ends up linked against Open MPI and MPICH at once.
# Launching such a binary under mpirun.mpich makes Open MPI's MPI_Init
# fall back to singleton initialisation: every process runs as its own
# independent 1-rank job (the log shows "Carpet is running on 1 processes"
# once per rank). The ranks then collide on the same output files, which
# also triggers POSIX lock failures on HDF5 checkpoints.
RUN update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 10 && \
    update-alternatives --install /usr/bin/gfortran gfortran /usr/bin/gfortran-10 10 && \
    update-alternatives --set mpi    /usr/bin/mpicc.mpich && \
    update-alternatives --set mpirun /usr/bin/mpirun.mpich && \
    mpicc -show | grep -q mpich

# ============================================================
# Python environment (Jupyter Lab + analysis libraries + tests)
# Dependencies are managed centrally in requirements.txt.
# Upstream also ships jupyterhub; this project is single-user, so it is omitted.
# ============================================================
COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir pip==22.2.2 && \
    pip3 install --no-cache-dir -r /tmp/requirements.txt && \
    rm -rf /root/.cache/pip* /tmp/requirements.txt

# ============================================================
# CarpetX-related extra libraries (same order as the upstream base.docker)
# Each library installs under /usr/local and is picked up automatically
# by the Cactus build below.
# ============================================================

# CMake 3.29.6 (AMReX requires a recent cmake)
RUN mkdir -p /tmp/dist && cd /tmp/dist && \
    wget -q https://github.com/Kitware/CMake/releases/download/v3.29.6/cmake-3.29.6-linux-x86_64.tar.gz && \
    tar xzf cmake-3.29.6-linux-x86_64.tar.gz && \
    rsync -r cmake-3.29.6-linux-x86_64/ /usr/local && \
    cd / && rm -rf /tmp/dist

# ADIOS2 2.10.2 (parallel I/O backend, alongside HDF5).
# The trailing ldd checks assert that ADIOS2 linked against MPICH only;
# a mixed MPI stack must fail the build here rather than at run time.
RUN mkdir -p /tmp/src && cd /tmp/src && \
    wget -q https://github.com/ornladios/ADIOS2/archive/refs/tags/v2.10.2.tar.gz && \
    tar xzf v2.10.2.tar.gz && cd ADIOS2-2.10.2 && \
    cmake -B build \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_TESTING=OFF \
        -DADIOS2_BUILD_EXAMPLES=OFF \
        -DADIOS2_USE_Fortran=OFF \
        -DADIOS2_USE_HDF5=ON \
        -DMPI_C_COMPILER=/usr/bin/mpicc.mpich \
        -DMPI_CXX_COMPILER=/usr/bin/mpicxx.mpich && \
    cmake --build build -j$(nproc) && \
    cmake --install build && \
    ldd /usr/local/lib/libadios2_core_mpi.so | grep -q libmpich && \
    ! ldd /usr/local/lib/libadios2_core_mpi.so | grep -q libopen-pal && \
    cd / && rm -rf /tmp/src

# NSIMD 3.0.1 (SIMD vectorisation, x86_64 SSE2 target)
RUN mkdir -p /tmp/src && cd /tmp/src && \
    wget -q https://github.com/agenium-scale/nsimd/archive/refs/tags/v3.0.1.tar.gz && \
    tar xzf v3.0.1.tar.gz && cd nsimd-3.0.1 && mkdir build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo \
          -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ \
          -Dsimd=SSE2 -DCMAKE_INSTALL_PREFIX=/usr/local .. && \
    make -j$(nproc) && make install && \
    cd / && rm -rf /tmp/src

# openPMD-api 0.15.1 (AMR data layout standard, depends on ADIOS2)
RUN mkdir -p /tmp/src && cd /tmp/src && \
    wget -q https://github.com/openPMD/openPMD-api/archive/refs/tags/0.15.1.tar.gz && \
    tar xzf 0.15.1.tar.gz && cd openPMD-api-0.15.1 && mkdir build && cd build && \
    cmake -DopenPMD_USE_PYTHON=python \
          -DMPI_C_COMPILER=/usr/bin/mpicc.mpich \
          -DMPI_CXX_COMPILER=/usr/bin/mpicxx.mpich .. && \
    make -j$(nproc) && make install && \
    cd / && rm -rf /tmp/src

# ssht 1.5.1 (spin-weighted spherical harmonics)
RUN mkdir -p /tmp/src && cd /tmp/src && \
    wget -q https://github.com/astro-informatics/ssht/archive/v1.5.1.tar.gz && \
    tar xzf v1.5.1.tar.gz && cd ssht-1.5.1 && mkdir build && cd build && \
    cmake .. && make -j$(nproc) && make install && \
    cd / && rm -rf /tmp/src

# Silo 4.11 (visualisation file format)
RUN mkdir -p /tmp/src && cd /tmp/src && \
    wget -q https://github.com/LLNL/Silo/releases/download/v4.11/silo-4.11.tar.gz && \
    tar xzf silo-4.11.tar.gz && cd silo-4.11 && mkdir build && cd build && \
    ../configure \
        --disable-fortran --enable-optimization \
        --with-hdf5=/usr/lib/x86_64-linux-gnu/hdf5/serial/include,/usr/lib/x86_64-linux-gnu/hdf5/serial/lib \
        --prefix=/usr/local && \
    make -j$(nproc) && make install && \
    cd / && rm -rf /tmp/src

# yaml-cpp 0.6.3
RUN mkdir -p /tmp/src && cd /tmp/src && \
    wget -q https://github.com/jbeder/yaml-cpp/archive/yaml-cpp-0.6.3.tar.gz && \
    tar xzf yaml-cpp-0.6.3.tar.gz && cd yaml-cpp-yaml-cpp-0.6.3 && mkdir build && cd build && \
    cmake .. && make -j$(nproc) && make install && \
    cd / && rm -rf /tmp/src

# AMReX 23.05 (adaptive mesh refinement, used by CarpetX)
ARG REAL_PRECISION=real64
RUN mkdir -p /tmp/src && cd /tmp/src && \
    wget -q https://github.com/AMReX-Codes/amrex/archive/23.05.tar.gz && \
    tar xzf 23.05.tar.gz && cd amrex-23.05 && mkdir build && cd build && \
    case "${REAL_PRECISION}" in \
        real32) AMREX_PREC=SINGLE ;; \
        real64) AMREX_PREC=DOUBLE ;; \
        *) echo "Invalid REAL_PRECISION: ${REAL_PRECISION}" >&2 && exit 1 ;; \
    esac && \
    cmake -DAMReX_OMP=ON \
          -DAMReX_PARTICLES=ON \
          -DAMReX_PRECISION="$AMREX_PREC" \
          -DBUILD_SHARED_LIBS=ON \
          -DCMAKE_BUILD_TYPE=RelWithDebInfo \
          -DCMAKE_INSTALL_PREFIX=/usr/local .. && \
    make -j$(nproc) && make install && \
    cd / && rm -rf /tmp/src

# Register the shared objects under /usr/local with the loader cache
RUN ldconfig

# ============================================================
# Non-root user (etuser)
# Matching the host UID/GID keeps bind-mount permissions consistent
# ============================================================
RUN groupadd -g ${USER_GID} etuser && \
    useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash etuser && \
    mkdir -p /home/etuser/work /home/etuser/simulations && \
    chown -R etuser:etuser /home/etuser

USER etuser
# Docker's USER directive only switches the UID; $USER and $HOME stay unset.
# The Cactus Formaline thorn runs git commit internally, and empty values make
# it fail with `fatal: empty ident name (for <@localhost>) not allowed`.
# This mirrors what the upstream build-cactus-tarball.sh does.
ENV USER=etuser HOME=/home/etuser
WORKDIR /home/etuser

# Give git the identity that the Formaline thorn requires.
# It is only used inside the build; no repository is published from it.
RUN git config --global user.name  "Einstein Toolkit Builder" && \
    git config --global user.email "etuser@gw230529-et.local"

# ============================================================
# Fetch and build the Einstein Toolkit (Kruskal)
# ============================================================
# The BH-NS gallery example (see the parfile header) requires
# Fuka/KadathImporter, Fuka/KadathThorn and LocalThorns/Boost in the thornlist.
# The bhns.th shipped by the gallery !INCLUDEs the master manifest, so this
# build fetches the Kruskal manifest directly to stay pinned to a release.
#
# Ordering matters: the manifest's Fuka block already declares
# ``!CHECKOUT = Fuka/KadathImporter Fuka/KadathThorn`` -- the #DISABLED markers
# mean "check out, but keep out of the ThornList". Running the enabling sed
# before GetComponents duplicates the checkout declaration and fails with
# "Duplicate checkouts", so the sed is applied AFTER checkout and BEFORE
# the sim build. The grep and ls calls are build-time assertions that fail
# loudly if a thorn was not enabled or not checked out.
RUN curl -kLO https://raw.githubusercontent.com/gridaphobe/CRL/${ET_RELEASE}/GetComponents && \
    chmod +x GetComponents && \
    curl -kL https://bitbucket.org/einsteintoolkit/manifest/raw/${ET_RELEASE}/einsteintoolkit.th \
         -o einsteintoolkit.th && \
    printf '%s\n' \
        '' \
        '# Boost thorn for the BH-NS gallery example (arXiv:2603.07374)' \
        '!TARGET   = $ARR' \
        '!TYPE     = git' \
        '!URL      = https://github.com/dradice/Boost.git' \
        '!REPO_PATH= ../$2' \
        '!CHECKOUT =' \
        'LocalThorns/Boost' \
        >> einsteintoolkit.th && \
    ./GetComponents --parallel einsteintoolkit.th && \
    sed -i \
        -e 's|^#DISABLED Fuka/KadathImporter$|Fuka/KadathImporter|' \
        -e 's|^#DISABLED Fuka/KadathThorn$|Fuka/KadathThorn|' \
        einsteintoolkit.th && \
    grep -qx 'Fuka/KadathImporter' einsteintoolkit.th && \
    grep -qx 'Fuka/KadathThorn'    einsteintoolkit.th && \
    grep -qx 'LocalThorns/Boost'   einsteintoolkit.th && \
    ls -d Cactus/arrangements/Fuka/KadathImporter Cactus/arrangements/Fuka/KadathThorn \
          Cactus/arrangements/LocalThorns/Boost

# SimFactory setup (detects the environment and writes a machine ini file)
WORKDIR /home/etuser/Cactus
RUN ./simfactory/bin/sim setup-silent

# Build option list (equivalent to the upstream tutorial.cfg)
COPY --chown=etuser:etuser docker/cactus.cfg /home/etuser/Cactus/docker.cfg

# The Cactus build itself, by far the longest step (30-60 min).
# MAKE_PARALLEL is the -j flag; lower it if gcc gets OOM killed.
# The trailing ldd checks assert a single MPI stack (MPICH) in the binary --
# see the update-alternatives comment above for why a mixed stack is fatal.
ENV LD_LIBRARY_PATH=/usr/local/lib:/lib/x86_64-linux-gnu
ARG MAKE_PARALLEL=8
RUN ./simfactory/bin/sim build \
        -j${MAKE_PARALLEL} \
        --thornlist ../einsteintoolkit.th \
        --optionlist docker.cfg && \
    ls -la ./exe/cactus_sim && \
    ldd ./exe/cactus_sim | grep -q libmpich && \
    ! ldd ./exe/cactus_sim | grep -qE 'libopen-pal|libopen-rte|libmpi\.so'

# ============================================================
# Runtime configuration
# ============================================================

# Pin pure MPI. Cactus is built with OpenMP enabled and the reference setup
# runs one thread per rank, but an unset OMP_NUM_THREADS makes every rank
# spawn one thread per visible core: 16 ranks on 16 cores becomes 256 threads
# contending for 16 cores. It does not fail, it just runs about 65 times
# slower -- 0.11 M/hour against the 7.2 M/hour measured in Phase 2 -- and a
# 192 rank cloud instance would compound it to 36,864 threads. Pinning it in
# the image means neither a local invocation nor a launch template has to
# remember. Override it explicitly if a hybrid MPI+OpenMP run is ever wanted.
ENV OMP_NUM_THREADS=1

# The Cactus executable lives outside the default PATH, so any command written
# as a bare `cactus_sim` fails with "command not found".
ENV PATH=/home/etuser/Cactus/exe:${PATH}

WORKDIR /home/etuser/work

EXPOSE 8888

# Default command: run Jupyter Lab in the foreground.
# Get the tokenised access URL with `make docker-token`.
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser"]
