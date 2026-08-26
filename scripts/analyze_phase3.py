#!/usr/bin/env python3
"""Phase 3 analysis dry-run for the GW230529 BH-NS low-resolution run.

Compares the local dx=28.0 run (t = 0..896 M) against the official
reference dataset (bhns_20252103, full resolution dx=19.2):

1. psi4 (l=2, m=2) waveform overlay at r=500 M in retarded time, plus
   the r=100 M extraction, which is the only one that contains the
   merger signal within t <= 896 M.
2. Merger-time estimate from the |psi4| peak (parabolic interpolation),
   cross-checked against the reference peak minus the extraction radius.
3. Orbital tracks: BH puncture location vs NS center of mass, and their
   coordinate separation over time.
4. Matter and horizon diagnostics: maximum rest-mass density and
   apparent-horizon irreducible masses (ah1 = BH, ah2 = post-merger).
5. 2D rest-mass density snapshots in the orbital plane at matched times.

Run inside the container where kuibit is installed:

    docker exec gw230529-et bash -lc \\
        'python3 /home/etuser/work/scripts/analyze_phase3.py'

Figures and a numerical summary land in ``reports/phase3`` (git-ignored).
"""

import argparse
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np

# Okabe-Ito derived palette, validated CVD-safe (dataviz six checks).
C_RUN = "#0072B2"
C_REF = "#D55E00"
C_AUX = "#009E73"

# Column indices (0-based) in the CarpetIOASCII 0D files.
PT_COL_TIME = 8   # column 9: time
PT_COL_X0 = 22    # column 23: pt_loc_x[0] (BH puncture)
PT_COL_Y0 = 32    # column 33: pt_loc_y[0]

# VolumeIntegrals_GRMHD columns: 1 time, 3-5 unnormalized CoM integrals
# of the NS tracking sphere, 6 rest mass inside that sphere.
VI_COL_TIME = 0
VI_COL_COMX = 2
VI_COL_COMY = 3
VI_COL_MASS = 5

plt.rcParams.update({
    "figure.facecolor": "white",
    "savefig.facecolor": "white",
    "savefig.dpi": 150,
    "axes.grid": True,
    "grid.alpha": 0.3,
    "axes.axisbelow": True,
    "lines.linewidth": 1.8,
    "font.size": 10,
})


def load_ascii(path):
    """Load a whitespace ASCII table, dropping duplicate time rows.

    Checkpoint recovery replays the recovered iteration, so runs that
    were restarted contain duplicated output rows. Rows are deduplicated
    on the first column value while preserving order.

    Args:
        path: Path to the ASCII file (comment lines start with ``#``).

    Returns:
        2D numpy array with unique, sorted first-column values.
    """
    data = np.atleast_2d(np.loadtxt(path))
    _, idx = np.unique(data[:, 0], return_index=True)
    return data[np.sort(idx)]


def peak_time(t, amp):
    """Estimate the time of the amplitude peak.

    Uses parabolic interpolation through the maximum sample and its two
    neighbours, which is meaningful here because the multipole output
    cadence (22.4 M for the run, 15.4 M for the reference) is coarse.

    Args:
        t: 1D array of times.
        amp: 1D array of amplitudes, same length as ``t``.

    Returns:
        Tuple ``(t_peak, at_boundary)`` where ``at_boundary`` is True if
        the maximum is the last sample (peak not contained in the data).
    """
    i = int(np.argmax(amp))
    if i == 0 or i == len(t) - 1:
        return float(t[i]), True
    y0, y1, y2 = amp[i - 1: i + 2]
    denom = y0 - 2.0 * y1 + y2
    shift = 0.0 if denom == 0 else 0.5 * (y0 - y2) / denom
    return float(t[i] + shift * (t[i + 1] - t[i])), False


def load_psi4(path, radius):
    """Load a Multipole psi4 file and scale by the extraction radius.

    Args:
        path: Path to ``mp_psi4_l2_m2_r*.asc`` (columns: t, Re, Im).
        radius: Extraction radius in M, used for the r*psi4 scaling.

    Returns:
        Tuple ``(u, re, im, amp)`` with retarded time ``u = t - radius``
        and radius-scaled real part, imaginary part, and amplitude.
    """
    data = load_ascii(path)
    u = data[:, 0] - radius
    re = radius * data[:, 1]
    im = radius * data[:, 2]
    return u, re, im, np.sqrt(re**2 + im**2)


