#!/usr/bin/env python3
"""Capstone figures for examples/06_capstone (Fortran-Julia CJ detonation).

Figure contracts (nature-figure five-point contract):
  fig1_sod_transport        183 mm, a|b|c = rho|u|p vs exact Riemann solution.
      Core conclusion: the vendored Clawpack Godunov transport kernel
      reproduces the exact Sod solution at first-order resolution.
  fig2_detonation_structure 183 mm, 2x2 rho|u|p|Z with CJ reference lines and
      a reaction-layer inset on Z.  Core conclusion: the Strang-split
      Fortran-Julia coupling sustains a CJ detonation whose burnt state
      matches the analytic CJ values and whose front runs at s_CJ.
  fig3_front_speed           89 mm, single panel.  Core conclusion: the front
      trajectory is linear at 7.12391 vs s_CJ 7.12470 (0.011% deviation).
  fig4_performance           89 mm, a|b = startup (log) | steady per-cell
      cost.  Core conclusion: the embedding modes separate on startup cost
      while steady per-cell cost is indistinguishable within node-load noise.

Data sources (all committed conventions):
  ../output/sod_final.dat, det_final.dat, det_front.dat  -- written by the
  Fortran driver; headers carry the run parameters and CJ constants.
  Performance constants are transcribed from PERFORMANCE.md with the
  section/line noted on each constant (numbers verified there against logs).

Data integrity: every point of every curve is plotted, no smoothing, no
averaging.  The only exclusion is recorded below (AOT_STEADY_EXCLUDED) with
the reason given in PERFORMANCE.md.

Backend: Python/matplotlib exclusively (render, preview, export, QA).
Exports: PNG 600 dpi + PDF (user contract; no SVG/TIFF).  The glyph and
collision audits read the committed PDFs directly.
"""

import re
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.transforms import ScaledTranslation

FIGS = Path(__file__).resolve().parent
OUT = FIGS.parent / "output"
SKILL_SCRIPTS = Path(
    "/home/redacted/.claude/local-marketplaces/nature-skills/"
    "skills/nature-figure/scripts"
)
sys.path.insert(0, str(SKILL_SCRIPTS))
from audit_panel_alignment import require_matplotlib_panel_alignment  # noqa: E402

# -- mandatory editable-text rules (nature-figure) + publication stance ----
# export contract per user decision: PNG (600 dpi) + PDF; SVG/TIFF are
# deliberately NOT exported (recorded deviation from the skill default, which
# wants SVG primary) -- final widths: 183 mm double column, 89 mm single.
plt.rcParams.update({
    'font.family': 'sans-serif',
    'font.sans-serif': ['Arial', 'Helvetica', 'DejaVu Sans', 'sans-serif'],
    'svg.fonttype': 'none',   # keep text editable if SVG is ever exported
    'pdf.fonttype': 42,       # embed TrueType, keep PDF text editable
    'font.size': 7,
    'axes.spines.right': False,
    'axes.spines.top': False,
    'axes.linewidth': 0.8,
    'legend.frameon': False,
    'xtick.direction': 'out',
    'ytick.direction': 'out',
})

PALETTE = {
    "blue_main": "#0F4D92",     # computed / numerical / measured
    "red_strong": "#B64342",    # analytic reference (exact / CJ)
    "teal": "#42949E",          # mode: sysimage
    "violet": "#9A4D8E",        # mode: AOT
    "neutral_mid": "#767676",   # mode: pure Julia (baseline)
    "neutral_light": "#CFCECE",
    "neutral_black": "#272727",
}
MODE_COLOR = {
    "jit": PALETTE["blue_main"],
    "sysimage": PALETTE["teal"],
    "AOT": PALETTE["violet"],
    "pure Julia": PALETTE["neutral_mid"],
}

MM = 1 / 25.4
W_DOUBLE = 183 * MM
W_SINGLE = 89 * MM

