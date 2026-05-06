#!/usr/bin/env python3
"""Write provenance records for manuscript figure artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-dir", default=".", help="Application root directory")
    args = parser.parse_args()

    root = Path(args.app_dir)
    fig_dir = root / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)

    known = {
        "system_overview.png": {
            "source": "figures/figure_spec.json rendered by scripts/generate_predicted_figures.py",
            "regeneration": "python3 scripts/generate_predicted_figures.py --app-dir .",
            "evidence_status": "system/protocol design artifact, not measured output",
        },
        "model_architecture.png": {
            "source": "figures/figure_spec.json rendered by scripts/generate_predicted_figures.py",
            "regeneration": "python3 scripts/generate_predicted_figures.py --app-dir .",
            "evidence_status": "model architecture design artifact, not measured output",
        },
        "module_detail.png": {
            "source": "figures/figure_spec.json rendered by scripts/generate_predicted_figures.py",
            "regeneration": "python3 scripts/generate_predicted_figures.py --app-dir .",
            "evidence_status": "module design artifact, not measured output",
        },
        "mechanism_formula_map.png": {
            "source": "figures/figure_spec.json rendered by scripts/generate_predicted_figures.py",
            "regeneration": "python3 scripts/generate_predicted_figures.py --app-dir .",
            "evidence_status": "mechanism/formula artifact, not measured output",
        },
        "protocol_surface_matrix.png": {
            "source": "figures/figure_spec.json rendered by scripts/generate_predicted_figures.py",
            "regeneration": "python3 scripts/generate_predicted_figures.py --app-dir .",
            "evidence_status": "protocol surface artifact, not performance data",
        },
        "predicted_results.png": {
            "source": "predicted_results/predicted_results.csv rendered by scripts/generate_predicted_figures.py",
            "regeneration": "python3 scripts/generate_predicted_figures.py --app-dir .",
            "evidence_status": "planning forecast centers and bands, not measured output",
        },
        "crackyolo_architecture.png": {
            "source": "compatibility alias for figures/model_architecture.png",
            "regeneration": "python3 scripts/generate_predicted_figures.py --app-dir .",
            "evidence_status": "design artifact, not measured output",
        },
        "planned_benchmark_matrix.png": {
            "source": "compatibility alias for figures/protocol_surface_matrix.png",
            "regeneration": "python3 scripts/generate_predicted_figures.py --app-dir .",
            "evidence_status": "ordinal protocol-priority artifact, not performance data",
        },
        "predicted_yolo_crack_results.png": {
            "source": "compatibility alias for figures/predicted_results.png",
            "regeneration": "python3 scripts/generate_predicted_figures.py --app-dir .",
            "evidence_status": "planning forecast centers, not measured output",
        },
        "crackyolo_module_detail.png": {
            "source": "compatibility alias for figures/module_detail.png",
            "regeneration": "python3 scripts/generate_predicted_figures.py --app-dir .",
            "evidence_status": "design artifact, not measured output",
        },
        "crackyolo_mechanism_equations.png": {
            "source": "compatibility alias for figures/mechanism_formula_map.png",
            "regeneration": "python3 scripts/generate_predicted_figures.py --app-dir .",
            "evidence_status": "protocol/formula artifact, not measured output",
        },
    }

    records = []
    figure_suffixes = {".png", ".jpg", ".jpeg", ".pdf", ".svg"}
    for path in sorted(fig_dir.glob("*")):
        if not path.is_file() or path.suffix.lower() not in figure_suffixes:
            continue
        meta = known.get(path.name, {
            "source": "unknown",
            "regeneration": "document before final submission",
            "evidence_status": "unclassified",
        })
        records.append({
            "file": f"figures/{path.name}",
            "sha256": sha256_file(path),
            **meta,
        })

    payload = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "records": records,
    }
    (fig_dir / "figure_provenance.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    lines = ["# Figure Provenance", ""]
    for record in records:
        lines.append(f"## `{record['file']}`")
        lines.append(f"- SHA256: `{record['sha256']}`")
        lines.append(f"- Source: {record['source']}")
        lines.append(f"- Regeneration: `{record['regeneration']}`")
        lines.append(f"- Evidence status: {record['evidence_status']}")
        lines.append("")
    (fig_dir / "README.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote figure provenance for {len(records)} figure(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
