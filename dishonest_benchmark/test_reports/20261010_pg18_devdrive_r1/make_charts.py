# -*- coding: utf-8 -*-
"""Draw the six result charts (charts/fig*.png) from pg18/results_round1.csv."""
import csv, os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.ticker import FuncFormatter
from matplotlib.patches import Patch

HERE = os.path.dirname(os.path.abspath(__file__))
CSV = os.path.join(HERE, "pg18", "results_round1.csv")
OUTDIR = os.path.join(HERE, "charts")
FOOTER = ("PostgreSQL 18.6, Windows 11, trusted Dev Drive V: (ReFS) with Defender performance mode, "
          "pgbench -c 32 -j 8 -T 120, 1 round")

with open(CSV, newline="", encoding="utf-8-sig") as f:
    res = list(csv.DictReader(f))
for r in res:
    for k in ("tps", "ops_per_sec", "lat_ms", "wal_per_tx"):
        r[k] = float(r[k])
    r["ops_per_txn"] = int(r["ops_per_txn"]); r["wal_bytes"] = int(r["wal_bytes"]); r["txns"] = int(r["txns"])
by = {r["method"]: r for r in res}

base  = by["Indexed baseline"]["tps"]
case0 = by["Case 0: bad code / missing index"]["tps"]
def reported(m):
    r = by[m]
    return r["ops_per_sec"] if r["ops_per_txn"] > 1 else r["tps"]

FIN_BATCH = "all cheats + batch x32"
FIN_MEGA  = "all cheats + mega-batch x1000"

# stamp every chart with the run conditions
_savefig = plt.savefig
def _stamped(*a, **k):
    plt.gcf().text(0.995, 0.004, FOOTER, ha="right", va="bottom", fontsize=8, color="#666666")
    return _savefig(*a, **k)
plt.savefig = _stamped

# ---------------------------------------------------------------- chart style
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 11, "axes.titlesize": 14,
    "axes.titleweight": "bold", "axes.grid": True, "grid.alpha": 0.25, "axes.axisbelow": True,
    "figure.facecolor": "white", "axes.edgecolor": "#999999"})
BAD="#7f7f7f"; HONEST="#2E8B57"; DURAB="#E07B39"; WORK="#C0392B"; SRV="#8E44AD"; UNIT="#B8860B"
CAT = {
 "Case 0: bad code / missing index": BAD,
 "Indexed baseline": HONEST, "Indexed baseline (repeat)": HONEST,
 "synchronous_commit=off": DURAB, "full_page_writes=off": DURAB, "fsync=off": DURAB,
 "checkpoint tuning": DURAB, "all durability off": DURAB,
 "less work (drop FK/SELECT/audit)": WORK, "UNLOGGED ledger/audit": WORK,
 "stored procedure": SRV, "stored function (SQL)": SRV, "prepared protocol": SRV,
 "prepared + pipelined": SRV, "stored proc + prepared": SRV, "sql function + prepared": SRV,
 "all cheats + batch x32 (SQL fn)": UNIT, "all cheats + batch x128 (SQL fn)": UNIT,
 "batching x8": UNIT, "batching x32": UNIT, "batching x128": UNIT, FIN_BATCH: UNIT, FIN_MEGA: UNIT,
}
STACKED = {FIN_BATCH, "all cheats + batch x32 (SQL fn)", "all cheats + batch x128 (SQL fn)"}
SHORT = {
 "Case 0: bad code / missing index":"Case 0\n(missing idx)",
 "Indexed baseline":"Indexed\nbaseline",
 "synchronous_commit=off":"sync_commit\n=off",
 "full_page_writes=off":"full_page\n_writes=off",
 "fsync=off":"fsync\n=off",
 "checkpoint tuning":"checkpoint\ntuning",
 "all durability off":"all durab.\noff",
 "less work (drop FK/SELECT/audit)":"less\nwork",
 "UNLOGGED ledger/audit":"UNLOGGED\nledger/audit",
 "stored procedure":"stored proc\n(plpgsql)",
 "stored function (SQL)":"stored fn\n(SQL)",
 "prepared protocol":"prepared\nprotocol",
 "prepared + pipelined":"prepared+\npipelined",
 "stored proc + prepared":"stored proc\n+prepared",
 "sql function + prepared":"sql fn\n+prepared",
 "batching x8":"batch x8",
 "batching x32":"batch x32",
 "batching x128":"batch x128",
 FIN_BATCH:"ALL CHEATS\n+batch x32",
 "all cheats + batch x32 (SQL fn)":"ALL CHEATS\n+b32(SQLfn)",
 "all cheats + batch x128 (SQL fn)":"ALL CHEATS\n+b128(SQLfn)",
 FIN_MEGA:"ALL CHEATS\n+mega x1000",
}
# --- pick the winning variants from the data --------------------------------
def _tps(m): return by[m]["tps"] if m in by else -1.0
def _ops(m): return by[m]["ops_per_sec"] if m in by else -1.0
COMBO  = "sql function + prepared" if _tps("sql function + prepared") > _tps("stored proc + prepared") else "stored proc + prepared"
# standalone batching bar: x32 (batch x128 intentionally ignored per request)
BATCH  = "batching x32"
# finale: the highest-OPS stacked variant that was actually measured (x128 ignored)
_fin_cands = [m for m in ("all cheats + batch x32 (SQL fn)", FIN_BATCH) if m in by]
FINALE = max(_fin_cands, key=lambda m: by[m]["ops_per_sec"]) if _fin_cands else FIN_BATCH
LADDER = ["Case 0: bad code / missing index","Indexed baseline","synchronous_commit=off",
 "full_page_writes=off","fsync=off","checkpoint tuning","all durability off",
 "less work (drop FK/SELECT/audit)","UNLOGGED ledger/audit","stored procedure",
 "stored function (SQL)","prepared protocol", COMBO,
 "batching x8", BATCH, FINALE]
