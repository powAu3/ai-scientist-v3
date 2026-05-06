from pathlib import Path
import importlib.util
import tempfile


def load_module(module_name: str, relative_path: str):
    repo_root = Path(__file__).resolve().parents[1]
    module_path = repo_root / relative_path
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


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


def test_audit_requires_finalcopy_for_polished_pdf():
    module = load_module("audit_paper_quality", "scripts/audit_paper_quality.py")

    assert module.camera_ready_failures(r"\documentclass{article}") == [
        "paper must enable \\iclrfinalcopy to suppress review line numbers"
    ]
    assert module.camera_ready_failures(r"\iclrfinalcopy") == []
