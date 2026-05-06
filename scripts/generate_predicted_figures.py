#!/usr/bin/env python3
"""Generate the manuscript visual evidence stack from workflow artifacts.

This script keeps figure generation inside the repository workflow instead of
relying on one-off notebook or shell snippets. It does not run experiments; it
renders a deterministic figure stack from ``figures/figure_spec.json`` plus the
current protocol-estimated CSV.
"""

from __future__ import annotations

import argparse
import csv
import json
import shutil
import textwrap
from collections import OrderedDict
from pathlib import Path
from typing import Iterable, Optional


CANONICAL_FIGURE_STACK = [
    "system_overview.png",
    "model_architecture.png",
    "module_detail.png",
    "mechanism_formula_map.png",
    "protocol_surface_matrix.png",
    "predicted_results.png",
]

COMPATIBILITY_ALIASES = {
    "model_architecture.png": ["crackyolo_architecture.png"],
    "module_detail.png": ["crackyolo_module_detail.png"],
    "mechanism_formula_map.png": ["crackyolo_mechanism_equations.png"],
    "protocol_surface_matrix.png": ["planned_benchmark_matrix.png"],
    "predicted_results.png": ["predicted_yolo_crack_results.png"],
}

REQUIRED_SPEC_KEYS = [
    "paper_type",
    "contribution_claim",
    "system_overview",
    "model_architecture",
    "module_detail",
    "mechanism_formulas",
    "protocol_surfaces",
    "visual_evidence_panels",
]

PALETTE = {
    "blue": "#d7e8ff",
    "green": "#dff2e2",
    "amber": "#f5ead0",
    "red": "#f5dede",
    "purple": "#e4dff4",
    "gray": "#eef1f5",
    "ink": "#242424",
    "muted": "#5f6670",
    "accent": "#2a6f97",
    "aux": "#7b4fa3",
    "protocol": "#9a6a1f",
}


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def read_figure_spec(root: Path) -> dict:
    spec_path = root / "figures" / "figure_spec.json"
    try:
        spec = json.loads(spec_path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(
            "figures/figure_spec.json is required before figure generation"
        ) from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"figures/figure_spec.json is invalid JSON: {exc}") from exc

    missing = [key for key in REQUIRED_SPEC_KEYS if key not in spec]
    if missing:
        raise SystemExit("figures/figure_spec.json missing keys: " + ", ".join(missing))
    return spec


def uncertainty(value: str) -> float:
    cleaned = value.replace("+-", "").replace("±", "").strip()
    try:
        return float(cleaned)
    except ValueError:
        return 0.0


def numeric_value(row: dict[str, str]) -> Optional[float]:
    try:
        return float(row.get("predicted_value", ""))
    except ValueError:
        return None


def pick(
    rows: list[dict[str, str]],
    metric: str,
    methods: list[str],
    dataset_contains: Optional[str] = None,
) -> list[tuple[str, float, float]]:
    selected: list[tuple[str, float, float]] = []
    for method in methods:
        matches = [
            row
            for row in rows
            if row.get("metric") == metric and row.get("method") == method
        ]
        if dataset_contains:
            matches = [
                row
                for row in matches
                if dataset_contains in row.get("dataset_bucket", "")
            ]
        if not matches:
            continue
        row = matches[0]
        value = numeric_value(row)
        if value is None:
            continue
        selected.append((method, value, uncertainty(row.get("uncertainty", "0"))))
    return selected


def wrap_text(text: object, width: int = 18) -> str:
    value = str(text or "").strip()
    if not value:
        return ""
    return "\n".join(textwrap.wrap(value, width=width, break_long_words=False))


def short_text(text: object, width: int = 34) -> str:
    value = str(text or "").replace("\n", " ").strip()
    return "\n".join(textwrap.wrap(value, width=width, break_long_words=False))


def node_label(node: dict) -> str:
    return str(node.get("label") or node.get("name") or node.get("id") or "node")


def iter_lane_nodes(section: dict) -> Iterable[dict]:
    for lane in section.get("lanes", []):
        for node in lane.get("nodes", []):
            yield node


def get_node(section: dict, node_id: str) -> Optional[dict]:
    for node in iter_lane_nodes(section):
        if node.get("id") == node_id:
            return node
    for node in section.get("nodes", []):
        if node.get("id") == node_id:
            return node
    return None