# -- performance constants (PERFORMANCE.md, 2026-10-26/27 measured runs) ----
# "Startup ranges" section, lines around 37-39: same-day init ranges
# jit 15.1-20.2 s, sysimage 0.93-2.37 s; AOT init line ~84: 0.58-1.97 s;
# mode-comparison table line ~73: pure Julia 17.5 s load (single run).
STARTUP_S = {
    "jit": (15.1, 20.2),
    "sysimage": (0.93, 2.37),
    "AOT": (0.58, 1.97),
    "pure Julia": 17.5,          # single run -> diamond marker
}
# per-active-cell-solve, lines ~56-57 and ~73-75: jit 175-190, sysimage
# 159-198 (batch ranges), pure Julia 309 (single run), AOT eight runs
# 236/347/319/240/240/191/353/361 -> 1-core runs span 236-361.
PERCELL_US = {
    "jit": (175.0, 190.0),
    "sysimage": (159.0, 198.0),
    "AOT": (236.0, 361.0),
    "pure Julia": 309.0,         # single run -> diamond marker
}
# EXCLUSION (recorded per data-integrity gate): the 191 us AOT run was
# measured inside a 32-core allocation (dedicated physical cores) while every
# other number is a 1-core run on the loaded shared node; not comparable,
# excluded from the AOT range (PERFORMANCE.md, footnote **).
AOT_STEADY_EXCLUDED = ("AOT steady 191 us (32-core run)", "dedicated physical cores, not comparable")

DRIVER_SPEED = 7.12391   # driver print "detonation speed" (cross-check)


def add_panel_label(ax, label, x_offset_pt=-4.5, y_offset_pt=2.5, fontsize=8):
    offset = ScaledTranslation(
        x_offset_pt / 72, y_offset_pt / 72, ax.figure.dpi_scale_trans
    )
    ax.text(
        0, 1, label, transform=ax.transAxes + offset,
        fontsize=fontsize, fontweight="bold", color="black", ha="left", va="bottom",
    )


def style_axis(ax, labelsize=6):
    ax.tick_params(labelsize=labelsize)
    for spine in ax.spines.values():
        spine.set_linewidth(0.8)


def finalize(fig, name, alignment_kwargs=None, pad=1.2):
    fig.tight_layout(pad=pad)
    kwargs = dict(
        json_out=str(FIGS / f"{name}.alignment.json"),
        overlay_svg=None,
        tolerance_pt=1.5,
        gutter_tolerance_pt=1.5,
        strict=True,
    )
    kwargs.update(alignment_kwargs or {})
    report = require_matplotlib_panel_alignment(fig, **kwargs)
    fig.savefig(FIGS / f"{name}.png", dpi=600)
    fig.savefig(FIGS / f"{name}.pdf")
    plt.close(fig)
    print(f"[{name}] rendered; alignment: {report.get('verdict', report.get('result'))}")


# -- data loading with integrity assertions ---------------------------------
def load_sod():
    path = OUT / "sod_final.dat"
    header = [l for l in path.read_text().splitlines() if l.startswith("#")]
    assert header[1] == "# columns: x rho u p Z rho_exact u_exact p_exact", header[1]
    d = np.loadtxt(path)
    assert d.shape == (400, 8), d.shape
    return d


def load_det():
    path = OUT / "det_final.dat"
    text = path.read_text().splitlines()
    hdr = [l for l in text if l.startswith("#")]
    cj = {
        k: float(v)
        for k, v in re.findall(
            r"(rho_cj|u_cj|p_cj|s_cj) =\s*([-\d.E+]+)", hdr[1]
        )
    }
    m = re.search(r"t =\s*([\d.]+)", hdr[0])
    assert m, hdr[0]
    t_end = float(m.group(1))
    assert set(cj) == {"rho_cj", "u_cj", "p_cj", "s_cj"}, cj
    d = np.loadtxt(path)
    assert d.shape == (2700, 5), d.shape
    return d, cj, t_end


