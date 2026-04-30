#!/usr/bin/env python3
"""Static paper-quality audit for review-backed low-compute manuscripts.

The verifier uses this script as a lightweight guardrail. It does not judge
scientific truth, but it rejects stub papers that lack the comparison, citation,
and disclosure structure expected from an AI Scientist-v2-style writeup.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path


REQUIRED_SECTIONS = [
    "Introduction",
    "Related Work",
    "Background",
    "Method",
    "Experimental Setup",
    "Comparative Evaluation Plan",
    "Predicted Results",
    "Top-Tier Gap Analysis",
    "Limitations",
    "Conclusion",
]

COMPARISON_TERMS = [
    "YOLOv8",
    "YOLOv7",
    "RT-DETR",
    "Faster R-CNN",
    "Mask R-CNN",
    "DeepCrack",
    "FPHBN",
    "RDD2022",
    "Crack500",
    "CFD",
]

RIGOR_TERMS = [
    "ablation",
    "baseline",
    "bootstrap",
    "confidence interval",
    "effect size",
    "leakage",
    "matched",
    "statistical",
    "hard negative",
    "stop/go",
]

DISCLOSURE_TERMS = [
    "predicted",
    "protocol-estimated",
    "literature-calibrated",
    "forecast",
    "not measured",
    "no new experiments",
    "no model was trained",
    "not executed",
    "hypothesis",
]


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""


def latex_words(text: str) -> int:
    text = re.sub(r"%.*", " ", text)
    text = re.sub(r"\\[a-zA-Z]+\*?(?:\[[^\]]*\])?(?:\{[^{}]*\})?", " ", text)
    return len(re.findall(r"[A-Za-z][A-Za-z0-9-]{2,}", text))


def bib_entries(text: str) -> list[tuple[str, str]]:
    entries: list[tuple[str, str]] = []
    for match in re.finditer(r"@([A-Za-z]+)\s*\{\s*([^,\s]+)", text):
        entries.append((match.group(1).lower(), match.group(2)))
    return entries


def unique_cite_keys(text: str) -> set[str]:
    keys: set[str] = set()
    for match in re.finditer(r"\\cite(?:t|p)?\{([^}]+)\}", text):
        for key in match.group(1).split(","):
            key = key.strip()
            if key:
                keys.add(key)
    return keys


def csv_stats(path: Path) -> tuple[int, set[str], set[str]]:
    try:
        with path.open(newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
    except FileNotFoundError:
        return 0, set(), set()
    methods = {row.get("method", "").strip() for row in rows if row.get("method")}
    metrics = {row.get("metric", "").strip() for row in rows if row.get("metric")}
    return len(rows), methods, metrics


def count_present_terms(text: str, terms: list[str]) -> int:
    lowered = text.lower()
    return sum(1 for term in terms if term.lower() in lowered)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-dir", default=".", help="Application root directory")
    args = parser.parse_args()

    root = Path(args.app_dir)
    tex = read_text(root / "latex" / "template.tex")
    bib = read_text(root / "latex" / "references.bib")
    predicted_csv = root / "predicted_results" / "predicted_results.csv"

    failures: list[str] = []
    warnings: list[str] = []

    words = latex_words(tex)
    if words < 2400:
        failures.append(f"paper is too short for a serious protocol manuscript: {words} words")

    missing_sections = [
        section
        for section in REQUIRED_SECTIONS
        if not re.search(rf"\\section\{{{re.escape(section)}\}}", tex)
    ]
    if missing_sections:
        failures.append("missing required sections: " + ", ".join(missing_sections))

    comparison_count = count_present_terms(tex, COMPARISON_TERMS)
    if comparison_count < 8:
        failures.append(
            f"comparative plan is too thin: found {comparison_count}/"
            f"{len(COMPARISON_TERMS)} expected comparison anchors"
        )

    rigor_count = count_present_terms(tex, RIGOR_TERMS)
    if rigor_count < 8:
        failures.append(
            f"experimental-rigor discussion is too thin: found {rigor_count}/"
            f"{len(RIGOR_TERMS)} rigor anchors"
        )

    disclosure_count = count_present_terms(tex, DISCLOSURE_TERMS)
    if disclosure_count < 5:
        failures.append(
            "prediction-mode disclosure is not repeated enough to prevent "
            "confusion with measured results"
        )

    entries = bib_entries(bib)
    cite_keys = unique_cite_keys(tex)
    if len(entries) < 10:
        failures.append(f"bibliography has too few entries: {len(entries)}")
    if len(cite_keys) < 8:
        failures.append(f"paper cites too few unique references: {len(cite_keys)}")

    entry_texts = re.split(r"\n@", "\n" + bib)
    grounded_entries = 0
    for entry in entry_texts:
        if re.search(r"\b(doi|url|arxiv|booktitle|journal)\s*=", entry, re.I):
            grounded_entries += 1
    if entries and grounded_entries < len(entries):
        warnings.append(
            f"{len(entries) - grounded_entries} bibliography entries lack a venue, DOI, URL, or arXiv field"
        )

    row_count, methods, metrics = csv_stats(predicted_csv)
    if row_count < 10:
        failures.append(f"predicted_results.csv has too few comparison rows: {row_count}")
    if len(methods) < 5:
        failures.append(f"predicted_results.csv compares too few methods: {len(methods)}")
    if len(metrics) < 4:
        failures.append(f"predicted_results.csv covers too few metrics: {len(metrics)}")

    if "fake" in tex.lower() or "fabricated" in tex.lower():
        failures.append("paper should not call protocol-estimated values fake; use evidence-status language")

    if "measured" in tex.lower() and not any(
        phrase in tex.lower()
        for phrase in ["not measured", "no measured", "measured result would require"]
    ):
        failures.append("paper mentions measured results without an explicit non-measured disclosure")

    for warning in warnings:
        print(f"WARN: {warning}")
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        return 1

    print(
        "OK: paper quality audit "
        f"(words={words}, bib_entries={len(entries)}, cited_refs={len(cite_keys)}, "
        f"comparison_terms={comparison_count}, rigor_terms={rigor_count}, "
        f"predicted_rows={row_count})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
