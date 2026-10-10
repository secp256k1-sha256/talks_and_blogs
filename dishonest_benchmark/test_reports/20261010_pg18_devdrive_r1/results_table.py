"""Render the results as table images (charts/results_table*.png)."""
import csv
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
CSV = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "pg18", "results_round1.csv")
SUBTITLE = "PostgreSQL 18.6 on Windows 11, trusted Dev Drive V: (ReFS), pgbench -c 32 -j 8 -T 120, 1 round"

# Summary rows: one bar per technique, best variant only.
SUMMARY_ROWS = [
    "Case 0: bad code / missing index", "Indexed baseline", "synchronous_commit=off",
    "full_page_writes=off", "fsync=off", "checkpoint tuning", "all durability off",
    "less work (drop FK/SELECT/audit)", "UNLOGGED ledger/audit", "stored procedure",
    "stored function (SQL)", "prepared protocol", "sql function + prepared",
    "batching x8", "batching x32", "all cheats + batch x32 (SQL fn)",
]
HIGHLIGHT = {"all cheats + batch x32", "all cheats + mega-batch x1000", "all cheats + batch x32 (SQL fn)"}

HEAD_BG, HEAD_FG = "#1b3a5c", "white"
ZEBRA = ("white", "#f2f5f9")
HL_BG = "#fbe8c8"
GRID = "#c9d1db"


def load(path):
    with open(path, newline="") as f:
        rows = {r["method"]: r for r in csv.DictReader(f)}
    base = float(rows["Indexed baseline"]["ops_per_sec"])
    case0 = float(rows["Case 0: bad code / missing index"]["ops_per_sec"])
    return rows, base, case0


def render(rows, base, case0, order, out, notes):
    header = ["method", "proto", "TPS", "OPS*", "lat ms", "x base", "x Case0"]
    cells, colors = [], []
    for i, m in enumerate(order):
        r = rows[m]
        tps, ops, lat = float(r["tps"]), float(r["ops_per_sec"]), float(r["lat_ms"])
        cells.append([m, r["protocol"], f"{tps:,.0f}", f"{ops:,.0f}", f"{lat:.2f}",
                      f"{ops / base:.2f}x", f"{ops / case0:.1f}x"])
        colors.append(HL_BG if m in HIGHLIGHT else ZEBRA[i % 2])

    widths = [0.335, 0.105, 0.125, 0.13, 0.1, 0.1, 0.105]
    row_h = 0.42
    fig_h = row_h * (len(cells) + 1) + 0.45 * (len(notes) + 1) + 0.5
    fig = plt.figure(figsize=(11, fig_h), dpi=150)
    ax = fig.add_axes([0.015, 0.0, 0.97, 1.0])
    ax.axis("off")
    n = len(cells) + 1
    top = 1 - 0.45 / fig_h
    h = row_h / fig_h
    ax.text(0, top + 0.1 / fig_h, SUBTITLE, fontsize=10.5, color="#333", va="bottom", transform=ax.transAxes)

    for ri in range(n):
        y = top - (ri + 1) * h
        x = 0
        for ci, w in enumerate(widths):
            if ri == 0:
                bg, txt, fg, weight = HEAD_BG, header[ci], HEAD_FG, "bold"
            else:
                bg, txt, fg, weight = colors[ri - 1], cells[ri - 1][ci], "#111", "normal"
            ax.add_patch(plt.Rectangle((x, y), w, h, facecolor=bg, edgecolor=GRID, lw=0.8,
                                       transform=ax.transAxes, clip_on=False))
            right = ri > 0 and ci >= 2
            ax.text(x + (w - 0.008 if right else 0.008), y + h / 2, txt, fontsize=11,
                    ha="right" if right else "left", va="center", color=fg, weight=weight,
                    transform=ax.transAxes)
            x += w

    y = top - n * h - 0.15 / fig_h
    for line in notes:
        ax.text(0.005, y, line, fontsize=10.5, color="#444", va="top", transform=ax.transAxes)
        y -= 0.38 / fig_h
    fig.savefig(out, facecolor="white", bbox_inches="tight", pad_inches=0.15)
    plt.close(fig)
    print("wrote", out)


def main():
    rows, base, case0 = load(CSV)
    notes = ["* OPS = operations/second for batched methods, TPS otherwise. x base = vs indexed baseline; x Case0 = vs the crippled Case 0.",
             "Highlighted rows stack every cheat at once.",
             "Dev Drive with Defender performance mode keeps real-time scanning out of the commit path (scans run asynchronously)."]
    render(rows, base, case0, SUMMARY_ROWS, os.path.join(HERE, "charts", "results_table.png"), notes)

    with open(CSV, newline="") as f:
        all_order = [r["method"] for r in sorted(csv.DictReader(f), key=lambda r: int(r["idx"]))]
    mega = rows.get("all cheats + mega-batch x1000")
    extra = notes + (["Mega-batch x1000 deadlocks by design: failed transactions are excluded from its TPS."] if mega else [])
    render(rows, base, case0, all_order, os.path.join(HERE, "charts", "results_table_all20.png"), extra)


if __name__ == "__main__":
    main()