def load_front(t_end):
    path = OUT / "det_front.dat"
    d = np.loadtxt(path)
    assert d.ndim == 2 and d.shape[1] == 2, d.shape
    t, xf = d.T
    # driver measurement window: first sample with t >= 0.5*t_final
    ia = int(np.argmax(t >= 0.5 * t_end))
    slope = (xf[-1] - xf[ia]) / (t[-1] - t[ia])
    assert abs(slope - DRIVER_SPEED) < 1e-3, (slope, DRIVER_SPEED)
    return t, xf, ia, slope


# ---------------------------------------------------------------- fig 1 ----
def fig1(sod):
    x = sod[:, 0]
    fig, axes = plt.subplots(1, 3, figsize=(W_DOUBLE, 55 * MM))
    panels = [
        ("ρ", sod[:, 1], sod[:, 5]),
        ("u", sod[:, 2], sod[:, 6]),
        ("p", sod[:, 3], sod[:, 7]),
    ]
    for k, (ylab, num, exact) in enumerate(panels):
        ax = axes[k]
        style_axis(ax)
        ax.plot(x, num, color=PALETTE["blue_main"], lw=1.0,
                label="Computed", zorder=3)
        # reference drawn ABOVE the data: dash gaps let the computed line
        # show through, so coincidence is readable as red-dash-over-blue
        ax.plot(x, exact, color=PALETTE["red_strong"], lw=1.0, ls=(0, (3, 2)),
                label="Exact (Riemann)", zorder=4)
        ax.set_xlabel("x", fontsize=7)
        ax.set_ylabel(ylab, fontsize=7)
        add_panel_label(ax, "abc"[k])
    axes[0].legend(fontsize=6, loc="upper right", handlelength=1.6,
                   borderaxespad=0.2)
    finalize(fig, "fig1_sod_transport")
    print(
        "  panel audit: a rho | b u | c p; 400 cells at t=0.2, all points\n"
        "  plotted; no smoothing; exact from driver-side Toro sampler."
    )


# ---------------------------------------------------------------- fig 2 ----
def fig2(det, cj):
    x, rho, u, p, Z = det.T
    xf_front = x[np.argmin(np.abs(Z - 0.5))]
    fig, axes = plt.subplots(2, 2, figsize=(W_DOUBLE, 128 * MM))
    panels = [
        ("ρ", rho, cj["rho_cj"]), ("u", u, cj["u_cj"]),
        ("p", p, cj["p_cj"]),
    ]
    for k, (ylab, data, cj_val) in enumerate(panels):
        ax = axes.flat[k]
        style_axis(ax)
        ax.plot(x, data, color=PALETTE["blue_main"], lw=0.9, zorder=3)
        ax.axhline(cj_val, color=PALETTE["red_strong"], lw=1.0, ls=(0, (3, 2)),
                   zorder=4)   # on top of the plateau, gaps show the data
        y0, y1 = ax.get_ylim()
        ax.set_ylim(y0, cj_val + 0.12 * (y1 - y0))       # headroom for label
        y_ax = (cj_val - y0) / (ax.get_ylim()[1] - y0)
        ax.text(0.02, y_ax + 0.035, "CJ", transform=ax.transAxes,
                color=PALETTE["red_strong"], fontsize=6, ha="left", va="bottom")
        ax.set_xlabel("x", fontsize=7)
        ax.set_ylabel(ylab, fontsize=7)
        add_panel_label(ax, "abc"[k])

    # Z panel (d): unburnt reactant fraction, Z=1 fresh gas / Z=0 burnt
    ax = axes.flat[3]
    style_axis(ax)
    ax.plot(x, Z, color=PALETTE["blue_main"], lw=0.9, zorder=3)
    ax.set_xlabel("x", fontsize=7)
    ax.set_ylabel("Z (unburnt)", fontsize=7)
    ax.set_ylim(-0.06, 1.1)
    add_panel_label(ax, "d")

    inset = ax.inset_axes([0.06, 0.52, 0.52, 0.44])
    win = (xf_front - 0.03, xf_front + 0.015)
    m = (x >= win[0]) & (x <= win[1])
    inset.plot(x[m], Z[m], color=PALETTE["blue_main"], lw=1.0)
    inset.axhline(0.5, color=PALETTE["neutral_mid"], lw=0.6, ls=":")
    inset.set_xlim(win)
    inset.set_ylim(-0.06, 1.1)
    inset.tick_params(labelsize=5.5, labelleft=False)  # same 0-1 scale as panel d
    inset.set_xlabel("x", fontsize=5.5, labelpad=1.5)
    for spine in inset.spines.values():
        spine.set_linewidth(0.6)
    layer = int(np.sum((Z > 0.1) & (Z < 0.9))) + 1
    inset.text(0.04, 0.90, f"reaction layer ≈ {layer} Δx", transform=inset.transAxes,
               fontsize=5.5, ha="left", va="top")
    # connector lines omitted: the zoom rectangle + inset make the region
    # unambiguous, and the connectors cross the inset tick labels (collision
    # audit FAIL)
    _, connectors = ax.indicate_inset_zoom(
        inset, edgecolor=PALETTE["neutral_mid"], lw=0.6, alpha=0.9
    )
    for c in connectors:
        c.set_visible(False)

    finalize(fig, "fig2_detonation_structure",
             alignment_kwargs=dict(exclude_axes=[inset]))
    print(
        "  panel audit: a rho | b u | c p | d Z; CJ dashed reference from\n"
        "  det_final.dat header (driver constants); inset zoom on the Z cliff,\n"
        "  excluded from alignment groups as an inset."
    )


