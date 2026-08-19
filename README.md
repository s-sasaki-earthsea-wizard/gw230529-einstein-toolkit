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

Phase 0 (project initialization and upstream asset survey) completed.
See [CLAUDE.md](CLAUDE.md) for the phase plan, technical findings, and the
cloud execution strategy.

## Upstream attribution

The parameter file, thornlist, and initial data are published by the Einstein
Toolkit gallery (Rahime Matur, Beyhan Karakas) and are **not** redistributed in
this repository; they are fetched from upstream at build time. Any results
derived from them should cite [arXiv:2603.07374](https://arxiv.org/abs/2603.07374)
and the relevant Einstein Toolkit thorn papers.

## License

GPL-2.0-or-later, following the Einstein Toolkit licensing. See [LICENSE](LICENSE).