def add_box(
    ax,
    x: float,
    y: float,
    w: float,
    h: float,
    label: str,
    color: str,
    fontsize: float = 8.4,
    linewidth: float = 1.0,
) -> None:
    import matplotlib.patches as patches

    rect = patches.FancyBboxPatch(
        (x, y),
        w,
        h,
        boxstyle="round,pad=0.035,rounding_size=0.055",
        facecolor=color,
        edgecolor=PALETTE["ink"],
        linewidth=linewidth,
    )
    ax.add_patch(rect)
    ax.text(x + w / 2, y + h / 2, label, ha="center", va="center", fontsize=fontsize)


def add_arrow(
    ax,
    start: tuple[float, float],
    end: tuple[float, float],
    kind: str = "main",
    rad: float = 0.0,
) -> None:
    color = PALETTE["ink"]
    style = "-"
    width = 1.1
    if kind in {"skip", "residual"}:
        color = PALETTE["accent"]
        style = "--"
        width = 1.25
    elif kind in {"aux", "auxiliary"}:
        color = PALETTE["aux"]
        style = ":"
        width = 1.35
    elif kind in {"protocol", "gate", "eval", "evaluation"}:
        color = PALETTE["protocol"]
        style = "-."
        width = 1.3
    ax.annotate(
        "",
        xy=end,
        xytext=start,
        arrowprops={
            "arrowstyle": "->",
            "lw": width,
            "linestyle": style,
            "color": color,
            "connectionstyle": f"arc3,rad={rad}",
            "shrinkA": 6,
            "shrinkB": 6,
        },
    )


def draw_system_overview_figure(plt, spec: dict, output: Path) -> None:
    section = spec.get("system_overview", {})
    nodes = section.get("nodes", [])
    edges = section.get("edges", [])
    if not nodes:
        nodes = [
            {"id": "claim", "label": "Claim"},
            {"id": "model", "label": "Candidate model"},
            {"id": "protocol", "label": "Protocol gate"},
            {"id": "paper", "label": "Manuscript evidence"},
        ]
        edges = [{"source": nodes[i]["id"], "target": nodes[i + 1]["id"]} for i in range(len(nodes) - 1)]

    fig, ax = plt.subplots(figsize=(11.0, 5.6), constrained_layout=True)
    ax.set_xlim(0, 12)
    ax.set_ylim(0, 7)
    ax.axis("off")
    ax.text(0.35, 6.5, "System Overview: Task, Model, Protocol, and Paper Evidence", fontsize=13, weight="bold")
    ax.text(0.35, 6.12, short_text(spec.get("contribution_claim"), 112), fontsize=8.2, color=PALETTE["muted"])

    bands = [
        (0.45, 4.55, "Task and Claim Surface", PALETTE["blue"]),
        (0.45, 2.7, "Model and Repair Flow", PALETTE["green"]),
        (0.45, 0.85, "Protocol, Forecast, and Future Replacement", PALETTE["amber"]),
    ]
    for x, y, label, color in bands:
        ax.add_patch(
            __import__("matplotlib.patches").patches.FancyBboxPatch(
                (x, y),
                11.1,
                1.35,
                boxstyle="round,pad=0.02,rounding_size=0.04",
                facecolor=color,
                edgecolor="#b8bec6",
                linewidth=0.8,
                alpha=0.42,
            )
        )
        ax.text(x + 0.18, y + 1.06, label, fontsize=8.5, weight="bold", color="#31363b")

    centers: dict[str, tuple[float, float]] = {}
    for idx, node in enumerate(nodes[:12]):
        row = idx % 3
        col = idx // 3
        x = 1.1 + col * 2.6
        y = [4.78, 2.93, 1.08][row]
        color = [PALETTE["blue"], PALETTE["green"], PALETTE["amber"]][row]
        add_box(ax, x, y, 1.85, 0.62, wrap_text(node_label(node), 18), color, fontsize=7.7)
        centers[str(node.get("id", f"n{idx}"))] = (x + 0.925, y + 0.31)

    for edge in edges:
        source = centers.get(str(edge.get("source")))
        target = centers.get(str(edge.get("target")))
        if source and target:
            add_arrow(ax, source, target, str(edge.get("kind", "main")), rad=0.05)

    ax.text(
        0.5,
        0.22,
        "The overview binds the task claim, model design, protocol surfaces, forecast artifacts, and future measured replacement path.",
        fontsize=7.8,
        color=PALETTE["muted"],
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=220, bbox_inches="tight")
    plt.close(fig)


