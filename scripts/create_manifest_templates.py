#!/usr/bin/env python3
"""Create immutable manifest templates declared by a repaired protocol.

Low-compute review-backed runs cannot download datasets or populate real split
rows. This script still materializes the manifest contract so reviewers and
future experiment runners can see exactly which files, columns, hashes, and
locking rules must be filled before training.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.metadata
import json
import platform
import re
from datetime import datetime, timezone
from pathlib import Path


MANIFEST_SCHEMA = [
    "image_id",
    "source_dataset",
    "dataset_version",
    "scene_or_route_id",
    "country_or_region",
    "annotation_type",
    "license_note",
    "sha256",
    "perceptual_hash",
    "split",
    "hard_negative_category",
]

COMPUTE_PARITY_SCHEMA = [
    "method",
    "family",
    "input_size",
    "epochs",
    "batch_size",
    "seeds",
    "pilot_trials",
    "gpu_model",
    "gpu_hours_train",
    "gpu_hours_tune",
    "total_images_seen",
    "early_stop_epoch",
    "native_resolution_exception",
    "pretrained_checkpoint",
    "config_sha256",
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def row_count(path: Path) -> int:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle))
    return max(0, len(rows) - 1)


def declared_manifests(protocol_text: str) -> list[str]:
    names = sorted(set(re.findall(r"manifests/[A-Za-z0-9_.-]+\.csv", protocol_text)))
    return names


def write_csv_template(path: Path) -> None:
    if path.exists() and path.stat().st_size > 0:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(MANIFEST_SCHEMA)


def write_readme(manifest_dir: Path, manifest_names: list[str]) -> None:
    bullets = "\n".join(f"- `{name}`" for name in manifest_names)
    readme = f"""# Manifest Lock Templates

These files are schema locks for the repaired experiment protocol. The current
run is low-compute and does not download datasets, train models, or populate
real split rows.

Before any empirical run, replace the zero-row templates with dataset-specific
rows and regenerate `manifest_lock.json`. Every row must preserve this schema:

```text
{",".join(MANIFEST_SCHEMA)}
```

Required manifest files:

{bullets}

Locking rules:

- Exact duplicate SHA256 values may not cross train/validation/test splits.
- Perceptual hashes with Hamming distance below 8 may not cross train/test
  unless a human audit marks the images unrelated.
- Dataset version, license, and annotation type must be recorded per row.
- Real measurements may be reported only after populated manifests are locked.
"""
    (manifest_dir / "README.md").write_text(readme, encoding="utf-8")


def write_environment_lock(root: Path) -> None:
    config_dir = root / "configs"
    config_dir.mkdir(parents=True, exist_ok=True)
    env_lock = config_dir / "environment_lock.yaml"
    if env_lock.exists() and env_lock.stat().st_size > 0:
        existing = env_lock.read_text(encoding="utf-8", errors="ignore")
        if "template_only_until_empirical_run" not in existing:
            return
    def version_or_status(package: str) -> str:
        try:
            return importlib.metadata.version(package)
        except importlib.metadata.PackageNotFoundError:
            return "not_installed_in_low_compute_run"

    env_lock.write_text(
        f"""# Environment lock template for future measured runs.
# The current low-compute manuscript run does not execute training.
status: template_only_until_empirical_run
python: "{platform.python_version()}"
pytorch: "{version_or_status('torch')}"
torchvision: "{version_or_status('torchvision')}"
ultralytics: "{version_or_status('ultralytics')}"
cuda: "not_available_in_low_compute_template"
cudnn: "not_available_in_low_compute_template"
opencv: "{version_or_status('opencv-python')}"
numpy: "{version_or_status('numpy')}"
determinism:
  torch_use_deterministic_algorithms: true
  cudnn_benchmark: false
  seed_sources:
    - python_random
    - numpy
    - torch_cpu
    - torch_cuda
repositories:
  ultralytics: "required_before_training"
  rt_detr_reference: "required_before_training_or_not_used"
  mask_rcnn_reference: "required_before_training_or_torchvision_release"
""",
        encoding="utf-8",
    )


def write_compute_parity(root: Path) -> None:
    report_dir = root / "reports"
    report_dir.mkdir(parents=True, exist_ok=True)
    parity_csv = report_dir / "compute_parity.csv"
    if parity_csv.exists() and parity_csv.stat().st_size > 0:
        if row_count(parity_csv) > 0:
            return
    with parity_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(COMPUTE_PARITY_SCHEMA)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-dir", default=".", help="Application root directory")
    args = parser.parse_args()

    root = Path(args.app_dir)
    protocol_path = root / "revised_experiment_protocol.md"
    protocol_text = protocol_path.read_text(encoding="utf-8") if protocol_path.exists() else ""
    manifests = declared_manifests(protocol_text)
    if not manifests:
        print("No protocol-declared manifests found; nothing to create.")
        return 0

    manifest_dir = root / "manifests"
    manifest_dir.mkdir(parents=True, exist_ok=True)

    for manifest in manifests:
        write_csv_template(root / manifest)

    lock_entries = []
    for manifest in manifests:
        path = root / manifest
        lock_entries.append(
            {
                "path": manifest,
                "sha256": sha256_file(path),
                "rows": row_count(path),
                "schema": MANIFEST_SCHEMA,
                "status": "template_only" if row_count(path) == 0 else "locked",
            }
        )

    lock = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "protocol_file": "revised_experiment_protocol.md",
        "protocol_sha256": sha256_file(protocol_path) if protocol_path.exists() else None,
        "low_compute_status": "template_only_until_datasets_are_downloaded",
        "manifests": lock_entries,
    }
    (manifest_dir / "manifest_lock.json").write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8")
    write_readme(manifest_dir, manifests)
    write_environment_lock(root)
    write_compute_parity(root)
    print(f"Wrote {len(manifests)} manifest template(s) to {manifest_dir}")
    print("Wrote protocol lock templates to configs/environment_lock.yaml and reports/compute_parity.csv")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
