#!/bin/bash
# Static customer-branch verification that is safe on low-compute machines.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CURRENT_BRANCH="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
MODE="${CUSTOMER_WORKFLOW_MODE:-}"

if [ -z "$MODE" ]; then
    case "$CURRENT_BRANCH" in
        *normal-experiment*) MODE="normal-experiment" ;;
        *) MODE="review-backed" ;;
    esac
fi

case "$MODE" in
    review-backed|normal-experiment) ;;
    *)
        echo "Usage: CUSTOMER_WORKFLOW_MODE=review-backed|normal-experiment bash scripts/verify_customer_workflow.sh" >&2
        exit 2
        ;;
esac

cd "$ROOT"

echo "Customer workflow mode: $MODE"
echo "Repository: $ROOT"
echo ""

echo "== Infrastructure tests =="
bash tests/test_infrastructure.sh

echo ""
echo "== run.sh tests =="
bash tests/test_run_sh.sh

echo ""
echo "== patched agent unit tests =="
python3 -m unittest tests.test_patched_agents

echo ""
echo "== shell syntax =="
bash -n \
    run.sh \
    harbor-task/tests/test.sh \
    tests/test_infrastructure.sh \
    tests/test_run_sh.sh \
    scripts/submit_for_review.sh \
    scripts/compile_latex.sh \
    scripts/convert_latex_to_docx.sh \
    scripts/run_claude_style_audit.sh \
    scripts/verify_customer_workflow.sh

echo ""
echo "== Python syntax =="
python3 -m py_compile \
    scripts/audit_paper_quality.py \
    scripts/write_manuscript_explanation.py \
    scripts/push_to_gitlab.py \
    local_harbor_agents/patched_claude_code.py \
    local_harbor_agents/patched_codex.py \
    local_harbor_agents/patched_gemini_cli.py

echo ""
echo "== Whitespace check =="
git diff --check

if [ "$MODE" = "normal-experiment" ]; then
    echo ""
    echo "NOTE: normal-experiment mode still requires a real hardware-backed Harbor run"
    echo "to verify measured artifacts under results/. This static check does not run"
    echo "training, benchmarks, dataset downloads, or ablations."
fi
