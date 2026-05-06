from pathlib import Path
import importlib.util
import json
import sys
import tempfile


def load_module(module_name: str, relative_path: str):
    repo_root = Path(__file__).resolve().parents[1]
    module_path = repo_root / relative_path
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def valid_generic_figure_spec() -> dict:
    return {
        "paper_type": "detector_protocol",
        "contribution_claim": "A review-backed low-compute detector protocol with conservative forecast evidence.",
        "system_overview": {
            "nodes": [
                {"id": "task", "label": "Task claim"},
                {"id": "proposal", "label": "Candidate model"},
                {"id": "review", "label": "Strict review gate"},
                {"id": "protocol", "label": "Protocol lock"},
                {"id": "forecast", "label": "Forecast surfaces"},
                {"id": "future", "label": "Future measured run"},
            ],
            "edges": [
                {"source": "task", "target": "proposal"},
                {"source": "proposal", "target": "review"},
                {"source": "review", "target": "protocol"},
                {"source": "protocol", "target": "forecast"},
                {"source": "forecast", "target": "future"},
            ],
        },
        "model_architecture": {
            "lanes": [
                {
                    "id": "input",
                    "label": "Inputs and scales",
                    "nodes": [
                        {"id": "image", "label": "Image"},
                        {"id": "p3", "label": "P3 fine"},
                        {"id": "p4", "label": "P4 mid"},
                    ],
                },
                {
                    "id": "backbone",
                    "label": "Backbone and context",
                    "nodes": [
                        {"id": "stem", "label": "Stem"},
                        {"id": "encoder", "label": "Context encoder"},
                        {"id": "neck", "label": "Multi-scale neck"},
                    ],
                },
                {
                    "id": "module",
                    "label": "Proposed mechanism",
                    "nodes": [
                        {"id": "align", "label": "Scale align"},
                        {"id": "attention", "label": "Elongation attention"},
                        {"id": "fusion", "label": "Crack-aware fusion"},
                    ],
                },
                {
                    "id": "heads",
                    "label": "Heads and protocol",
                    "nodes": [
                        {"id": "detect", "label": "Detection head"},
                        {"id": "thin", "label": "Thin-structure head"},
                        {"id": "gate", "label": "Evaluation protocol gate", "role": "protocol_gate"},
                    ],
                },
            ],
            "edges": [
                {"source": "image", "target": "stem"},
                {"source": "stem", "target": "p3"},
                {"source": "stem", "target": "p4"},
                {"source": "p3", "target": "encoder"},
                {"source": "p4", "target": "encoder"},
                {"source": "encoder", "target": "neck"},
                {"source": "neck", "target": "align"},
                {"source": "align", "target": "attention"},
                {"source": "attention", "target": "fusion"},
                {"source": "fusion", "target": "detect"},
                {"source": "fusion", "target": "thin"},
                {"source": "thin", "target": "gate", "kind": "protocol"},
                {"source": "p3", "target": "fusion", "kind": "skip"},
                {"source": "gate", "target": "attention", "kind": "auxiliary"},
            ],
        },
        "module_detail": {
            "nodes": [
                {"id": "inputs", "label": "P3/P4/P5 input features", "role": "input"},
                {"id": "align", "label": "1x1 scale alignment", "role": "operator"},
                {"id": "pool", "label": "Strip pooling attention", "role": "attention"},
                {"id": "fusion", "label": "Gated feature fusion", "role": "fusion"},
                {"id": "head", "label": "Detection and thin-crack heads", "role": "output_head"},
                {"id": "loss", "label": "Boundary/continuity loss", "role": "loss"},
            ],
            "edges": [
                {"source": "inputs", "target": "align"},
                {"source": "align", "target": "pool"},
                {"source": "pool", "target": "fusion"},
                {"source": "fusion", "target": "head"},
                {"source": "loss", "target": "fusion", "kind": "constraint"},
            ],
        },
        "mechanism_formulas": [
            {"id": "gate", "formula": "G=I[soundness>tau]", "links": ["gate"]},
            {"id": "fusion", "formula": "F=sum_s alpha_s P_s", "links": ["fusion"]},
            {"id": "thin", "formula": "L=L_det+lambda L_boundary", "links": ["loss"]},
            {"id": "forecast", "formula": "m_hat=m_lit+Delta-rho", "links": ["protocol"]},
        ],
        "protocol_surfaces": [
            {"name": "primary detection", "gate": "matched budget"},
            {"name": "thin-crack stress", "gate": "segmentation auxiliary"},
            {"name": "hard negatives", "gate": "taxonomy lock"},
            {"name": "speed check", "gate": "device budget"},
        ],
        "visual_evidence_panels": [
            {"name": "thin longitudinal crack", "role": "protocol exemplar"},
            {"name": "sealed joint confusion", "role": "hard negative"},
            {"name": "shadow edge", "role": "failure mode"},
        ],
    }


