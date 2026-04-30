#!/bin/bash
# Test that infrastructure files are consistent.
# Validates the experiment_codebase rename and Code References schema.
#
# Usage: bash tests/test_infrastructure.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

section() { echo ""; echo "=== $1 ==="; }

# ---------------------------------------------------------------------------
section "1. No stale experiment_results references in tracked files"
# ---------------------------------------------------------------------------

# Get list of tracked files that still reference experiment_results
STALE=$(git -C "$REPO_ROOT" grep -l "experiment_results" -- ':!interactive_run/' ':!jobs/' ':!*.md.template.bak' ':!tests/test_infrastructure.sh' 2>/dev/null || true)
if [ -z "$STALE" ]; then
    pass "No tracked files reference experiment_results"
else
    fail "These tracked files still reference experiment_results: $STALE"
fi

# ---------------------------------------------------------------------------
section "2. All infrastructure files reference experiment_codebase"
# ---------------------------------------------------------------------------

REQUIRED_FILES=(
    ".claude/CLAUDE.md"
    "harbor-task/instruction.md.template"
    "harbor-task/environment/Dockerfile.cpu"
    "harbor-task/environment/Dockerfile.gpu"
    "harbor-task/tests/test.sh"
    "local_harbor_agents/patched_claude_code.py"
    "run.sh"
    "scripts/submit_for_review.sh"
    "monitor.py"
    ".gitignore"
)

for f in "${REQUIRED_FILES[@]}"; do
    FULL="$REPO_ROOT/$f"
    if [ ! -f "$FULL" ]; then
        fail "$f does not exist"
        continue
    fi
    if grep -q "experiment_codebase" "$FULL" 2>/dev/null; then
        pass "$f references experiment_codebase"
    else
        fail "$f does NOT reference experiment_codebase"
    fi
done

# ---------------------------------------------------------------------------
section "3. Instruction template has cloning guidance"
# ---------------------------------------------------------------------------

TEMPLATE="$REPO_ROOT/harbor-task/instruction.md.template"

if grep -q "cloned_repos" "$TEMPLATE" 2>/dev/null; then
    pass "Instruction template mentions cloned_repos"
else
    fail "Instruction template missing cloned_repos guidance"
fi

# ---------------------------------------------------------------------------
section "4. Idea JSON files are valid"
# ---------------------------------------------------------------------------

for f in "$REPO_ROOT"/ideas/idea*.json "$REPO_ROOT"/idea*.json; do
    [ -f "$f" ] || continue
    BASENAME=$(basename "$f")
    if python3 -c "import json; json.load(open('$f'))" 2>/dev/null; then
        pass "$BASENAME is valid JSON"
    else
        fail "$BASENAME is INVALID JSON"
    fi
done

# ---------------------------------------------------------------------------
section "5. idea_videoqa_with_tool.json has Code References"
# ---------------------------------------------------------------------------

IDEA_VQA="$REPO_ROOT/ideas/idea_videoqa_with_tool.json"
# Fallback to old location
[ -f "$IDEA_VQA" ] || IDEA_VQA="$REPO_ROOT/idea_videoqa_with_tool.json"