def fig_psi4(run_data, ref_dir, out_dir, summary):
    """Plot the psi4 overlay and estimate merger times."""
    u5, re5, _, amp5 = load_psi4(run_data / "mp_psi4_l2_m2_r500.00.asc", 500.0)
    u1, _, _, amp1 = load_psi4(run_data / "mp_psi4_l2_m2_r100.00.asc", 100.0)
    ur, rer, _, ampr = load_psi4(ref_dir / "mp_psi4_l2_m2_r500.00.asc", 500.0)

    t_run, run_at_edge = peak_time(u1 + 100.0, amp1)
    merger_run = t_run - 100.0
    t_ref, _ = peak_time(ur + 500.0, ampr)
    merger_ref = t_ref - 500.0

    summary["merger_run"] = merger_run
    summary["merger_run_at_edge"] = run_at_edge
    summary["merger_ref"] = merger_ref
    # Confirm the r=500 extraction of the run cannot contain the merger:
    # past the junk-radiation burst (u < 150) its amplitude must still be
    # rising at the final sample.
    phys = u5 > 150.0
    summary["run_r500_peak_at_edge"] = peak_time(u5[phys], amp5[phys])[1]

    fig, (ax0, ax1) = plt.subplots(2, 1, figsize=(9, 7.5))

    ax0.plot(ur, rer, color=C_REF, label="reference r=500 M (dx=19.2)")
    ax0.plot(u5, re5, color=C_RUN, label="run r=500 M (dx=28.0)")
    ax0.set_xlim(-100, 420)
    ax0.set_xlabel("retarded time  u = t - r  [M]")
    ax0.set_ylabel(r"Re[$r\,\psi_4$]  ($l$=2, $m$=2)")
    ax0.set_title("Inspiral overlap at r=500 M (run ends at u = 396 M)")
    ax0.legend(loc="upper left")

    ax1.semilogy(ur, ampr, color=C_REF, label="reference r=500 M")
    ax1.semilogy(u5, amp5, color=C_RUN, label="run r=500 M")
    ax1.semilogy(u1, amp1, color=C_AUX, linestyle="--",
                 label="run r=100 M (contains merger)")
    ax1.axvline(merger_run, color=C_AUX, alpha=0.5, linestyle=":")
    ax1.axvline(merger_ref, color=C_REF, alpha=0.5, linestyle=":")
    ax1.annotate(f"run merger\n{merger_run:.0f} M", (merger_run, 2e-3),
                 textcoords="offset points", xytext=(6, 0), fontsize=9)
    ax1.annotate(f"ref merger\n{merger_ref:.0f} M", (merger_ref, 2e-6),
                 textcoords="offset points", xytext=(6, 0), fontsize=9)
    ax1.set_xlim(-100, 900)
    ax1.set_ylim(1e-8, 2e-1)
    ax1.set_xlabel("retarded time  u = t - r  [M]")
    ax1.set_ylabel(r"|$r\,\psi_4$|  ($l$=2, $m$=2)")
    ax1.set_title("Amplitude with merger-time estimates (dotted)")
    ax1.legend(loc="lower right")

    fig.tight_layout()
    fig.savefig(out_dir / "psi4_l2m2_overlay.png")
    plt.close(fig)


def fig_orbit(run_data, run_root, out_dir, summary):
    """Plot BH/NS coordinate tracks and their separation."""
    pt = load_ascii(run_data / "puncturetracker-pt_loc..asc")
    t_bh = pt[:, PT_COL_TIME]
    x_bh, y_bh = pt[:, PT_COL_X0], pt[:, PT_COL_Y0]

    vi = load_ascii(
        run_root / "volume_integration" / "volume_integrals-GRMHD.asc")
    t_ns = vi[:, VI_COL_TIME]
    mass = vi[:, VI_COL_MASS]
    x_ns = vi[:, VI_COL_COMX] / mass
    y_ns = vi[:, VI_COL_COMY] / mass

    sep = np.hypot(np.interp(t_ns, t_bh, x_bh) - x_ns,
                   np.interp(t_ns, t_bh, y_bh) - y_ns)
    summary["sep_initial"] = float(sep[0])
    summary["ns_mass_initial"] = float(mass[0])
    # Conservation is only meaningful while the NS exists; after merger
    # the tracking sphere drains into the BH, which is reported separately.
    inspiral = t_ns < 600.0
    summary["ns_mass_drift_inspiral"] = float(
        (mass[inspiral].max() - mass[inspiral].min()) / mass[0])
    summary["ns_mass_final_fraction"] = float(mass[-1] / mass[0])

    fig, (ax0, ax1) = plt.subplots(1, 2, figsize=(11.5, 5))

    ax0.plot(x_bh, y_bh, color=C_RUN, label="BH puncture")
    ax0.plot(x_ns, y_ns, color=C_REF, label="NS center of mass")
    ax0.plot(x_bh[0], y_bh[0], "o", color=C_RUN, markersize=8)
    ax0.plot(x_ns[0], y_ns[0], "o", color=C_REF, markersize=8)
    ax0.set_aspect("equal")
    ax0.set_xlabel("x [M]")
    ax0.set_ylabel("y [M]")
    ax0.set_title("Coordinate tracks (dots mark t=0)")
    ax0.legend(loc="upper right")

    ax1.plot(t_ns, sep, color=C_RUN)
    ax1.axhline(30.0, color="gray", alpha=0.5, linestyle=":")
    ax1.annotate("initial separation 30 M", (0, 30.5), fontsize=9)
    if "merger_run" in summary:
        ax1.axvline(summary["merger_run"], color=C_AUX, alpha=0.5,
                    linestyle=":")
    ax1.set_xlabel("t [M]")
    ax1.set_ylabel("BH-NS separation [M]")
    ax1.set_title("Separation (NS CoM leaves its sphere after disruption)")

    fig.tight_layout()
    fig.savefig(out_dir / "orbit_tracks.png")
    plt.close(fig)