# ---------------------------------------------------------------- fig 3 ----
def fig3(t, xf, ia, slope, cj, t_end):
    fig, ax = plt.subplots(figsize=(W_SINGLE, 68 * MM))
    style_axis(ax)
    # driver measurement window (second half of the run), behind everything
    ax.axvspan(t[ia], t_end, color=PALETTE["neutral_light"], alpha=0.30, lw=0,
               zorder=1)
    ax.plot(t, xf, color=PALETTE["blue_main"], lw=0.7, zorder=2)
    ax.plot(t[::25], xf[::25], "o", color=PALETTE["blue_main"], ms=1.8,
            mec="none", zorder=2.5)   # every 25th of the 2608 samples
    # driver secant: two-point speed measurement between (t_a, x_a) and end
    secant = xf[ia] + slope * (t - t[ia])
    ax.plot(t, secant, color=PALETTE["blue_main"], lw=1.4, zorder=3.5)
    ax.plot([t[ia], t[-1]], [xf[ia], xf[-1]], "o", color=PALETTE["blue_main"],
            ms=3.5, mec="white", mew=0.5, zorder=5)
    # CJ reference through the same endpoint
    ref = xf[-1] + cj["s_cj"] * (t - t[-1])
    # CJ reference on top of the secant: dash gaps reveal how the two
    # slopes coincide over the whole measurement window
    ax.plot(t, ref, color=PALETTE["red_strong"], lw=1.0, ls=(0, (3, 2)), zorder=4)
    dev = 100.0 * abs(slope - cj["s_cj"]) / cj["s_cj"]
    ax.text(0.03, 0.97, f"measured slope  {slope:.5f}", transform=ax.transAxes,
            color=PALETTE["blue_main"], fontsize=6.5, va="top", ha="left")
    ax.text(0.03, 0.905,
            f"CJ  {cj['s_cj']:.5f}  (deviation {dev:.3f}%)",
            transform=ax.transAxes, color=PALETTE["red_strong"], fontsize=6.5,
            va="top", ha="left")
    ax.set_xlabel("t", fontsize=7)
    ax.set_ylabel("front position", fontsize=7)
    ax.set_xlim(-0.004, 0.308)
    finalize(fig, "fig3_front_speed",
             alignment_kwargs=dict(require_panel_labels=False))
    print(
        "  panel audit: single panel; 2608 samples (line) + every 25th as\n"
        "  marker; secant is\n"
        "  the driver's own two-point measurement (t_a = first t >= 0.5 t_end,\n"
        "  cross-checked against the driver print 7.12391)."
    )


