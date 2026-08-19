# GW230529 BH-NS Merger — Einstein Toolkit Simulation

Numerical relativity simulation of the black hole–neutron star merger
**GW230529** (BH 3.6 M☉ + NS 1.4 M☉, non-spinning, Γ=2 polytrope), based on the
[Einstein Toolkit BH-NS gallery example](https://einsteintoolkit.org/gallery/bhns/index.html).

This is the successor to the
[GW150914 project](https://github.com/s-sasaki-earthsea-wizard/gw150914-einstein-toolkit),
which reproduced the first binary black hole merger on a single 16-core machine.
This project adds two new ingredients:

- **Matter**: general relativistic hydrodynamics with IllinoisGRMHD + ML_CCZ4,
  starting from a precomputed FUKA/Kadath initial data solution
- **Cloud execution**: local runs are limited to reduced resolution for
  development and validation; the full-resolution production run targets
  **AWS spot instances** (single c7a.48xlarge node), with checkpoints synced
  to S3, figures-only egress, and final results archived to S3 Glacier
  Deep Archive — under a hard budget ceiling of ~300 USD

## Status

**Phase 3 in progress**: a reduced-resolution (dx=28 M, 0.686x) run on 16 local
cores, evolving to t=896 M — far enough past the t≈713 M merger to cover
inspiral, merger and ringdown. It takes about five days.

Completed so far:

- **Phase 1** — Docker image build. The image builds the Einstein Toolkit
  Kruskal release (ET_2025_05) from source with the Fuka/Kadath initial data
  thorns and the Boost thorn enabled, and `make docker-check` verifies the
  installation, including that the binary links a single MPI stack and that
  MPI ranks actually form one communicator.
- **Phase 2** — reduced-resolution smoke test at 16 MPI ranks, with checkpoint
  writing and recovery both demonstrated: 37 GB resident, 43 s/iteration, and
  an apparent-horizon mass matching the 3.6 M☉ black hole to six digits.

The production run stays on a single node. Multi-node MPI is deliberately
deferred to a separate experiment after production, so that a learning exercise
never rides on the run that has to succeed.

See [CLAUDE.md](CLAUDE.md) for the phase plan, technical findings, and the
cloud execution strategy.

## Quick start

```sh
make docker-build   # build the image (60-120 min on first run)
make docker-up      # start the container
make docker-check   # verify the toolkit installation
make help           # list all targets
```

Running a simulation additionally needs the upstream gallery artifacts in
`upstream/` (see the table in [CLAUDE.md](CLAUDE.md)); they are not
redistributed here.

## Upstream attribution

The parameter file, thornlist, and initial data are published by the Einstein
Toolkit gallery (Rahime Matur, Beyhan Karakas) and are **not** redistributed in
this repository; they are fetched from upstream at build time. Any results
derived from them should cite [arXiv:2603.07374](https://arxiv.org/abs/2603.07374)
and the relevant Einstein Toolkit thorn papers.

## License

GPL-2.0-or-later, following the Einstein Toolkit licensing. See [LICENSE](LICENSE).