def fig_matter(run_data, run_root, out_dir, summary):
    """Plot max rest-mass density and apparent-horizon masses."""
    rho = load_ascii(run_data / "hydrobase-rho.maximum.asc")
    t_rho, rho_max = rho[:, 1], rho[:, 2]

    ah1 = load_ascii(run_root / "BH" / "BH_diagnostics.ah1.gp")
    fig, (ax0, ax1) = plt.subplots(2, 1, figsize=(9, 7), sharex=True)

    ax0.semilogy(t_rho, rho_max / rho_max[0], color=C_RUN)
    ax0.set_ylabel(r"$\rho_{\max}(t)\,/\,\rho_{\max}(0)$")
    ax0.set_title("Maximum rest-mass density (drop = NS swallowed/disrupted)")

    ax1.plot(ah1[:, 1], ah1[:, 26], color=C_RUN, label="ah1 (BH)")
    ah2_path = run_root / "BH" / "BH_diagnostics.ah2.gp"
    if ah2_path.exists():
        ah2 = load_ascii(ah2_path)
        ax1.plot(ah2[:, 1], ah2[:, 26], color=C_AUX,
                 label="ah2 (post-merger)")
        summary["ah2_first"] = float(ah2[0, 1])
        summary["ah2_final_mass"] = float(ah2[-1, 26])
    summary["ah1_initial_mass"] = float(ah1[0, 26])
    summary["ah1_final_mass"] = float(ah1[-1, 26])
    if "merger_run" in summary:
        for ax in (ax0, ax1):
            ax.axvline(summary["merger_run"], color=C_AUX, alpha=0.5,
                       linestyle=":")
    ax1.set_xlabel("t [M]")
    ax1.set_ylabel(r"$m_{\mathrm{irr}}$ [$M_\odot$]")
    ax1.set_title("Apparent-horizon irreducible mass")
    ax1.legend(loc="lower right")

    fig.tight_layout()
    fig.savefig(out_dir / "matter_horizons.png")
    plt.close(fig)


def fig_rho2d(run_data, ref_dir, out_dir, summary):
    """Plot matched-time 2D density snapshots, run vs reference.

    Reads the Carpet HDF5 output through kuibit and resamples the AMR
    hierarchy onto a uniform grid. Failure here (e.g. kuibit API drift)
    must not kill the scalar analysis, so the caller wraps this.
    """
    from kuibit.simdir import SimDir

    targets = [0.0, 448.0, 672.0, 806.4]
    extent, shape = 64.0, [512, 512]

    fields = {}
    for name, path in (("run", run_data), ("ref", ref_dir)):
        fields[name] = SimDir(str(path)).gf.xy["rho"]

    fig, axes = plt.subplots(2, len(targets), figsize=(3.2 * len(targets), 7),
                             sharex=True, sharey=True)
    im = None
    for row, name in enumerate(("run", "ref")):
        field = fields[name]
        times = np.array(field.available_times)
        iters = np.array(field.available_iterations)
        for col, t_want in enumerate(targets):
            i = int(np.argmin(np.abs(times - t_want)))
            grid = field[iters[i]].to_UniformGridData(
                shape, x0=[-extent, -extent], x1=[extent, extent],
                resample=True)
            log_rho = np.log10(np.abs(grid.data.T) + 1e-15)
            im = axes[row, col].imshow(
                log_rho, origin="lower", cmap="magma", vmin=-9.0, vmax=-2.5,
                extent=[-extent, extent, -extent, extent])
            axes[row, col].grid(False)
            axes[row, col].set_title(f"{name}  t = {times[i]:.0f} M",
                                     fontsize=10)
    for ax in axes[1, :]:
        ax.set_xlabel("x [M]")
    for ax in axes[:, 0]:
        ax.set_ylabel("y [M]")
    fig.suptitle("Rest-mass density in the orbital plane "
                 "(top: run dx=28.0, bottom: reference dx=19.2)")
    fig.colorbar(im, ax=axes, shrink=0.85,
                 label=r"$\log_{10}\rho$  (geometric units)")
    fig.savefig(out_dir / "rho_xy_snapshots.png")
    plt.close(fig)
    summary["rho2d_ok"] = True


