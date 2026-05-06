#!/usr/bin/env python3
"""Static paper-quality audit for review-backed low-compute manuscripts.

The verifier uses this script as a lightweight guardrail. It does not judge
scientific truth, but it rejects stub papers that lack the comparison, citation,
and disclosure structure expected from an AI Scientist-v2-style writeup.
"""

from __future__ import annotations

import argparse
import csv
import json
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

REQUIRED_FORECAST_COLUMNS = [
    "scenario",
    "dataset_bucket",
    "protocol_surface",
    "comparison_role",
    "method",
    "metric",
    "predicted_value",
    "uncertainty",
    "assumption",
    "rationale",
    "evidence_status",
    "calibration_source",
    "replacement_trigger",
]

KEYWORD_PATTERNS = [
    r"\\keywords\s*\{",
    r"\bKeywords\s*:",
    r"\bKey words\s*:",
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


def csv_rows(path: Path) -> tuple[list[dict[str, str]], list[str]]:
    try:
        with path.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            rows = list(reader)
            return rows, list(reader.fieldnames or [])
    except FileNotFoundError:
        return [], []


def csv_stats(path: Path) -> tuple[int, set[str], set[str], list[dict[str, str]], list[str]]:
    rows, fieldnames = csv_rows(path)
    methods = {row.get("method", "").strip() for row in rows if row.get("method")}
    metrics = {row.get("metric", "").strip() for row in rows if row.get("metric")}
    return len(rows), methods, metrics, rows, fieldnames


def count_present_terms(text: str, terms: list[str]) -> int:
    lowered = text.lower()
    return sum(1 for term in terms if term.lower() in lowered)


def declared_manifests(protocol_text: str) -> list[str]:
    return sorted(set(re.findall(r"manifests/[A-Za-z0-9_.-]+\.csv", protocol_text)))


def manifest_schema_failures(root: Path, protocol_text: str) -> list[str]:
    failures: list[str] = []
    manifest_refs = declared_manifests(protocol_text)
    for manifest_ref in manifest_refs:
        manifest_path = root / manifest_ref
        if not manifest_path.exists():
            failures.append(f"protocol-declared manifest is missing: {manifest_ref}")
            continue
        with manifest_path.open(newline="", encoding="utf-8") as handle:
            header = next(csv.reader(handle), [])
        if "dataset_version" not in header:
            failures.append(f"{manifest_ref} header missing dataset_version")

    lock_path = root / "manifests" / "manifest_lock.json"
    if manifest_refs:
        try:
            lock = json.loads(lock_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            failures.append("manifests/manifest_lock.json missing or invalid")
            return failures
        for entry in lock.get("manifests", []):
            schema = entry.get("schema", [])
            if "dataset_version" not in schema:
                failures.append(f"{entry.get('path', 'manifest')} lock schema missing dataset_version")
    return failures


def forecast_surface_failures(protocol_text: str, rows: list[dict[str, str]], fieldnames: list[str]) -> list[str]:
    failures: list[str] = []
    missing_columns = [name for name in REQUIRED_FORECAST_COLUMNS if name not in fieldnames]
    if missing_columns:
        failures.append("predicted_results.csv missing required columns: " + ", ".join(missing_columns))
        return failures

    combined_protocol = protocol_text.lower()
    if "rdd2022" not in combined_protocol or "crack500" not in combined_protocol:
        return failures

    detection_rows = [row for row in rows if "map" in row.get("metric", "").lower()]
    primary_detection = [
        row
        for row in detection_rows
        if "primary" in (
            row.get("protocol_surface", "") + " " + row.get("comparison_role", "")
        ).lower()
    ]
    if not primary_detection:
        failures.append("predicted_results.csv has no primary detection rows")
        return failures
    if not any("rdd2022" in row.get("dataset_bucket", "").lower() for row in primary_detection):
        failures.append("primary detection surface must include RDD2022 rows")

    protocol_declares_crack500_primary = re.search(
        r"(primary\s+detection[^.\n]{0,120}crack500|crack500[^.\n]{0,120}primary\s+detection)",
        protocol_text,
        re.I,
    )
    if not protocol_declares_crack500_primary:
        crack500_primary = [
            row
            for row in primary_detection
            if "crack500" in row.get("dataset_bucket", "").lower()
        ]
        if crack500_primary:
            failures.append(
                "Crack500 appears as a primary detection surface without an explicit protocol declaration"
            )
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-dir", default=".", help="Application root directory")
    args = parser.parse_args()

    root = Path(args.app_dir)
    tex = read_text(root / "latex" / "template.tex")
    bib = read_text(root / "latex" / "references.bib")
    protocol = read_text(root / "revised_experiment_protocol.md")
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

    if not any(re.search(pattern, tex, re.I) for pattern in KEYWORD_PATTERNS):
        failures.append("paper is missing a keyword line near the abstract")

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

    row_count, methods, metrics, rows, fieldnames = csv_stats(predicted_csv)
    if row_count < 10:
        failures.append(f"predicted_results.csv has too few comparison rows: {row_count}")
    if len(methods) < 5:
        failures.append(f"predicted_results.csv compares too few methods: {len(methods)}")
    if len(metrics) < 4:
        failures.append(f"predicted_results.csv covers too few metrics: {len(metrics)}")
    failures.extend(forecast_surface_failures(protocol, rows, fieldnames))
    failures.extend(manifest_schema_failures(root, protocol))

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