def write_valid_figure_spec(root: Path) -> None:
    figure_dir = root / "figures"
    figure_dir.mkdir(parents=True, exist_ok=True)
    (figure_dir / "figure_spec.json").write_text(
        json.dumps(valid_generic_figure_spec(), indent=2) + "\n",
        encoding="utf-8",
    )


def figure_stack_tex() -> str:
    return r"""
    \includegraphics{system_overview.png}
    \includegraphics{model_architecture.png}
    \includegraphics{module_detail.png}
    \includegraphics{mechanism_formula_map.png}
    \includegraphics{protocol_surface_matrix.png}
    \includegraphics{predicted_results.png}
    """


def test_manifest_schema_includes_dataset_version_column():
    module = load_module("create_manifest_templates", "scripts/create_manifest_templates.py")

    assert "dataset_version" in module.MANIFEST_SCHEMA


def test_companion_counts_table_and_table_star():
    module = load_module("write_manuscript_explanation", "scripts/write_manuscript_explanation.py")

    with tempfile.TemporaryDirectory() as tmpdir:
        root = Path(tmpdir)
        (root / "latex").mkdir()
        (root / "predicted_results").mkdir()
        (root / "literature").mkdir()
        (root / "figures").mkdir()

        (root / "latex" / "template.tex").write_text(
            r"""
            \section{Introduction}
            \begin{table}
            body
            \end{table}
            \begin{table*}
            body
            \end{table*}
            """,
            encoding="utf-8",
        )
        (root / "predicted_results" / "predicted_results.csv").write_text(
            "method,metric,dataset_bucket,evidence_status,calibration_source,replacement_trigger\n"
            "A,mAP,D,protocol-estimated,source,trigger\n",
            encoding="utf-8",
        )
        (root / "literature" / "literature_matrix.md").write_text("matrix", encoding="utf-8")

        output = root / "manuscript_explanation.md"
        import sys

        argv = sys.argv
        try:
            sys.argv = ["write_manuscript_explanation.py", "--app-dir", str(root), "--output", str(output)]
            module.main()
        finally:
            sys.argv = argv

        note = output.read_text(encoding="utf-8")
        assert "Tables referenced in paper: 2" in note


def test_audit_rejects_crack500_primary_without_protocol_declaration():
    module = load_module("audit_paper_quality", "scripts/audit_paper_quality.py")

    protocol = "Primary detection is RDD2022. Crack500 is an auxiliary segmentation stress test."
    fieldnames = module.REQUIRED_FORECAST_COLUMNS
    rows = [
        {
            "scenario": "bad",
            "dataset_bucket": "Crack500 detection subset",
            "protocol_surface": "primary detection",
            "comparison_role": "primary",
            "method": "YOLOv8s baseline",
            "metric": "mAP50-95",
            "predicted_value": "0.51",
            "uncertainty": "0.03",
            "assumption": "literature",
            "rationale": "planning",
            "evidence_status": "protocol-estimated",
            "calibration_source": "paper",
            "replacement_trigger": "empirical run",
        }
    ]

    failures = module.forecast_surface_failures(protocol, rows, fieldnames)

    assert any("Crack500 appears as a primary detection surface" in failure for failure in failures)


def test_audit_requires_rich_figure_set_and_display_formulas():
    module = load_module("audit_paper_quality", "scripts/audit_paper_quality.py")

    sparse_tex = r"""
    \begin{equation} a=b \end{equation}
    \includegraphics{predicted_yolo_crack_results.png}
    """

    failures = module.generated_figure_failures(sparse_tex)

    assert module.display_formula_count(sparse_tex) == 1
    assert any("too few generated figures" in failure for failure in failures)
    assert any("architecture" in failure for failure in failures)


def test_audit_accepts_required_figure_reference_categories():
    module = load_module("audit_paper_quality", "scripts/audit_paper_quality.py")

    rich_tex = r"""
    \includegraphics{crackyolo_architecture.png}
    \includegraphics{crackyolo_module_detail.png}
    \includegraphics{crackyolo_mechanism_equations.png}
    \includegraphics{predicted_yolo_crack_results.png}
    \includegraphics{planned_benchmark_matrix.png}
    """

    assert module.generated_figure_failures(rich_tex) == []


def test_audit_requires_figure_spec_for_visual_stack():
    module = load_module("audit_paper_quality", "scripts/audit_paper_quality.py")

    with tempfile.TemporaryDirectory() as tmpdir:
        root = Path(tmpdir)
        (root / "figures").mkdir()

        failures = module.figure_spec_failures(root, figure_stack_tex())

    assert any("figures/figure_spec.json is required" in failure for failure in failures)