LADDER = [m for m in LADDER if m in by]
headline = max(LADDER, key=lambda m: by[m]["ops_per_sec"])   # biggest reported number among shown bars

def th(x, _): return f"{int(x):,}"
def style_stacked(bars, methods):
    for b, m in zip(bars, methods):
        if m in STACKED:
            b.set_edgecolor("black"); b.set_linewidth(2.0); b.set_hatch("//")

# ---------------------------------------------------------------- FIG 1: index
f1 = os.path.join(OUTDIR, "fig1_index.png")
fig, ax = plt.subplots(figsize=(7.2, 5.4))
b = ax.bar(["missing index\n(Case 0)", "composite index\n(baseline)"], [case0, base],
           color=[BAD, HONEST], edgecolor="white", width=0.62)
ax.set_ylabel("Transactions per second"); ax.yaxis.set_major_formatter(FuncFormatter(th))
ax.set_title("Step 1 (legitimate): add the missing index\non bench_audit(created_at, audit_id)")
for bb, v in zip(b, [case0, base]):
    ax.text(bb.get_x()+bb.get_width()/2, v, f"{v:,.0f}", ha="center", va="bottom", fontweight="bold")
ax.text(0.5, base*0.55, f"{base/case0:.0f}x", ha="center", fontsize=30, fontweight="bold", color=HONEST)
ax.margins(y=0.16); plt.tight_layout(); plt.savefig(f1, dpi=160); plt.close()

# --------------------------------------------- FIG 2: dishonest headline ladder
f2 = os.path.join(OUTDIR, "fig2_headline.png")
vals = [reported(m) for m in LADDER]; cols = [CAT[m] for m in LADDER]
fig, ax = plt.subplots(figsize=(14.5, 7.0))
bars = ax.bar([SHORT[m] for m in LADDER], vals, color=cols, edgecolor="white")
style_stacked(bars, LADDER)
ax.set_ylabel("TPS  /  operations per second (OPS)")
ax.set_title("My Dishonest Benchmark — the headline chart\n(labels show the multiplier vs Case 0 = 1x, the crippled baseline a marketer would pick)")
ax.yaxis.set_major_formatter(FuncFormatter(th)); plt.setp(ax.get_xticklabels(), fontsize=8.0)
for b, v, m in zip(bars, vals, LADDER):
    tag = f"{v:,.0f}\n{v/case0:,.0f}x" + ("\n(ops/s)" if by[m]["ops_per_txn"] > 1 else "")
    ax.text(b.get_x()+b.get_width()/2, v, tag, ha="center", va="bottom", fontsize=7.2, fontweight="bold")
ax.margins(y=0.20)
ax.legend(handles=[Patch(color=BAD,label="bad code (1x baseline)"), Patch(color=HONEST,label="indexed baseline"),
 Patch(color=DURAB,label="durability / WAL"), Patch(color=WORK,label="workload / storage"),
 Patch(color=SRV,label="server-side / protocol"), Patch(color=UNIT,label="unit-of-measurement"),
 Patch(facecolor="white",edgecolor="black",hatch="//",label="stacked (all cheats)")],
 loc="upper left", fontsize=8.6, framealpha=0.92, ncol=2)
plt.tight_layout(); plt.savefig(f2, dpi=160); plt.close()