def draw_model_architecture_figure(plt, spec: dict, output: Path) -> None:
    section = spec.get("model_architecture", {})
    lanes = section.get("lanes", [])
    edges = section.get("edges", [])

    fig, ax = plt.subplots(figsize=(12.0, 6.4), constrained_layout=True)
    ax.set_xlim(0, 12)
    ax.set_ylim(0, 7.4)
    ax.axis("off")
    ax.text(0.25, 7.02, "Model Architecture and Protocol Branches", fontsize=13, weight="bold")
    ax.text(0.25, 6.66, short_text(spec.get("contribution_claim"), 120), fontsize=8.2, color=PALETTE["muted"])

    lane_count = max(1, len(lanes))
    lane_width = 11.2 / lane_count
    centers: dict[str, tuple[float, float]] = {}
    colors = [PALETTE["blue"], PALETTE["green"], PALETTE["amber"], PALETTE["red"], PALETTE["purple"], PALETTE["gray"]]

    for lane_idx, lane in enumerate(lanes):
        x0 = 0.4 + lane_idx * lane_width
        lane_color = colors[lane_idx % len(colors)]
        ax.add_patch(
            __import__("matplotlib.patches").patches.Rectangle(
                (x0, 0.72),
                lane_width - 0.12,
                5.58,
                facecolor=lane_color,
                edgecolor="#c8cdd2",
                linewidth=0.7,
                alpha=0.28,
            )
        )
        ax.text(x0 + 0.12, 6.08, wrap_text(lane.get("label") or lane.get("id"), 20), fontsize=8.3, weight="bold")
        nodes = lane.get("nodes", [])
        step = 4.72 / max(1, len(nodes))
        for node_idx, node in enumerate(nodes):
            y = 5.35 - node_idx * step
            w = max(1.55, min(2.35, lane_width - 0.42))
            x = x0 + (lane_width - w) / 2 - 0.06
            add_box(ax, x, y, w, 0.58, wrap_text(node_label(node), 19), lane_color, fontsize=7.4)
            centers[str(node.get("id", f"lane{lane_idx}_node{node_idx}"))] = (x + w / 2, y + 0.29)

    for edge_idx, edge in enumerate(edges):
        source = centers.get(str(edge.get("source")))
        target = centers.get(str(edge.get("target")))
        if not source or not target:
            continue
        kind = str(edge.get("kind", "main")).lower()
        rad = 0.0
        if kind in {"skip", "residual", "aux", "auxiliary"}:
            rad = 0.18 if edge_idx % 2 == 0 else -0.18
        elif kind in {"protocol", "gate", "eval", "evaluation"}:
            rad = -0.12
        add_arrow(ax, source, target, kind, rad=rad)

    legend_items = [
        ("main", PALETTE["ink"], "-"),
        ("skip/residual", PALETTE["accent"], "--"),
        ("auxiliary", PALETTE["aux"], ":"),
        ("protocol/eval gate", PALETTE["protocol"], "-."),
    ]
    for idx, (label, color, style) in enumerate(legend_items):
        x = 0.62 + idx * 2.45
        ax.plot([x, x + 0.52], [0.34, 0.34], color=color, linestyle=style, linewidth=1.6)
        ax.text(x + 0.62, 0.29, label, fontsize=7.4, color=PALETTE["muted"])

    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=220, bbox_inches="tight")
    plt.close(fig)


