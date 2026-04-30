#!/bin/bash
# Static customer-branch verification that is safe on low-compute machines.

set -euo pipefail

MODE="${CUSTOMER_WORKFLOW_MODE:-review-backed}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

require_text() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if grep -Eiq "$pattern" "$file" 2>/dev/null; then
        echo "  OK: $description"
    else
        echo "  MISSING: $description ($file)" >&2
        exit 1
    fi
}

echo "== Customer branch contract =="
require_text "docs/customer-branches.md" "AI Scientist-v2|AI Scientist-v3" "v2/v3 synthesis is documented"
require_text "README.md" "scripts/verify_customer_workflow.sh" "README points to the static verifier"
if [ "$MODE" = "normal-experiment" ]; then
    require_text "docs/customer-branches.md" "customer-normal-experiment-mode" "normal branch name is documented"
    require_text "docs/customer-branches.md" "full normal run.*results|measured artifacts under .?results" "docs preserve hardware-backed validation boundary"
else
    require_text "docs/customer-branches.md" "customer-review-backed-paper-mode" "review-backed branch name is documented"
    require_text ".claude/CLAUDE.md" "Do not run training|Do not run training, benchmarking" "Claude instructions forbid experiments"
    require_text "harbor-task/instruction.md.template" "must \\*\\*not\\*\\* run training|do not run experiments" "Harbor task forbids experiments"
    require_text "harbor-task/tests/test.sh" "predicted_data_valid" "Harbor verifier checks predicted data"
    require_text "run.sh" "RESEARCH_RUN_MODE=review-backed" "run.sh exports review-backed verifier mode"
    require_text "docs/customer-branches.md" "must not claim that experiments were executed|Do not run training" "docs preserve no-experiment boundary"
fi
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
