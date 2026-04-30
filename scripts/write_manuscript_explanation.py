#!/usr/bin/env python3
"""Write a companion note for review-backed manuscript artifacts.

The note is deliberately separate from the PDF. The paper can keep ordinary
scientific table and figure titles, while this artifact preserves the evidence
chain, replacement checklist, and non-execution status for reviewers or future
experiment runners.
"""

from __future__ import annotations

import argparse
import csv
import re
from collections import Counter
from pathlib import Path
from typing import Optional


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""


def count_words(tex: str) -> int:
    tex = re.sub(r"%.*", " ", tex)
    tex = re.sub(r"\\[a-zA-Z]+\*?(?:\[[^\]]*\])?(?:\{[^{}]*\})?", " ", tex)
    return len(re.findall(r"[A-Za-z][A-Za-z0-9-]{2,}", tex))


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    try:
        with path.open(newline="", encoding="utf-8") as handle:
            return list(csv.DictReader(handle))
    except FileNotFoundError:
        return []


def top_counts(rows: list[dict[str, str]], key: str, limit: Optional[int] = 8) -> str:
    counts = Counter(row.get(key, "").strip() for row in rows if row.get(key, "").strip())
    if not counts:
        return "none"
    items = counts.most_common(limit or len(counts))
    return ", ".join(f"{name} ({count})" for name, count in items)


def bullet_list(values: list[str]) -> str:
    if not values:
        return "- None recorded.\n"
    return "".join(f"- {value}\n" for value in values)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-dir", default=".", help="Application root directory")
    parser.add_argument(
        "--output",
        default=None,
        help="Output markdown path; default: <app-dir>/manuscript_explanation.md",
    )
    args = parser.parse_args()

    root = Path(args.app_dir)
    output = Path(args.output) if args.output else root / "manuscript_explanation.md"

    tex_path = root / "latex" / "template.tex"
    pdf_path = root / "latex" / "template.pdf"
    csv_path = root / "predicted_results" / "predicted_results.csv"
    literature_path = root / "literature" / "literature_matrix.md"

    tex = read_text(tex_path)
    rows = read_csv_rows(csv_path)
    statuses = sorted({row.get("evidence_status", "").strip() for row in rows if row.get("evidence_status")})
    replacement_triggers = sorted(
        {row.get("replacement_trigger", "").strip() for row in rows if row.get("replacement_trigger")}
    )
    calibration_sources = sorted(
        {row.get("calibration_source", "").strip() for row in rows if row.get("calibration_source")}
    )

    sections = re.findall(r"\\section\{([^}]+)\}", tex)
    figure_count = len(re.findall(r"\\includegraphics", tex))
    table_count = len(re.findall(r"\\begin\{table\}", tex))

    note = f"""# Manuscript Companion Explanation

## Purpose

This file accompanies `latex/template.pdf`. The PDF is intentionally formatted as
a serious conference-style manuscript so the visual effect, table density,
figures, citations, and reviewer flow can be tested. It is not a record of a
completed training or benchmark run.

## Evidence Status

- Paper source: `{tex_path.relative_to(root)}` ({count_words(tex)} approximate words)
- PDF artifact: `{pdf_path.relative_to(root)}` ({'present' if pdf_path.exists() else 'missing'})
- Prediction CSV: `{csv_path.relative_to(root)}` ({len(rows)} data rows plus one header row)
- Literature matrix: `{literature_path.relative_to(root)}` ({'present' if literature_path.exists() else 'missing'})
- Figure provenance: `figures/figure_provenance.json` ({'present' if (root / 'figures' / 'figure_provenance.json').exists() else 'missing'})
- Manuscript sections: {', '.join(sections) if sections else 'none detected'}
- Figures referenced in paper: {figure_count}
- Tables referenced in paper: {table_count}

The main manuscript may use normal table names such as "Comparison on
road-crack benchmarks" for layout realism, but the underlying result rows remain
review-backed forecasts until a real benchmark replaces them. Any `+/-` ranges
in the paper are planning tolerances for future runs, not measured variance,
confidence intervals, or seed statistics. In the current manuscript table, these
are shown as planning ranges rather than `+/-` error bars.

The contribution should be read primarily as a pre-registered protocol and
falsifiable evaluation contract. The proposed detector architecture reuses known
model-family ingredients; the unproven question is whether this particular
combination improves the target metric under locked manifests, matched budgets,
hard-negative auditing, and deployment constraints.

## Forecast Data Chain

- Evidence-status labels found in the CSV: {', '.join(statuses) if statuses else 'none'}
- Methods represented: {top_counts(rows, 'method', None)}
- Metrics represented: {top_counts(rows, 'metric', None)}
- Dataset buckets represented: {top_counts(rows, 'dataset_bucket', None)}
- Calibration sources represented: {len(calibration_sources)}

## Replacement Triggers

Future experiment execution should overwrite the forecast CSV and regenerate the
paper when these triggers are satisfied:

{bullet_list(replacement_triggers)}
## Reader Guidance

- Treat the PDF as a manuscript-quality effect test and protocol draft.
- Treat `predicted_results/predicted_results.csv` as the machine-readable source
  for current comparison values.
- Treat `literature/literature_matrix.md` as the citation-to-claim map.
- Treat `experiment_review.md`, `preflight_repair.md`, and
  `revised_experiment_protocol.md` as the gate and repair chain.
- Do not cite the current values as measured results. They become empirical
  results only after training, evaluation, seed analysis, and figure
  regeneration are completed.
"""

    output.write_text(note, encoding="utf-8")
    print(f"Wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