def draw_module_detail_figure(plt, spec: dict, output: Path) -> None:
    section = spec.get("module_detail", {})
    nodes = section.get("nodes", [])
    edges = section.get("edges", [])

    fig, ax = plt.subplots(figsize=(11.2, 6.2), constrained_layout=True)
    ax.set_xlim(0, 12)
    ax.set_ylim(0, 7)
    ax.axis("off")
    ax.text(0.25, 6.52, "Module Detail: Inputs, Operators, Fusion, Heads, and Constraints", fontsize=13, weight="bold")
    ax.text(0.25, 6.16, "A module figure must expose feature inputs, core operators, fusion path, output heads, and loss or protocol constraints.", fontsize=8.1, color=PALETTE["muted"])

    columns = [
        ("input", "Input Features", PALETTE["blue"], 0.5),
        ("operator", "Operators / Attention", PALETTE["amber"], 3.0),
        ("fusion", "Fusion", PALETTE["green"], 5.65),
        ("output", "Heads", PALETTE["red"], 8.0),
        ("constraint", "Loss / Gate", PALETTE["purple"], 9.95),
    ]
    for _, title, color, x in columns:
        ax.text(x, 5.72, title, fontsize=8.2, weight="bold")
        ax.add_patch(
            __import__("matplotlib.patches").patches.Rectangle(
                (x - 0.08, 0.72),
                1.85,
                4.78,
                facecolor=color,
                edgecolor="#d1d5da",
                linewidth=0.6,
                alpha=0.22,
            )
        )

    def column_for(node: dict) -> tuple[float, str]:
        label = (node_label(node) + " " + str(node.get("role", ""))).lower()
        if any(token in label for token in ["fusion", "fuse", "merge"]):
            return 5.65, PALETTE["green"]
        if any(token in label for token in ["loss", "constraint", "gate", "budget", "protocol"]):
            return 9.95, PALETTE["purple"]
        if any(token in label for token in ["head", "output", "predict", "score"]):
            return 8.0, PALETTE["red"]
        if any(token in label for token in ["attention", "operator", "pool", "conv", "align", "probe", "encoder"]):
            return 3.0, PALETTE["amber"]
        return 0.5, PALETTE["blue"]

    by_col: dict[float, list[dict]] = {}
    for node in nodes:
        x, _ = column_for(node)
        by_col.setdefault(x, []).append(node)

    centers: dict[str, tuple[float, float]] = {}
    for x, node_list in by_col.items():
        for idx, node in enumerate(node_list):
            y = 4.95 - idx * (4.0 / max(1, len(node_list)))
            _, color = column_for(node)
            add_box(ax, x, y, 1.55, 0.66, wrap_text(node_label(node), 17), color, fontsize=7.2)
            centers[str(node.get("id", f"{x}_{idx}"))] = (x + 0.775, y + 0.33)

    for edge_idx, edge in enumerate(edges):
        source = centers.get(str(edge.get("source")))
        target = centers.get(str(edge.get("target")))
        if source and target:
            add_arrow(ax, source, target, str(edge.get("kind", "main")).lower(), rad=0.12 if edge_idx % 2 else -0.08)

    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=220, bbox_inches="tight")
    plt.close(fig)


def draw_mechanism_formula_figure(plt, spec: dict, output: Path) -> None:
    formulas = spec.get("mechanism_formulas", [])
    fig_height = max(5.6, 1.0 + len(formulas) * 0.9)
    fig, ax = plt.subplots(figsize=(11.4, fig_height), constrained_layout=True)
    ax.set_xlim(0, 12)
    ax.set_ylim(0, 1.3 + len(formulas) * 0.92)
    ax.axis("off")
    y_top = 1.0 + len(formulas) * 0.92
    ax.text(0.25, y_top, "Mechanism Formula Map", fontsize=13, weight="bold")
    ax.text(0.25, y_top - 0.34, "Formulas are linked to model blocks, review gates, and replacement rules so the diagram carries mechanism-level claims.", fontsize=8.1, color=PALETTE["muted"])

    for idx, item in enumerate(formulas):
        y = y_top - 1.08 - idx * 0.86
        title = item.get("name") or item.get("id") or f"formula {idx + 1}"
        formula = item.get("formula", "")
        links = item.get("links", [])
        note = item.get("note") or item.get("rationale") or "linked mechanism"
        color = [PALETTE["blue"], PALETTE["green"], PALETTE["amber"], PALETTE["purple"]][idx % 4]
        add_box(ax, 0.45, y, 1.85, 0.55, wrap_text(title, 18), color, fontsize=7.1)
        add_arrow(ax, (2.35, y + 0.28), (2.95, y + 0.28))
        ax.text(3.08, y + 0.39, str(formula), fontsize=9.1, family="DejaVu Sans Mono", va="center")
        ax.text(3.08, y + 0.08, "links: " + ", ".join(map(str, links)) + " | " + short_text(note, 70), fontsize=7.2, color=PALETTE["muted"], va="center")

    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=220, bbox_inches="tight")
    plt.close(fig)