# ---------------------------------------------------------------- fig 4 ----
def fig4():
    modes = list(MODE_COLOR)
    fig, axes = plt.subplots(1, 2, figsize=(W_SINGLE, 72 * MM))
    for ax, data, ylab in (
        (axes[0], STARTUP_S, "startup time (s)"),
        (axes[1], PERCELL_US, "per-cell solve time (µs)"),
    ):
        for i, mode in enumerate(modes):
            v = data[mode]
            if isinstance(v, tuple):
                ax.bar(i, v[1] - v[0], bottom=v[0], width=0.62,
                       color=MODE_COLOR[mode], edgecolor=PALETTE["neutral_black"],
                       linewidth=0.5, zorder=3)
            else:
                ax.plot(i, v, marker="D", ms=3.5, color=MODE_COLOR[mode],
                        mec=PALETTE["neutral_black"], mew=0.5, ls="none",
                        zorder=4)
        labels = ["jit", "sysimage", "AOT", "pure\nJulia"]
        ax.set_xticks(range(len(modes)))
        ax.set_xticklabels(labels, fontsize=6)
        ax.set_ylabel(ylab, fontsize=7)
        style_axis(ax)
        add_panel_label(ax, "ab"[list(axes).index(ax)])
    bottoms = [v[0] for v in STARTUP_S.values() if isinstance(v, tuple)]
    assert min(bottoms) > 0, "log axis needs strictly positive bar bottoms"
    axes[0].set_yscale("log")
    axes[0].set_yticks([0.5, 1, 2, 5, 10, 20])
    axes[0].set_ylim(0.4, 40)
    from matplotlib.ticker import ScalarFormatter
    axes[0].get_yaxis().set_major_formatter(ScalarFormatter())
    axes[1].set_ylim(0, 400)
    axes[1].set_yticks([0, 100, 200, 300, 400])
    fig.tight_layout(pad=1.2, rect=(0, 0.13, 1, 1))
    fig.text(
        0.015, 0.012,
        "Bars: min–max over same-day runs on the loaded node (~±20% run-to-run).\n"
        "Diamonds: single runs (pure Julia, 17.5 s startup, 309 µs per cell).\n"
        "AOT steady range excludes one 32-core run (191 µs; dedicated cores).",
        fontsize=5.5, ha="left", va="bottom", linespacing=1.3,
    )
    report = require_matplotlib_panel_alignment(
        fig, json_out=str(FIGS / "fig4_performance.alignment.json"),
        overlay_svg=None, tolerance_pt=1.5, gutter_tolerance_pt=1.5,
        require_panel_labels=True, strict=True,
    )
    fig.savefig(FIGS / "fig4_performance.png", dpi=600)
    fig.savefig(FIGS / "fig4_performance.pdf")
    plt.close(fig)
    print(f"[fig4_performance] rendered; alignment: {report.get('verdict', report.get('result'))}")
    print(
        "  panel audit: a startup (log s) | b steady per-cell (µs); ranges from\n"
        "  PERFORMANCE.md; exclusion recorded in-figure and in the header."
    )


def main():
    sod = load_sod()
    det, cj, t_end = load_det()
    t, xf, ia, slope = load_front(t_end)
    print(f"integrity: slope {slope:.5f} vs driver {DRIVER_SPEED} | "
          f"CJ {cj} | t_end {t_end}")
    print(f"exclusion: {AOT_STEADY_EXCLUDED[0]} — {AOT_STEADY_EXCLUDED[1]}")
    fig1(sod)
    fig2(det, cj)
    fig3(t, xf, ia, slope, cj, t_end)
    fig4()


if __name__ == "__main__":
    main()