def test_audit_rejects_simple_box_chain_figure_spec():
    module = load_module("audit_paper_quality", "scripts/audit_paper_quality.py")

    simple_spec = {
        "paper_type": "detector_protocol",
        "contribution_claim": "A simple detector idea.",
        "system_overview": {"nodes": [{"id": "input"}, {"id": "output"}]},
        "model_architecture": {
            "lanes": [
                {
                    "id": "main",
                    "nodes": [
                        {"id": "input", "label": "input"},
                        {"id": "module", "label": "module"},
                        {"id": "output", "label": "output"},
                    ],
                }
            ],
            "edges": [
                {"source": "input", "target": "module"},
                {"source": "module", "target": "output"},
            ],
        },
        "module_detail": {
            "nodes": [
                {"id": "input", "label": "input"},
                {"id": "module", "label": "module"},
                {"id": "output", "label": "output"},
            ],
            "edges": [
                {"source": "input", "target": "module"},
                {"source": "module", "target": "output"},
            ],
        },
        "mechanism_formulas": [{"id": "x", "formula": "x=y"}],
        "protocol_surfaces": [{"name": "primary"}],
        "visual_evidence_panels": [{"name": "example"}],
    }

    with tempfile.TemporaryDirectory() as tmpdir:
        root = Path(tmpdir)
        figure_dir = root / "figures"
        figure_dir.mkdir()
        (figure_dir / "figure_spec.json").write_text(
            json.dumps(simple_spec, indent=2) + "\n",
            encoding="utf-8",
        )

        failures = module.figure_spec_failures(root, figure_stack_tex())

    assert any("at least 4 lanes" in failure for failure in failures)
    assert any("at least 10 nodes" in failure for failure in failures)
    assert any("at least 12 edges" in failure for failure in failures)
    assert any("skip or auxiliary" in failure for failure in failures)
    assert any("protocol gate" in failure for failure in failures)
    assert any("mechanism formulas" in failure for failure in failures)


def test_audit_accepts_generic_top_conference_figure_spec():
    module = load_module("audit_paper_quality", "scripts/audit_paper_quality.py")

    with tempfile.TemporaryDirectory() as tmpdir:
        root = Path(tmpdir)
        write_valid_figure_spec(root)
        for name in module.CANONICAL_FIGURE_STACK:
            (root / "figures" / name).write_bytes(b"placeholder")

        failures = module.figure_spec_failures(root, figure_stack_tex())

    assert failures == []


def test_generate_predicted_figures_uses_generic_spec_outputs():
    module = load_module("generate_predicted_figures", "scripts/generate_predicted_figures.py")

    with tempfile.TemporaryDirectory() as tmpdir:
        root = Path(tmpdir)
        write_valid_figure_spec(root)
        (root / "predicted_results").mkdir()
        (root / "predicted_results" / "predicted_results.csv").write_text(
            "method,metric,dataset_bucket,predicted_value,uncertainty\n"
            "Generic baseline,mAP50-95,Primary,0.61,0.03\n"
            "Proposed method,mAP50-95,Primary,0.66,0.025\n"
            "Generic baseline,F1@thin-crack,Thin,0.58,0.04\n"
            "Proposed method,F1@thin-crack,Thin,0.64,0.035\n"
            "Generic baseline,false_positive_per_image,Hard negative,1.20,0.20\n"
            "Proposed method,false_positive_per_image,Hard negative,0.92,0.16\n",
            encoding="utf-8",
        )

        argv = sys.argv
        try:
            sys.argv = ["generate_predicted_figures.py", "--app-dir", str(root)]
            module.main()
        finally:
            sys.argv = argv

        expected = set(module.CANONICAL_FIGURE_STACK) | {
            "crackyolo_architecture.png",
            "crackyolo_module_detail.png",
            "crackyolo_mechanism_equations.png",
            "planned_benchmark_matrix.png",
            "predicted_yolo_crack_results.png",
        }
        missing = [name for name in expected if not (root / "figures" / name).exists()]

    assert missing == []


def test_submit_for_review_blocks_figure_generation_failures_by_default():
    repo_root = Path(__file__).resolve().parents[1]
    script = (repo_root / "scripts" / "submit_for_review.sh").read_text(encoding="utf-8")

    assert 'STRICT_FIGURE_GATE="${STRICT_FIGURE_GATE:-1}"' in script
    assert (
        'if [ "$STRICT_FIGURE_GATE" = "1" ]; then\n'
        '        python3 "$BASE_DIR/scripts/generate_predicted_figures.py" --app-dir "$BASE_DIR"'
    ) in script


def test_audit_requires_finalcopy_for_polished_pdf():
    module = load_module("audit_paper_quality", "scripts/audit_paper_quality.py")

    assert module.camera_ready_failures(r"\documentclass{article}") == [
        "paper must enable \\iclrfinalcopy to suppress review line numbers"
    ]
    assert module.camera_ready_failures(r"\iclrfinalcopy") == []