def draw_protocol_surface_figure(plt, spec: dict, output: Path) -> None:
    surfaces = spec.get("protocol_surfaces", [])
    panels = spec.get("visual_evidence_panels", [])
    rows = max(len(surfaces), 1)
    fig, ax = plt.subplots(figsize=(11.6, 6.2), constrained_layout=True)
    ax.set_xlim(0, 12)
    ax.set_ylim(0, 7)
    ax.axis("off")
    ax.text(0.25, 6.5, "Protocol Surface Matrix and Visual Evidence Panels", fontsize=13, weight="bold")
    ax.text(0.25, 6.16, "Protocol exemplars, hard-negative taxonomy, manifest hooks, budget checks, and statistics gates are shown as review surfaces.", fontsize=8.1, color=PALETTE["muted"])

    headers = ["surface", "role", "gate", "repair trigger"]
    x_positions = [0.45, 2.65, 4.95, 7.25]
    widths = [2.0, 2.08, 2.08, 2.3]
    for x, width, header in zip(x_positions, widths, headers):
        add_box(ax, x, 5.42, width, 0.42, header, PALETTE["gray"], fontsize=7.3, linewidth=0.8)

    row_height = min(0.72, 4.6 / rows)
    for idx, surface in enumerate(surfaces[:7]):
        y = 5.0 - idx * row_height
        values = [
            surface.get("name") or surface.get("surface") or surface.get("id") or f"surface {idx + 1}",
            surface.get("role") or surface.get("comparison_role") or surface.get("purpose") or "claim surface",
            surface.get("gate") or surface.get("protocol_gate") or surface.get("statistical_gate") or "review gate",
            surface.get("repair_trigger") or surface.get("replacement_trigger") or surface.get("trigger") or "future measured run",
        ]
        for x, width, value in zip(x_positions, widths, values):
            add_box(ax, x, y, width, row_height * 0.76, wrap_text(value, 20), "#ffffff", fontsize=6.8, linewidth=0.65)

    ax.text(9.95, 5.8, "Evidence panels", fontsize=8.2, weight="bold")
    for idx, panel in enumerate(panels[:5]):
        y = 5.1 - idx * 0.86
        label = panel.get("name") or panel.get("label") or f"panel {idx + 1}"
        role = panel.get("role") or panel.get("surface") or panel.get("failure_mode") or "protocol exemplar"
        add_box(ax, 9.72, y, 1.85, 0.58, wrap_text(label, 18), [PALETTE["blue"], PALETTE["amber"], PALETTE["green"], PALETTE["red"], PALETTE["purple"]][idx % 5], fontsize=6.8)
        ax.text(9.82, y - 0.16, short_text(role, 29), fontsize=6.3, color=PALETTE["muted"])

    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=220, bbox_inches="tight")
    plt.close(fig)


def metric_direction(metric: str) -> str:
    lowered = metric.lower()
    if any(token in lowered for token in ["false", "fp/", "latency", "error", "loss", "miss"]):
        return "lower"
    return "higher"


def group_rows_for_chart(rows: list[dict[str, str]]) -> list[tuple[str, list[dict[str, str]]]]:
    grouped: "OrderedDict[str, list[dict[str, str]]]" = OrderedDict()
    for row in rows:
        metric = row.get("metric", "").strip()
        if not metric or numeric_value(row) is None:
            continue
        dataset = row.get("dataset_bucket", "").strip()
        key = f"{metric} | {dataset}" if dataset else metric
        grouped.setdefault(key, []).append(row)
    return list(grouped.items())[:5]


