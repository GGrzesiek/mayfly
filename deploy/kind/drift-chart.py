"""Renders drift-test.sh results as SVG. Standard library only.

isolated.csv -> strip plot: one row per scenario, a dot per round, a median tick
repeated.csv -> bars: seconds to revert each back-to-back drift

Usage: python drift-chart.py <results.csv> <out.svg>
"""
import csv
import math
import statistics
import sys

ROWS = [
    ("modify", "Edited a managed field"),
    ("delete", "Deleted the Service"),
]

W = 720

# Light values first; the media query swaps in the dark steps of the same hue.
STYLE = """
.surface { fill: #fcfcfb; }
.title { fill: #0b0b0b; font: 600 15px system-ui, sans-serif; }
.label { fill: #52514e; font: 13px system-ui, sans-serif; }
.value { fill: #0b0b0b; font: 600 12px system-ui, sans-serif; }
.grid { stroke: #e4e3df; stroke-width: 1; }
.median { stroke: #0b0b0b; stroke-width: 2; }
.mark { fill: #2a78d6; stroke: #fcfcfb; stroke-width: 2; }
.dot { fill-opacity: 0.8; }
@media (prefers-color-scheme: dark) {
  .surface { fill: #1a1a19; }
  .title, .value { fill: #f0efec; }
  .label { fill: #c3c2b7; }
  .grid { stroke: #3a3a37; }
  .median { stroke: #f0efec; }
  .mark { fill: #3987e5; stroke: #1a1a19; }
}
"""


def load(path):
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    return rows[0]["mode"], rows


def frame(height, title, label):
    return [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{height}" '
        f'viewBox="0 0 {W} {height}" role="img" aria-label="{label}">',
        f"<style>{STYLE}</style>",
        f'<rect class="surface" width="{W}" height="{height}" rx="6"/>',
        f'<text class="title" x="20" y="30">{title}</text>',
    ]


def isolated(rows):
    left, right, top, row_h, bottom = 190, 30, 66, 62, 44
    data = {key: [int(r["revert_ms"]) / 1000 for r in rows if r["scenario"] == key]
            for key, _ in ROWS}
    n = max(len(v) for v in data.values())
    x_max = max(1, math.ceil(max(max(v) for v in data.values()) * 2) / 2)
    step = 0.25 if x_max <= 1 else 0.5 if x_max <= 4 else 1
    plot_w = W - left - right
    height = top + row_h * len(ROWS) + bottom

    def x(sec):
        return left + sec / x_max * plot_w

    out = frame(height, f"Argo CD self-heal: seconds to revert a one-off manual change "
                        f"({n} rounds each, kind)",
                "Seconds Argo CD took to revert each manual change")
    tick = 0.0
    while tick <= x_max + 1e-9:
        tx = x(tick)
        out.append(f'<line class="grid" x1="{tx:.1f}" y1="{top}" '
                   f'x2="{tx:.1f}" y2="{top + row_h * len(ROWS)}"/>')
        out.append(f'<text class="label" x="{tx:.1f}" y="{top + row_h * len(ROWS) + 20}" '
                   f'text-anchor="middle">{tick:g}s</text>')
        tick += step

    for i, (key, label) in enumerate(ROWS):
        values = data[key]
        cy = top + row_h * i + row_h / 2
        out.append(f'<text class="label" x="{left - 14}" y="{cy + 4:.1f}" '
                   f'text-anchor="end">{label}</text>')
        # Spread dots above and below the row line so equal values stay visible.
        for j, sec in enumerate(values):
            dy = (j % 3 - 1) * 7
            out.append(f'<circle class="mark dot" cx="{x(sec):.1f}" cy="{cy + dy:.1f}" r="5">'
                       f"<title>round {j + 1}: {sec:.2f}s</title></circle>")
        med = statistics.median(values)
        mx = x(med)
        out.append(f'<line class="median" x1="{mx:.1f}" y1="{cy - 15:.1f}" '
                   f'x2="{mx:.1f}" y2="{cy + 15:.1f}"/>')
        out.append(f'<text class="value" x="{mx:.1f}" y="{cy - 21:.1f}" '
                   f'text-anchor="middle">median {med:.1f}s</text>')
    return out


def repeated(rows):
    left, right, top, bottom, plot_h = 60, 30, 58, 44, 200
    values = [int(r["revert_ms"]) / 1000 for r in rows]
    y_max = math.ceil(max(values) / 50) * 50
    plot_w = W - left - right
    slot = plot_w / len(values)
    bar_w = min(48, slot * 0.6)
    height = top + plot_h + bottom

    def y(sec):
        return top + plot_h - sec / y_max * plot_h

    out = frame(height, "Same change made again as soon as it is reverted: "
                        "Argo CD backs off (2s, x3 per attempt)",
                "Seconds Argo CD took to revert each back-to-back manual change")
    for tick in range(0, y_max + 1, 50):
        ty = y(tick)
        out.append(f'<line class="grid" x1="{left}" y1="{ty:.1f}" x2="{W - right}" y2="{ty:.1f}"/>')
        out.append(f'<text class="label" x="{left - 8}" y="{ty + 4:.1f}" '
                   f'text-anchor="end">{tick}s</text>')
    for i, sec in enumerate(values):
        cx = left + slot * i + slot / 2
        top_y = y(sec)
        h = top + plot_h - top_y
        # 4px rounded data end, square at the baseline.
        r = min(4, h / 2, bar_w / 2)
        x0, x1, base = cx - bar_w / 2, cx + bar_w / 2, top + plot_h
        path = (f"M{x0:.1f},{base:.1f} V{top_y + r:.1f} "
                f"Q{x0:.1f},{top_y:.1f} {x0 + r:.1f},{top_y:.1f} H{x1 - r:.1f} "
                f"Q{x1:.1f},{top_y:.1f} {x1:.1f},{top_y + r:.1f} V{base:.1f} Z")
        out.append(f'<path class="mark" d="{path}">'
                   f"<title>attempt {i + 1}: {sec:.2f}s</title></path>")
        out.append(f'<text class="value" x="{cx:.1f}" y="{top_y - 6:.1f}" '
                   f'text-anchor="middle">{sec:.1f}s</text>')
        out.append(f'<text class="label" x="{cx:.1f}" y="{base + 20:.1f}" '
                   f'text-anchor="middle">#{i + 1}</text>')
    return out


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    mode, rows = load(src)
    out = isolated(rows) if mode == "isolated" else repeated(rows)
    out.append("</svg>")
    with open(dst, "w", newline="\n") as f:
        f.write("\n".join(out) + "\n")