if [ -f "$IDEA_VQA" ]; then
    HAS_CODE_REFS=$(python3 -c "
import json
with open('$IDEA_VQA') as f:
    data = json.load(f)
refs = data.get('Code References', [])
if refs and isinstance(refs, list) and len(refs) > 0:
    ref = refs[0]
    if 'url' in ref:
        print('ok')
    else:
        print('missing_url')
else:
    print('missing')
" 2>/dev/null)

    if [ "$HAS_CODE_REFS" = "ok" ]; then
        pass "idea_videoqa_with_tool.json has valid Code References"
    else
        fail "idea_videoqa_with_tool.json Code References: $HAS_CODE_REFS"
    fi
else
    fail "idea_videoqa_with_tool.json not found"
fi

# ---------------------------------------------------------------------------
section "6. Dockerfile consistency"
# ---------------------------------------------------------------------------

for DF in Dockerfile.cpu Dockerfile.gpu; do
    FULL="$REPO_ROOT/harbor-task/environment/$DF"
    if grep -q "mkdir -p /app/experiment_codebase" "$FULL" 2>/dev/null; then
        pass "$DF creates experiment_codebase directory"
    else
        fail "$DF does NOT create experiment_codebase directory"
    fi
    if grep -q "prev_artifacts/experiment_codebase" "$FULL" 2>/dev/null; then
        pass "$DF copies previous experiment_codebase artifacts"
    else
        fail "$DF does NOT copy previous experiment_codebase artifacts"
    fi
done

# ---------------------------------------------------------------------------
section "7. Artifact sync consistency"
# ---------------------------------------------------------------------------

PATCHED="$REPO_ROOT/local_harbor_agents/patched_claude_code.py"
if grep -q '"experiment_codebase"' "$PATCHED" 2>/dev/null; then
    pass "patched_claude_code.py syncs experiment_codebase"
else
    fail "patched_claude_code.py does NOT sync experiment_codebase"
fi
if grep -q "paper.docx" "$PATCHED" 2>/dev/null && \
   grep -q "manuscript_explanation.md" "$PATCHED" 2>/dev/null && \
   grep -q '"results"' "$PATCHED" 2>/dev/null && \
   grep -q '"configs"' "$PATCHED" 2>/dev/null && \
   grep -q '"manifests"' "$PATCHED" 2>/dev/null && \
   grep -q '"reports"' "$PATCHED" 2>/dev/null && \
   grep -q '"reviews"' "$PATCHED" 2>/dev/null; then
    pass "patched_claude_code.py syncs DOCX, explanation, results, protocol locks, and reviews"
else
    fail "patched_claude_code.py does NOT sync DOCX, explanation, results, protocol locks, and reviews"
fi

PATCHED_CODEX="$REPO_ROOT/local_harbor_agents/patched_codex.py"
if grep -q '"experiment_codebase"' "$PATCHED_CODEX" 2>/dev/null && \
   grep -q "paper.docx" "$PATCHED_CODEX" 2>/dev/null && \
   grep -q "manuscript_explanation.md" "$PATCHED_CODEX" 2>/dev/null && \
   grep -q '"results"' "$PATCHED_CODEX" 2>/dev/null && \
   grep -q '"configs"' "$PATCHED_CODEX" 2>/dev/null && \
   grep -q '"manifests"' "$PATCHED_CODEX" 2>/dev/null && \
   grep -q '"reports"' "$PATCHED_CODEX" 2>/dev/null && \
   grep -q '"reviews"' "$PATCHED_CODEX" 2>/dev/null; then
    pass "patched_codex.py syncs experiment_codebase, DOCX, explanation, results, protocol locks, and reviews"
else
    fail "patched_codex.py does NOT sync experiment_codebase, DOCX, explanation, results, protocol locks, and reviews"
fi

TEST_SH="$REPO_ROOT/harbor-task/tests/test.sh"
if grep -q "experiment_codebase" "$TEST_SH" 2>/dev/null; then
    pass "test.sh checks experiment_codebase"
else
    fail "test.sh does NOT check experiment_codebase"
fi
if grep -q "docx_valid" "$TEST_SH" 2>/dev/null && \
   grep -q "paper_quality_audit" "$TEST_SH" 2>/dev/null && \
   grep -q "write_figure_provenance" "$TEST_SH" 2>/dev/null && \
   grep -q "measured_data_valid" "$TEST_SH" 2>/dev/null && \
   grep -q "review_artifacts_valid" "$TEST_SH" 2>/dev/null; then
    pass "test.sh checks DOCX, measured data, paper-quality audit, figure provenance, and review artifacts"
else
    fail "test.sh does NOT check DOCX, measured data, paper-quality audit, figure provenance, and review artifacts"
fi

SUBMIT="$REPO_ROOT/scripts/submit_for_review.sh"
if grep -q 'experiment_codebase' "$SUBMIT" 2>/dev/null; then
    pass "submit_for_review.sh copies experiment_codebase"
else
    fail "submit_for_review.sh does NOT copy experiment_codebase"
fi
if grep -q "RUN_PAPER_QUALITY_AUDIT" "$SUBMIT" 2>/dev/null && \
   grep -q "GENERATE_MANIFEST_TEMPLATES" "$SUBMIT" 2>/dev/null && \
   grep -q "write_figure_provenance" "$SUBMIT" 2>/dev/null && \
   grep -q "results predicted_results literature configs manifests reports" "$SUBMIT" 2>/dev/null && \
   grep -q "COMPILE_BEFORE_REVIEW" "$SUBMIT" 2>/dev/null && \
   grep -q "current_review_record.md" "$SUBMIT" 2>/dev/null && \
   grep -q "paper.docx" "$SUBMIT" 2>/dev/null; then
    pass "submit_for_review.sh owns manifest templates, figure provenance, evidence snapshots, quality audit, compile gate, current review record, and DOCX snapshot"
else
    fail "submit_for_review.sh missing manifest/figure-provenance/evidence-snapshot/quality/compile/review-record/DOCX workflow"
fi

# ---------------------------------------------------------------------------
section "8. Gemini CLI support"
# ---------------------------------------------------------------------------

PATCHED_GEMINI="$REPO_ROOT/local_harbor_agents/patched_gemini_cli.py"

if [ -f "$PATCHED_GEMINI" ]; then
    pass "patched_gemini_cli.py exists"
else
    fail "patched_gemini_cli.py does not exist"
fi

if grep -q '"experiment_codebase"' "$PATCHED_GEMINI" 2>/dev/null; then
    pass "patched_gemini_cli.py syncs experiment_codebase"
else
    fail "patched_gemini_cli.py does NOT sync experiment_codebase"
fi
if grep -q "paper.docx" "$PATCHED_GEMINI" 2>/dev/null && \
   grep -q "manuscript_explanation.md" "$PATCHED_GEMINI" 2>/dev/null && \
   grep -q '"results"' "$PATCHED_GEMINI" 2>/dev/null && \
   grep -q '"configs"' "$PATCHED_GEMINI" 2>/dev/null && \
   grep -q '"manifests"' "$PATCHED_GEMINI" 2>/dev/null && \
   grep -q '"reports"' "$PATCHED_GEMINI" 2>/dev/null && \
   grep -q '"reviews"' "$PATCHED_GEMINI" 2>/dev/null; then
    pass "patched_gemini_cli.py syncs DOCX, explanation, results, protocol locks, and reviews"
else
    fail "patched_gemini_cli.py does NOT sync DOCX, explanation, results, protocol locks, and reviews"
fi

if grep -q 'gemini_sessions' "$PATCHED_GEMINI" 2>/dev/null; then
    pass "patched_gemini_cli.py syncs gemini_sessions"
else
    fail "patched_gemini_cli.py does NOT sync gemini_sessions"
fi

INIT_PY="$REPO_ROOT/local_harbor_agents/__init__.py"
if grep -q "PatchedClaudeCode" "$INIT_PY" && grep -q "PatchedGeminiCli" "$INIT_PY"; then
    pass "__init__.py exports both PatchedClaudeCode and PatchedGeminiCli"
else
    fail "__init__.py does not export both patched agents"
fi

if grep -q "\-\-agent" "$REPO_ROOT/run.sh" 2>/dev/null; then
    pass "run.sh supports --agent flag"
else
    fail "run.sh does NOT support --agent flag"
fi

if grep -q "RESEARCH_RUN_MODE=full-experiment" "$REPO_ROOT/run.sh" 2>/dev/null; then
    pass "run.sh exports full-experiment verifier mode"
else
    fail "run.sh does NOT export full-experiment verifier mode"
fi

TEMPLATE="$REPO_ROOT/harbor-task/instruction.md.template"
if grep -q "(CLAUDE.md)" "$TEMPLATE" 2>/dev/null; then
    fail "instruction.md.template still has agent-specific (CLAUDE.md) reference"
else
    pass "instruction.md.template is agent-agnostic (no CLAUDE.md parenthetical)"
fi

# ---------------------------------------------------------------------------
section "9. Customer workflow verifier contract"
# ---------------------------------------------------------------------------

VERIFY_SCRIPT="$REPO_ROOT/scripts/verify_customer_workflow.sh"
if [ -x "$VERIFY_SCRIPT" ]; then
    pass "verify_customer_workflow.sh exists and is executable"
else
    fail "verify_customer_workflow.sh missing or not executable"
fi

if grep -q "Customer branch contract" "$VERIFY_SCRIPT" && \
   grep -q "results/measured_results.csv" "$VERIFY_SCRIPT" && \
   grep -q "predicted_data_valid" "$VERIFY_SCRIPT" && \
   grep -q "RESEARCH_RUN_MODE=full-experiment" "$VERIFY_SCRIPT"; then
    pass "verify_customer_workflow.sh checks branch-specific contracts"
else
    fail "verify_customer_workflow.sh does NOT check branch-specific contracts"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "==========================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "==========================================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
else
    exit 0
fi