def draw_predicted_results_figure(plt, rows: list[dict[str, str]], output: Path) -> None:
    groups = group_rows_for_chart(rows)
    if not groups:
        raise SystemExit("No numeric predicted rows found for predicted_results.png")

    fig, axes = plt.subplots(2, 3, figsize=(11.2, 6.0), constrained_layout=True)
    flat_axes = axes.ravel()
    colors = ["#4a6fa5", "#2a7f62", "#8a6d3b", "#9a4f4f", "#7b4fa3", "#5c5c5c"]

    for ax, (title, group) in zip(flat_axes, groups):
        group = group[:6]
        labels = [wrap_text(row.get("method", f"method {idx + 1}"), 14) for idx, row in enumerate(group)]
        values = [numeric_value(row) or 0.0 for row in group]
        errors = [uncertainty(row.get("uncertainty", "0")) for row in group]
        xs = list(range(len(group)))
        ax.bar(
            xs,
            values,
            yerr=errors if any(errors) else None,
            color=[colors[idx % len(colors)] for idx in range(len(group))],
            alpha=0.92,
            edgecolor="black",
            linewidth=0.4,
            capsize=2.5,
        )
        metric = title.split("|", 1)[0].strip()
        ax.set_title(short_text(title, 38), fontsize=8.8, fontweight="bold")
        ax.set_ylabel(metric)
        ax.set_xticks(xs)
        ax.set_xticklabels(labels, rotation=32, ha="right")
        ax.grid(axis="y", alpha=0.2, linewidth=0.6)
        direction = metric_direction(metric)
        vals_with_errors = values + [v - e for v, e in zip(values, errors)] + [v + e for v, e in zip(values, errors)]
        lo = min(vals_with_errors)
        hi = max(vals_with_errors)
        spread = max(hi - lo, 0.05)
        lo = max(0.0, lo - spread * 0.18)
        hi = hi + spread * 0.22
        if all(0.0 <= value <= 1.0 for value in values) and "fps" not in metric.lower():
            hi = min(1.0, max(hi, max(values) + 0.04))
        ax.set_ylim(lo, hi)
        ax.text(
            0.98,
            0.92,
            "lower is better" if direction == "lower" else "higher is better",
            transform=ax.transAxes,
            ha="right",
            va="top",
            fontsize=7,
            color=PALETTE["muted"],
        )

    for ax in flat_axes[len(groups):]:
        ax.axis("off")
    flat_axes[-1].axis("off")
    flat_axes[-1].text(
        0.02,
        0.88,
        "Planning bands come from the CSV uncertainty column.\n"
        "Panels are conservative comparison surfaces.\n"
        "No training, benchmark, or leaderboard claim is made here.",
        fontsize=9,
        va="top",
    )
    fig.suptitle("Predicted Results Across Protocol Surfaces", fontsize=12, fontweight="bold")
    output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output, dpi=220, bbox_inches="tight")
    plt.close(fig)


def copy_compatibility_aliases(fig_dir: Path) -> None:
    for canonical, aliases in COMPATIBILITY_ALIASES.items():
        source = fig_dir / canonical
        if not source.exists():
            continue
        for alias in aliases:
            shutil.copyfile(source, fig_dir / alias)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-dir", default=".", help="Application root directory")
    parser.add_argument(
        "--output",
        default=None,
        help="Optional output path for predicted_results.png; aliases still use figures/.",
    )
    args = parser.parse_args()

    root = Path(args.app_dir)
    fig_dir = root / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)
    csv_path = root / "predicted_results" / "predicted_results.csv"

    spec = read_figure_spec(root)
    rows = read_rows(csv_path)
    if not rows:
        raise SystemExit(f"No predicted rows found: {csv_path}")

    try:
        import matplotlib.pyplot as plt
    except Exception as exc:  # pragma: no cover - environment failure path
        raise SystemExit(f"matplotlib is required to generate figures: {exc}") from exc

    plt.rcParams.update(
        {
            "font.size": 8,
            "font.family": "DejaVu Sans",
            "axes.spines.top": False,
            "axes.spines.right": False,
        }
    )

    draw_system_overview_figure(plt, spec, fig_dir / "system_overview.png")
    draw_model_architecture_figure(plt, spec, fig_dir / "model_architecture.png")
    draw_module_detail_figure(plt, spec, fig_dir / "module_detail.png")
    draw_mechanism_formula_figure(plt, spec, fig_dir / "mechanism_formula_map.png")
    draw_protocol_surface_figure(plt, spec, fig_dir / "protocol_surface_matrix.png")

    predicted_output = Path(args.output) if args.output else fig_dir / "predicted_results.png"
    draw_predicted_results_figure(plt, rows, predicted_output)
    if predicted_output != fig_dir / "predicted_results.png":
        shutil.copyfile(predicted_output, fig_dir / "predicted_results.png")

    copy_compatibility_aliases(fig_dir)
    written = [fig_dir / name for name in CANONICAL_FIGURE_STACK]
    print("Wrote visual evidence stack: " + ", ".join(str(path) for path in written))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