def write_summary(out_dir, summary):
    """Write the numerical comparison to ``summary.md``."""
    lines = [
        "# Phase 3 analysis dry-run summary",
        "",
        "Local dx=28.0 run (t = 0..896 M) vs reference bhns_20252103.",
        "",
        f"| quantity | value |",
        f"| --- | --- |",
        f"| merger (run, source frame, from r=100 peak) | "
        f"{summary['merger_run']:.1f} M |",
        f"| merger (reference, from r=500 peak) | "
        f"{summary['merger_ref']:.1f} M |",
        f"| merger shift (run - ref) | "
        f"{summary['merger_run'] - summary['merger_ref']:+.1f} M |",
        f"| run r=500 amplitude still rising at end | "
        f"{summary['run_r500_peak_at_edge']} (expected True) |",
        f"| initial BH-NS separation | {summary['sep_initial']:.2f} M |",
        f"| NS baryon mass (tracking sphere, t=0) | "
        f"{summary['ns_mass_initial']:.4f} |",
        f"| NS baryon mass drift (inspiral, t < 600 M) | "
        f"{100 * summary['ns_mass_drift_inspiral']:.3f} % |",
        f"| NS baryon mass left in sphere at t=896 M | "
        f"{100 * summary['ns_mass_final_fraction']:.2f} % |",
        f"| ah1 m_irr initial | {summary['ah1_initial_mass']:.4f} |",
        f"| ah1 m_irr final | {summary['ah1_final_mass']:.4f} |",
    ]
    if "ah2_first" in summary:
        lines += [
            f"| ah2 first found at | {summary['ah2_first']:.1f} M |",
            f"| ah2 m_irr final | {summary['ah2_final_mass']:.4f} |",
        ]
    if summary.get("merger_run_at_edge"):
        lines += ["", "**WARNING**: run r=100 peak sits at the last sample; "
                  "the merger may not be contained in the run."]
    if not summary.get("rho2d_ok"):
        lines += ["", "**WARNING**: 2D density comparison failed; "
                  "see stderr for the kuibit error."]
    lines += [
        "",
        "Figures: psi4_l2m2_overlay.png, orbit_tracks.png, "
        "matter_horizons.png, rho_xy_snapshots.png",
        "",
    ]
    (out_dir / "summary.md").write_text("\n".join(lines))


def main():
    """Run all comparisons and write figures plus summary.md."""
    parser = argparse.ArgumentParser(
        description="Phase 3 run-vs-reference analysis")
    parser.add_argument(
        "--run-dir", type=Path,
        default=Path("/home/etuser/simulations/dx28/run"),
        help="run directory containing data/, BH/, volume_integration/")
    parser.add_argument(
        "--ref-dir", type=Path,
        default=Path("/home/etuser/work/upstream/bhns_20252103"),
        help="extracted reference dataset directory")
    parser.add_argument(
        "--out-dir", type=Path,
        default=Path("/home/etuser/work/reports/phase3"),
        help="output directory for figures and summary.md")
    args = parser.parse_args()

    run_data = args.run_dir / "data"
    args.out_dir.mkdir(parents=True, exist_ok=True)
    summary = {}

    fig_psi4(run_data, args.ref_dir, args.out_dir, summary)
    print(f"merger (run):       {summary['merger_run']:.1f} M")
    print(f"merger (reference): {summary['merger_ref']:.1f} M")

    fig_orbit(run_data, args.run_dir, args.out_dir, summary)
    fig_matter(run_data, args.run_dir, args.out_dir, summary)

    try:
        fig_rho2d(run_data, args.ref_dir, args.out_dir, summary)
    except Exception as exc:  # noqa: BLE001 - keep scalar results on failure
        print(f"2D density comparison failed: {exc}", file=sys.stderr)
        summary["rho2d_ok"] = False

    write_summary(args.out_dir, summary)
    print(f"wrote {args.out_dir}/summary.md and figures")


if __name__ == "__main__":
    main()