# --------------------------------------------------- FIG 3: honest TPS units
f3 = os.path.join(OUTDIR, "fig3_tps.png")
vals3 = [by[m]["tps"] for m in LADDER]
fig, ax = plt.subplots(figsize=(14.5, 6.8))
bars = ax.bar([SHORT[m] for m in LADDER], vals3, color=cols, edgecolor="white")
style_stacked(bars, LADDER)
ax.axhline(base, color=HONEST, ls="--", lw=1.2, alpha=0.75)
ax.text(len(LADDER)-0.5, base, "  indexed baseline", color=HONEST, va="bottom", ha="right", fontsize=9)
ax.set_ylabel("Transactions per second (one bar = one business transaction)")
ax.set_title("The same runs in honest units: business transactions per second\n(labels show the multiplier vs the indexed baseline)")
ax.yaxis.set_major_formatter(FuncFormatter(th)); plt.setp(ax.get_xticklabels(), fontsize=8.0)
for b, v in zip(bars, vals3):
    ax.text(b.get_x()+b.get_width()/2, v, f"{v:,.0f}\n{v/base:.2f}x", ha="center", va="bottom", fontsize=7.2, fontweight="bold")
ax.margins(y=0.16); plt.tight_layout(); plt.savefig(f3, dpi=160); plt.close()

# ------------------------------------- FIG 3b: the same runs in OPS (ops/second)
f3b = os.path.join(OUTDIR, "fig4_ops.png")
vals3b = [by[m]["ops_per_sec"] for m in LADDER]   # OPS = TPS x ops-per-txn
fig, ax = plt.subplots(figsize=(14.5, 6.8))
bars = ax.bar([SHORT[m] for m in LADDER], vals3b, color=cols, edgecolor="white")
style_stacked(bars, LADDER)
ax.axhline(base, color=HONEST, ls="--", lw=1.2, alpha=0.75)
ax.text(len(LADDER)-0.5, base, "  indexed baseline", color=HONEST, va="bottom", ha="right", fontsize=9)
ax.set_ylabel("operations per second (OPS = TPS x ops-per-txn)")
ax.set_title("The same runs in operations per second (OPS)\n(labels show the multiplier vs the indexed baseline)")
ax.yaxis.set_major_formatter(FuncFormatter(th)); plt.setp(ax.get_xticklabels(), fontsize=8.0)
for b, v in zip(bars, vals3b):
    ax.text(b.get_x()+b.get_width()/2, v, f"{v:,.0f}\n{v/base:.1f}x", ha="center", va="bottom", fontsize=7.2, fontweight="bold")
ax.margins(y=0.17); plt.tight_layout(); plt.savefig(f3b, dpi=160); plt.close()

# --------------------------------------------------------------- FIG 5: latency
f5 = os.path.join(OUTDIR, "fig5_latency.png")
vals5 = [by[m]["lat_ms"] for m in LADDER]
fig, ax = plt.subplots(figsize=(14.5, 5.6))
bars = ax.bar([SHORT[m] for m in LADDER], vals5, color=cols, edgecolor="white")
style_stacked(bars, LADDER)
ax.set_ylabel("average latency per transaction (ms)"); ax.set_title("Average transaction latency (32 clients)")
plt.setp(ax.get_xticklabels(), fontsize=8.0)
for b, v in zip(bars, vals5):
    ax.text(b.get_x()+b.get_width()/2, v, f"{v:.2f}", ha="center", va="bottom", fontsize=7.0)
ax.margins(y=0.16); plt.tight_layout(); plt.savefig(f5, dpi=160); plt.close()

# ------------------------------------------- FIG 6: two baselines (the money shot)
f6 = os.path.join(OUTDIR, "fig6_two_baselines.png")
mm = [m for m in LADDER if m != "Case 0: bad code / missing index"]
xc = np.array([reported(m)/case0 for m in mm]); xb = np.array([reported(m)/base for m in mm])
x = np.arange(len(mm)); w = 0.4
fig, ax = plt.subplots(figsize=(14.5, 6.8))
b1 = ax.bar(x-w/2, xc, w, color="#C0392B", label="x vs Case 0 (crippled 1x) — marketing")
b2 = ax.bar(x+w/2, xb, w, color="#2E8B57", label="x vs indexed baseline — honest")
ax.set_yscale("log"); ax.set_ylabel("improvement multiplier (log scale)")
ax.set_title("Same numbers, two baselines: how the choice of \"1x\" inflates every claim")
ax.set_xticks(x); ax.set_xticklabels([SHORT[m] for m in mm], fontsize=8.0)
for bb, v in zip(b1, xc): ax.text(bb.get_x()+bb.get_width()/2, v, f"{v:,.0f}x", ha="center", va="bottom", fontsize=6.6, color="#C0392B", fontweight="bold")
for bb, v in zip(b2, xb): ax.text(bb.get_x()+bb.get_width()/2, v, f"{v:.1f}x", ha="center", va="bottom", fontsize=6.6, color="#1e5e38")
ax.legend(loc="upper left", fontsize=9.5, framealpha=0.92)
ax.margins(y=0.22); plt.tight_layout(); plt.savefig(f6, dpi=160); plt.close()
print("charts done")
