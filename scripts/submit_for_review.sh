#!/bin/bash
# Submit a paper for external review and create a versioned snapshot.
#
# Usage: bash scripts/submit_for_review.sh <tex_path> [base_dir]
#   tex_path:  Path to the .tex file to submit
#   base_dir:  Workspace root (default: /app, or parent of scripts/ if not in container)
#
# What this does:
#   1. Generates a review (via external API, Claude Code subagent, or ensemble of 4 reviewers)
#   2. Creates a versioned snapshot in submissions/v{N}_{timestamp}/ containing:
#      - paper.tex, paper.pdf
#      - paper.docx
#      - manuscript_explanation.md
#      - experiment_codebase/
#      - figures/
#      - reviewer_communications/response.md
#      - reviewer_communications/area_chair_gate.md
#   3. Updates submissions/version_log.json
#
# Environment variables:
#   REVIEWER_MODE  — "ensemble" (default) runs 4 diversified reviewers in parallel:
#                      - Comprehensive reviewer (reviewer.md)
#                      - Idea/literature reviewer (idea-reviewer.md)
#                      - Protocol/reproducibility reviewer (code-reviewer.md)
#                      - Figure/caption reviewer (figure-reviewer.md)
#                    "subagent" uses a single reviewer subagent
#                    Each reviewer can run on a different CLI backend (claude, codex, gemini).
#                    "api" uses external reviewer API (works with any runtime)
#   AGENT_TYPE     — "claude-code" or "gemini-cli" (optional, for subagent CLI selection)
#   CODEX_MODEL    — Model for Codex CLI (default: the local Codex CLI default)
#   GEMINI_MODEL   — Model for Gemini CLI (default: auto)
#   FINAL_GATE_REVIEWER — 1 (default) runs a final Claude area-chair gate after reviewer aggregation
#   GENERATE_PREDICTED_FIGURES — 1 (default) refreshes optional planning/static figures when predicted_results.csv exists
#   GENERATE_MANIFEST_TEMPLATES — 1 (default) materializes protocol manifest schemas before review
#   RUN_PAPER_QUALITY_AUDIT — 1 (default) runs the static manuscript/citation/data audit before review
#   RUN_STYLE_AUDIT — 1 (default) runs a Claude manuscript style audit when available
#   COMPILE_BEFORE_REVIEW — 1 (default) compiles PDF and DOCX before review
#
# One call = one versioned review package. LLM calls are limited to configured
# reviewer/style/auditor CLIs; artifact generation is local and deterministic.

set -euo pipefail

TEX_PATH="$1"

if [ -z "$TEX_PATH" ] || [ ! -f "$TEX_PATH" ]; then
    echo "Error: File not found: $TEX_PATH" >&2
    echo "Usage: bash scripts/submit_for_review.sh <tex_path> [base_dir]" >&2
    exit 1
fi

# Determine base directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -n "${2:-}" ]; then
    BASE_DIR="$2"
elif [ -d "/app/latex" ]; then
    BASE_DIR="/app"
else
    BASE_DIR="$(dirname "$SCRIPT_DIR")"
fi

SUBMISSIONS_DIR="$BASE_DIR/submissions"
VERSION_LOG="$SUBMISSIONS_DIR/version_log.json"
EXTRACT_SCRIPT="$BASE_DIR/.claude/skills/review-paper/scripts/extract_and_generate_questions.sh"

mkdir -p "$SUBMISSIONS_DIR"

REVIEWER_MODE="${REVIEWER_MODE:-ensemble}"
REVIEWER_TIMEOUT="${REVIEWER_TIMEOUT:-1800}"  # Per-reviewer timeout in seconds (default: 30 min)
CLAUDE_REVIEWER_MODEL="${CLAUDE_REVIEWER_MODEL:-}"  # Override model for Claude reviewer (e.g. claude-sonnet-4-5-20250929)
FINAL_GATE_REVIEWER="${FINAL_GATE_REVIEWER:-1}"
AREA_CHAIR_RESPONSE="$BASE_DIR/area_chair_gate.md"
MANUSCRIPT_EXPLANATION="$BASE_DIR/manuscript_explanation.md"
PAPER_DOCX="$BASE_DIR/latex/template.docx"
REVIEWS_DIR="$BASE_DIR/reviews"
RUN_STYLE_AUDIT="${RUN_STYLE_AUDIT:-1}"
RUN_PAPER_QUALITY_AUDIT="${RUN_PAPER_QUALITY_AUDIT:-1}"
GENERATE_PREDICTED_FIGURES="${GENERATE_PREDICTED_FIGURES:-1}"
GENERATE_MANIFEST_TEMPLATES="${GENERATE_MANIFEST_TEMPLATES:-1}"
COMPILE_BEFORE_REVIEW="${COMPILE_BEFORE_REVIEW:-1}"
PAPER_QUALITY_AUDIT_LOG="$REVIEWS_DIR/paper_quality_audit.log"

# =============================================================================
# Helper functions (used by both subagent and ensemble modes)
# =============================================================================

# Cross-platform timeout: use GNU timeout (gtimeout on macOS) or fall back
if command -v timeout &>/dev/null; then
    TIMEOUT_CMD="timeout"
elif command -v gtimeout &>/dev/null; then
    TIMEOUT_CMD="gtimeout"
else
    TIMEOUT_CMD=""
fi

run_with_timeout() {
    local secs="$1"; shift
    if [ -n "$TIMEOUT_CMD" ]; then
        "$TIMEOUT_CMD" "$secs" "$@"
    else
        python3 -c 'import subprocess, sys
secs = float(sys.argv[1])
cmd = sys.argv[2:]
try:
    raise SystemExit(subprocess.call(cmd, timeout=secs))
except subprocess.TimeoutExpired:
    print("Timed out after %gs: %s" % (secs, " ".join(cmd)), file=sys.stderr)
    raise SystemExit(124)
' "$secs" "$@"
    fi
}

# Ensure PATH includes common CLI install locations
ensure_cli_path() {
    export PATH="$HOME/.local/bin:$PATH"
    # Source nvm if node-based CLIs aren't on PATH (Harbor installs via nvm)
    if ! command -v node &>/dev/null && [ -f "$HOME/.nvm/nvm.sh" ]; then
        . "$HOME/.nvm/nvm.sh"
    fi
}

# Strip YAML frontmatter from an agent .md file, returning only the body text.
strip_frontmatter() {
    local file="$1"
    local second_marker
    second_marker=$(grep -n "^---$" "$file" | sed -n '2p' | cut -d: -f1)
    if [ -n "$second_marker" ]; then
        tail -n +$((second_marker + 1)) "$file"
    else
        cat "$file"
    fi
}

# Detect available CLI backends. Prints space-separated list padded to 4 entries.
# Always includes "claude"; adds "codex" and "gemini" if their keys + binaries exist.
detect_available_clis() {
    local clis=("claude")

    if { [ -n "${CODEX_API_KEY:-}" ] || [ -n "${OPENAI_API_KEY:-}" ]; } && command -v codex &>/dev/null; then
        clis+=("codex")
    fi

    # Gemini disabled by default — unreliable HeadersTimeout/503 errors
    # (github.com/google-gemini/gemini-cli/issues/18030, #14148, #8475).
    # Re-enable with ENABLE_GEMINI_REVIEWER=1 if the upstream fixes land.
    if [ "${ENABLE_GEMINI_REVIEWER:-0}" = "1" ] && { [ -n "${GEMINI_API_KEY:-}" ] || [ -n "${GOOGLE_API_KEY:-}" ]; } && command -v gemini &>/dev/null; then
        clis+=("gemini")
    fi

    # Pad to 4 with claude
    while [ ${#clis[@]} -lt 4 ]; do
        clis+=("claude")
    done

    echo "${clis[@]}"
}

# Shuffle an array using $RANDOM (portable, no dependency on shuf).
# Usage: SHUFFLED=($(shuffle_array "${ARRAY[@]}"))
shuffle_array() {
    local arr=("$@")
    local i n temp
    n=${#arr[@]}
    for (( i = n - 1; i > 0; i-- )); do
        local j=$(( RANDOM % (i + 1) ))
        temp="${arr[$i]}"
        arr[$i]="${arr[$j]}"
        arr[$j]="$temp"
    done
    echo "${arr[@]}"
}

# Run a single reviewer.
# Arguments: agent_name cli_type output_file stderr_file
# Agent names: "reviewer", "idea-reviewer", "code-reviewer"
run_single_reviewer() {
    local agent_name="$1"
    local cli_type="$2"
    local output_file="$3"
    local stderr_file="$4"

    local agent_prompt_file="$BASE_DIR/.claude/agents/${agent_name}.md"
    if [ ! -f "$agent_prompt_file" ]; then
        echo "Error: Agent prompt not found: $agent_prompt_file" >"$stderr_file"
        return 1
    fi

    local task_prompt="Review the normal empirical research submission. The paper is at latex/template.tex (compiled PDF at latex/template.pdf and Word export at latex/template.docx). Inspect the full workspace: experiment_review.md, review.json, preflight_repair.md, revised_experiment_protocol.md, experiment_codebase/, results/, configs/, manifests/, reports/, manuscript_explanation.md, figures/, literature/, reviews/, submissions/, and latex/. Output the final markdown review immediately using the required headings in your agent prompt; do not describe a plan, wait for more instructions, or emit process notes. Evaluate protocol correctness, measured-result traceability, citations, companion explanation, visual artifacts, and reproducibility."

    cd "$BASE_DIR"

    case "$cli_type" in
        claude)
            # CLAUDECODE="" clears nesting guard
            if [ -n "${CLAUDE_REVIEWER_MODEL:-}" ]; then
                CLAUDECODE="" run_with_timeout "$REVIEWER_TIMEOUT" claude -p \
                    --model "$CLAUDE_REVIEWER_MODEL" \
                    --agent "$agent_name" \
                    --permission-mode bypassPermissions \
                    --output-format text \
                    "$task_prompt" \
                    > "$output_file" 2>"$stderr_file" || true
            else
                CLAUDECODE="" run_with_timeout "$REVIEWER_TIMEOUT" claude -p \
                    --agent "$agent_name" \
                    --permission-mode bypassPermissions \
                    --output-format text \
                    "$task_prompt" \
                    > "$output_file" 2>"$stderr_file" || true
            fi
            ;;
        codex)
            local prompt_file
            prompt_file=$(mktemp)
            strip_frontmatter "$agent_prompt_file" > "$prompt_file"
            printf '\n\n%s\n' "$task_prompt" >> "$prompt_file"

            # Codex CLI reads CODEX_API_KEY (not OPENAI_API_KEY); bridge if needed
            if [ -z "${CODEX_API_KEY:-}" ] && [ -n "${OPENAI_API_KEY:-}" ]; then
                export CODEX_API_KEY="$OPENAI_API_KEY"
            fi

            # Use --dangerously-bypass-approvals-and-sandbox inside containers/sandboxes
            # to avoid Landlock double-sandboxing (container already provides isolation).
            # Detects: Docker (/.dockerenv), LXC/containerd (cgroup), Modal (cgroup /ta-*).
            # Fall back to --full-auto on bare metal.
            local codex_sandbox_flag="--full-auto"
            if [ -f "/.dockerenv" ] || grep -qE 'docker|lxc|containerd|/ta-' /proc/1/cgroup 2>/dev/null; then
                codex_sandbox_flag="--dangerously-bypass-approvals-and-sandbox"
            fi

            if [ -n "${CODEX_MODEL:-}" ]; then
                run_with_timeout "$REVIEWER_TIMEOUT" codex exec \
                    --model "$CODEX_MODEL" \
                    $codex_sandbox_flag \
                    --output-last-message "$output_file" \
                    - < "$prompt_file" 2>"$stderr_file" || true
            else
                run_with_timeout "$REVIEWER_TIMEOUT" codex exec \
                    $codex_sandbox_flag \
                    --output-last-message "$output_file" \
                    - < "$prompt_file" 2>"$stderr_file" || true
            fi
            rm -f "$prompt_file"
            ;;
        gemini)
            local prompt_file raw_json
            prompt_file=$(mktemp)
            raw_json=$(mktemp)
            strip_frontmatter "$agent_prompt_file" > "$prompt_file"
            printf '\n\n%s\n' "$task_prompt" >> "$prompt_file"

            # Retry up to 3 times on Gemini API failures (503, timeout)
            local gemini_attempt=0
            local gemini_max_retries=3
            while [ $gemini_attempt -lt $gemini_max_retries ]; do
                gemini_attempt=$((gemini_attempt + 1))
                > "$raw_json"  # clear previous attempt

                run_with_timeout "$REVIEWER_TIMEOUT" gemini \
                    --approval-mode=yolo \
                    --output-format json \
                    --model "${GEMINI_MODEL:-auto}" \
                    < "$prompt_file" \
                    > "$raw_json" 2>>"$stderr_file" || true

                # Check if we got a valid response
                if [ -s "$raw_json" ] && python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
resp = data.get('response', '')
if data.get('error') or len(resp) < 50:
    sys.exit(1)
" "$raw_json" 2>/dev/null; then
                    break  # success
                fi

                if [ $gemini_attempt -lt $gemini_max_retries ]; then
                    echo "  Gemini attempt $gemini_attempt failed, retrying in 30s..." >&2
                    sleep 30
                fi
            done

            # Parse JSON response
            python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    if data.get('error'):
        print(f'Gemini error: {data[\"error\"]}', file=sys.stderr)
        sys.exit(1)
    with open(sys.argv[2], 'w') as f:
        f.write(data.get('response', ''))
except Exception as e:
    print(f'Warning: failed to parse Gemini JSON: {e}', file=sys.stderr)
    import shutil
    shutil.copy(sys.argv[1], sys.argv[2])
" "$raw_json" "$output_file" 2>>"$stderr_file" || true
            rm -f "$prompt_file" "$raw_json"
            ;;
        *)
            echo "Error: Unknown CLI type: $cli_type" >"$stderr_file"
            return 1
            ;;
    esac

    # Verify output was produced
    if [ ! -s "$output_file" ]; then
        echo "Error: Reviewer produced empty output" >>"$stderr_file"
        return 1
    fi
    return 0
}

review_file_valid() {
    local agent_name="$1"
    local output_file="$2"
    [ -s "$output_file" ] || return 1

    local byte_count
    byte_count=$(wc -c < "$output_file" | tr -d ' ')
    [ "${byte_count:-0}" -ge 600 ] || return 1

    case "$agent_name" in
        reviewer)
            grep -q "### Summary" "$output_file" && grep -q "### Scores" "$output_file"
            ;;
        idea-reviewer)
            grep -q "### Novelty Assessment" "$output_file" && grep -q "### Overall Verdict" "$output_file"
            ;;
        code-reviewer)
            grep -q "### Protocol Correctness" "$output_file" && grep -q "### Code Quality Score" "$output_file"
            ;;
        figure-reviewer)
            grep -q "### Figure" "$output_file" && grep -q "### Scores" "$output_file"
            ;;
        *)
            return 0
            ;;
    esac
}

run_area_chair_gate() {
    if [ "$FINAL_GATE_REVIEWER" != "1" ]; then
        return 0
    fi

    if ! command -v claude &>/dev/null && [ ! -f "$HOME/.local/bin/claude" ]; then
        echo "Warning: FINAL_GATE_REVIEWER=1 but claude CLI was not found; skipping area-chair gate." >&2
        return 0
    fi

    local gate_prompt
    local raw_hint="reviewer_raw_response.md"
    if [ "$REVIEWER_MODE" = "api" ]; then
        raw_hint="reviewer_raw_response.json"
    fi
    gate_prompt="Run the final top-A-conference area-chair gate for this normal empirical submission. Inspect the current root artifacts: latex/template.tex, latex/template.pdf, latex/template.docx, experiment_review.md, review.json, preflight_repair.md, revised_experiment_protocol.md, experiment_codebase/, results/, configs/, manifests/, reports/, manuscript_explanation.md, figures/, literature/, reviews/current_review_record.md, reviews/top_tier_review.md, reviews/figure_audit.md, and $raw_hint. You are generating the current area-chair gate artifact now, so do not fail the submission because a previous area-chair gate file is absent or stale before this run completes. Treat older submissions/ directories as historical superseded snapshots unless current_review_record.md names one as current. Be extremely strict. If the paper is not ready, route it back to the precise upstream repair artifact."

    cd "$BASE_DIR"
    echo ""
    echo "--- Final area-chair gate ---"
    if [ -n "${CLAUDE_REVIEWER_MODEL:-}" ]; then
        CLAUDECODE="" run_with_timeout "$REVIEWER_TIMEOUT" claude -p \
            --model "$CLAUDE_REVIEWER_MODEL" \
            --agent area-chair \
            --permission-mode bypassPermissions \
            --output-format text \
            "$gate_prompt" \
            > "$AREA_CHAIR_RESPONSE" 2>"$BASE_DIR/area_chair_stderr.log" || true
    else
        CLAUDECODE="" run_with_timeout "$REVIEWER_TIMEOUT" claude -p \
            --agent area-chair \
            --permission-mode bypassPermissions \
            --output-format text \
            "$gate_prompt" \
            > "$AREA_CHAIR_RESPONSE" 2>"$BASE_DIR/area_chair_stderr.log" || true
    fi

    if [ ! -s "$AREA_CHAIR_RESPONSE" ]; then
        echo "Warning: area-chair gate produced no output." >&2
        return 1
    fi
    echo "Area-chair gate complete: $AREA_CHAIR_RESPONSE"
}

# =============================================================================
# Step 1: Generate review(s)
# =============================================================================
echo "=== Submitting paper for review ==="
echo "Paper: $TEX_PATH"
echo "Reviewer mode: $REVIEWER_MODE"

if [ "$REVIEWER_MODE" = "api" ]; then
    RAW_RESPONSE="$BASE_DIR/reviewer_raw_response.json"
else
    RAW_RESPONSE="$BASE_DIR/reviewer_raw_response.md"
fi
ENSEMBLE_ASSIGNMENT_JSON=""  # Set by ensemble mode for version log

rm -f "$BASE_DIR/reviewer_raw_response.json" "$BASE_DIR/reviewer_raw_response.md" \
      "$BASE_DIR"/reviewer_response_*.txt "$BASE_DIR"/reviewer_stderr_*.log \
      "$AREA_CHAIR_RESPONSE" "$BASE_DIR/area_chair_stderr.log"

ensure_cli_path
mkdir -p "$REVIEWS_DIR"
rm -f "$REVIEWS_DIR/top_tier_review.md" "$REVIEWS_DIR/figure_audit.md" \
      "$REVIEWS_DIR/area_chair_gate.md" "$REVIEWS_DIR/review_repair_plan.md" \
      "$REVIEWS_DIR/current_review_record.md" "$REVIEWS_DIR/paper_quality_audit.log" \
      "$REVIEWS_DIR/manuscript_style_audit.md"

if [ "$GENERATE_PREDICTED_FIGURES" = "1" ] && [ -f "$BASE_DIR/scripts/generate_predicted_figures.py" ]; then
    python3 "$BASE_DIR/scripts/generate_predicted_figures.py" --app-dir "$BASE_DIR" >/dev/null 2>&1 || true
fi
if [ -f "$BASE_DIR/scripts/write_figure_provenance.py" ]; then
    python3 "$BASE_DIR/scripts/write_figure_provenance.py" --app-dir "$BASE_DIR" >/dev/null 2>&1 || true
fi

if [ -f "$BASE_DIR/scripts/write_manuscript_explanation.py" ]; then
    python3 "$BASE_DIR/scripts/write_manuscript_explanation.py" --app-dir "$BASE_DIR" >/dev/null 2>&1 || true
fi

if [ "$GENERATE_MANIFEST_TEMPLATES" = "1" ] && [ -f "$BASE_DIR/scripts/create_manifest_templates.py" ]; then
    python3 "$BASE_DIR/scripts/create_manifest_templates.py" --app-dir "$BASE_DIR" >/dev/null 2>&1 || true
fi

if [ "$RUN_PAPER_QUALITY_AUDIT" = "1" ] && [ -f "$BASE_DIR/scripts/audit_paper_quality.py" ]; then
    if ! python3 "$BASE_DIR/scripts/audit_paper_quality.py" --app-dir "$BASE_DIR" > "$PAPER_QUALITY_AUDIT_LOG" 2>&1; then
        cat "$PAPER_QUALITY_AUDIT_LOG" >&2 || true
        echo "Error: static paper-quality audit failed before review. Repair the manuscript, citations, or predicted-results CSV, then rerun." >&2
        exit 1
    fi
fi

if [ "$RUN_STYLE_AUDIT" = "1" ] && [ -f "$BASE_DIR/scripts/run_claude_style_audit.sh" ]; then
    bash "$BASE_DIR/scripts/run_claude_style_audit.sh" "$BASE_DIR" "$BASE_DIR/latex/template.tex" "$BASE_DIR/reviews/style_audit.md" >/dev/null 2>&1 || true
fi

if [ "$COMPILE_BEFORE_REVIEW" = "1" ] && [ -f "$BASE_DIR/scripts/compile_latex.sh" ]; then
    bash "$BASE_DIR/scripts/compile_latex.sh" "$BASE_DIR/latex"
elif [ ! -s "$PAPER_DOCX" ] && [ -f "$BASE_DIR/scripts/convert_latex_to_docx.sh" ]; then
    bash "$BASE_DIR/scripts/convert_latex_to_docx.sh" "$BASE_DIR/latex" >/dev/null 2>&1 || true
fi

if [ "$REVIEWER_MODE" = "ensemble" ]; then
    # =========================================================================
    # ENSEMBLE MODE: Run 4 diversified reviewers in parallel
    # =========================================================================
    echo ""
    echo "--- Ensemble mode: launching 4 reviewers in parallel ---"

    # Agent names for the 4 reviewer roles
    AGENT_NAMES=("reviewer" "idea-reviewer" "code-reviewer" "figure-reviewer")
    AGENT_LABELS=("Comprehensive Reviewer" "Idea & Literature Reviewer" "Protocol & Repro Reviewer" "Figure & Caption Reviewer")

    # Detect and assign CLIs
    AVAILABLE_CLIS=($(detect_available_clis))
    CLIS=($(shuffle_array "${AVAILABLE_CLIS[@]}"))

    echo "Assignments:"
    for i in "${!AGENT_NAMES[@]}"; do
        echo "  ${AGENT_LABELS[$i]} (${AGENT_NAMES[$i]}) → ${CLIS[$i]}"
    done

    # Save assignment JSON for version log
    ENSEMBLE_ASSIGNMENT_JSON=$(AGENT_NAMES_CSV="$(IFS=,; echo "${AGENT_NAMES[*]}")" CLIS_CSV="$(IFS=,; echo "${CLIS[*]}")" python3 -c "
import json, os
names = os.environ['AGENT_NAMES_CSV'].split(',')
clis = os.environ['CLIS_CSV'].split(',')
print(json.dumps(dict(zip(names, clis))))
")

    # Snapshot Claude session files (for trace capture)
    SESSIONS_PROJECT_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/-app"
    PRE_SESSIONS=""
    if [ -d "$SESSIONS_PROJECT_DIR" ]; then
        PRE_SESSIONS=$(find "$SESSIONS_PROJECT_DIR" -name "*.jsonl" 2>/dev/null | sort)
    fi

    # Launch all reviewers in background
    PIDS=()
    REVIEW_FILES=()
    STDERR_FILES=()
    for i in "${!AGENT_NAMES[@]}"; do
        review_file="$BASE_DIR/reviewer_response_$((i+1)).txt"
        stderr_file="$BASE_DIR/reviewer_stderr_$((i+1)).log"
        REVIEW_FILES+=("$review_file")
        STDERR_FILES+=("$stderr_file")

        echo "  Starting ${AGENT_LABELS[$i]} (${CLIS[$i]})..."
        run_single_reviewer "${AGENT_NAMES[$i]}" "${CLIS[$i]}" "$review_file" "$stderr_file" &
        PIDS+=($!)
    done

    echo ""
    echo "All ${#AGENT_NAMES[@]} reviewers launched. Waiting for completion..."

    # Wait and track results (indexed array: RESULT_STATUS[0..2])
    RESULT_STATUS=()
    FAILURES=0
    for i in "${!AGENT_NAMES[@]}"; do
        if wait "${PIDS[$i]}"; then
            if review_file_valid "${AGENT_NAMES[$i]}" "${REVIEW_FILES[$i]}"; then
                RESULT_STATUS+=("success")
                echo "  ✓ ${AGENT_LABELS[$i]} (${CLIS[$i]}) completed successfully"
            else
                echo "  ! ${AGENT_LABELS[$i]} (${CLIS[$i]}) returned incomplete output; retrying once"
                run_single_reviewer "${AGENT_NAMES[$i]}" "${CLIS[$i]}" "${REVIEW_FILES[$i]}" "${STDERR_FILES[$i]}" || true
                if review_file_valid "${AGENT_NAMES[$i]}" "${REVIEW_FILES[$i]}"; then
                    RESULT_STATUS+=("success")
                    echo "  ✓ ${AGENT_LABELS[$i]} (${CLIS[$i]}) completed successfully after retry"
                else
                    RESULT_STATUS+=("failed")
                    FAILURES=$((FAILURES + 1))
                    echo "  ✗ ${AGENT_LABELS[$i]} (${CLIS[$i]}) produced invalid review output"
                fi
            fi
        else
            RESULT_STATUS+=("failed")
            FAILURES=$((FAILURES + 1))
            echo "  ✗ ${AGENT_LABELS[$i]} (${CLIS[$i]}) failed"
        fi
    done

    if [ $FAILURES -eq ${#AGENT_NAMES[@]} ]; then
        echo "Error: All reviewers failed." >&2
        for i in "${!AGENT_NAMES[@]}"; do
            echo "--- stderr from ${AGENT_LABELS[$i]} ---" >&2
            cat "${STDERR_FILES[$i]}" 2>/dev/null >&2 || true
        done
        exit 1
    fi

    echo ""
    echo "Ensemble complete: $((${#AGENT_NAMES[@]} - FAILURES))/${#AGENT_NAMES[@]} reviewers succeeded."

    # Aggregate reviews into RAW_RESPONSE (used as response.md source)
    {
        for i in "${!AGENT_NAMES[@]}"; do
            echo "## Review (${AGENT_LABELS[$i]} — ${CLIS[$i]})"
            echo ""
            if [ "${RESULT_STATUS[$i]}" = "success" ] && [ -s "${REVIEW_FILES[$i]}" ]; then
                cat "${REVIEW_FILES[$i]}"
            else
                echo "[Review not available — ${CLIS[$i]} reviewer failed]"
                if [ -f "${STDERR_FILES[$i]}" ]; then
                    echo ""
                    echo "Error log:"
                    echo '```'
                    tail -20 "${STDERR_FILES[$i]}" 2>/dev/null || true
                    echo '```'
                fi
            fi
            echo ""
            echo ""
        done
    } > "$RAW_RESPONSE"

    # Capture Claude session trace (if any Claude reviewers ran)
    if [ -d "$SESSIONS_PROJECT_DIR" ]; then
        POST_SESSIONS=$(find "$SESSIONS_PROJECT_DIR" -name "*.jsonl" 2>/dev/null | sort)
        NEW_SESSIONS=$(comm -13 <(echo "$PRE_SESSIONS") <(echo "$POST_SESSIONS"))
        if [ -n "$NEW_SESSIONS" ]; then
            REVIEWER_TRACE_DIR="$BASE_DIR/reviewer_trace"
            rm -rf "$REVIEWER_TRACE_DIR"
            mkdir -p "$REVIEWER_TRACE_DIR"
            echo "$NEW_SESSIONS" | while IFS= read -r f; do
                FLAT_NAME=$(echo "$f" | sed "s|$SESSIONS_PROJECT_DIR/||; s|/|__|g")
                cp "$f" "$REVIEWER_TRACE_DIR/$FLAT_NAME"
            done
            echo "Reviewer trace: $(echo "$NEW_SESSIONS" | wc -l | tr -d ' ') session file(s) saved to $REVIEWER_TRACE_DIR/"
        fi
    fi

    # Build ensemble results JSON for version log
    ENSEMBLE_RESULTS_JSON=$(AGENT_NAMES_CSV="$(IFS=,; echo "${AGENT_NAMES[*]}")" RESULTS_CSV="$(IFS=,; echo "${RESULT_STATUS[*]}")" python3 -c "
import json, os
names = os.environ['AGENT_NAMES_CSV'].split(',')
results = os.environ['RESULTS_CSV'].split(',')
print(json.dumps(dict(zip(names, results))))
")

    echo "Ensemble reviewers complete."

elif [ "$REVIEWER_MODE" = "subagent" ]; then
    # =========================================================================
    # SUBAGENT MODE: Single reviewer (existing behavior)
    # =========================================================================
    # Detect which CLI to use: AGENT_TYPE env var, or auto-detect from available commands
    SUBAGENT_CLI="${AGENT_TYPE:-auto}"
    if [ "$SUBAGENT_CLI" = "auto" ]; then
        # Check claude first (more common in this environment)
        if command -v claude &>/dev/null || [ -f "$HOME/.local/bin/claude" ]; then
            SUBAGENT_CLI="claude-code"
        elif command -v codex &>/dev/null; then
            SUBAGENT_CLI="codex"
        elif command -v gemini &>/dev/null; then
            SUBAGENT_CLI="gemini-cli"
        else
            echo "Error: REVIEWER_MODE=subagent requires claude, codex, or gemini CLI." >&2
            exit 1
        fi
    fi

    echo "Invoking reviewer subagent via $SUBAGENT_CLI (this may take several minutes)..."

    if [ "$SUBAGENT_CLI" = "codex" ]; then
        # --- Codex CLI reviewer ---
        REVIEWER_PROMPT_FILE="$BASE_DIR/.claude/agents/reviewer.md"
        if [ ! -f "$REVIEWER_PROMPT_FILE" ]; then
            echo "Error: reviewer prompt not found at $REVIEWER_PROMPT_FILE" >&2
            exit 1
        fi

        REVIEW_PROMPT_FILE=$(mktemp)
        strip_frontmatter "$REVIEWER_PROMPT_FILE" > "$REVIEW_PROMPT_FILE"
        printf '\n\nReview the research submission. The paper is at %s (PDF and DOCX exports should be in latex/). Inspect the full workspace: experiment_review.md, review.json, preflight_repair.md, revised_experiment_protocol.md, experiment_codebase/, results/, configs/, manifests/, reports/, manuscript_explanation.md, figures/, literature/, reviews/, submissions/, and latex/. Output the final markdown review immediately using the required headings; do not emit process notes.\n' "$TEX_PATH" >> "$REVIEW_PROMPT_FILE"

        # Bridge API key if needed
        if [ -z "${CODEX_API_KEY:-}" ] && [ -n "${OPENAI_API_KEY:-}" ]; then
            export CODEX_API_KEY="$OPENAI_API_KEY"
        fi

        codex_sandbox_flag="--full-auto"
        if [ -f "/.dockerenv" ] || grep -qE 'docker|lxc|containerd|/ta-' /proc/1/cgroup 2>/dev/null; then
            codex_sandbox_flag="--dangerously-bypass-approvals-and-sandbox"
        fi

        cd "$BASE_DIR"
        if [ -n "${CODEX_MODEL:-}" ]; then
            run_with_timeout "$REVIEWER_TIMEOUT" codex exec \
                --model "$CODEX_MODEL" \
                $codex_sandbox_flag \
                --output-last-message "$RAW_RESPONSE" \
                - < "$REVIEW_PROMPT_FILE" 2>"$BASE_DIR/reviewer_subagent_stderr.log" || true
        else
            run_with_timeout "$REVIEWER_TIMEOUT" codex exec \
                $codex_sandbox_flag \
                --output-last-message "$RAW_RESPONSE" \
                - < "$REVIEW_PROMPT_FILE" 2>"$BASE_DIR/reviewer_subagent_stderr.log" || true
        fi
        rm -f "$REVIEW_PROMPT_FILE"

        echo "Codex reviewer subagent complete."

    elif [ "$SUBAGENT_CLI" = "gemini-cli" ]; then
        # --- Gemini CLI reviewer ---
        # Read the reviewer prompt from the agent config file
        REVIEWER_PROMPT_FILE="$BASE_DIR/.claude/agents/reviewer.md"
        if [ ! -f "$REVIEWER_PROMPT_FILE" ]; then
            echo "Error: reviewer prompt not found at $REVIEWER_PROMPT_FILE" >&2
            exit 1
        fi
        # Strip the YAML frontmatter (skip everything up to and including the second ---)
        SECOND_MARKER=$(grep -n "^---$" "$REVIEWER_PROMPT_FILE" | sed -n '2p' | cut -d: -f1)
        REVIEWER_SYSTEM_PROMPT=$(tail -n +$((SECOND_MARKER + 1)) "$REVIEWER_PROMPT_FILE")

        # Write the full review prompt to a temp file (too large for shell argument)
        REVIEW_PROMPT_FILE=$(mktemp)
        cat > "$REVIEW_PROMPT_FILE" <<REVIEW_EOF
Review the research submission. The paper is at $TEX_PATH (PDF and DOCX exports should be in latex/). Inspect the full workspace: experiment_review.md, review.json, preflight_repair.md, revised_experiment_protocol.md, experiment_codebase/, results/, configs/, manifests/, reports/, manuscript_explanation.md, figures/, literature/, reviews/, submissions/, and latex/. Output the final markdown review immediately using the required headings; do not emit process notes.

$REVIEWER_SYSTEM_PROMPT
REVIEW_EOF

        # Use --output-format json and extract .response to get clean output
        # without chain-of-thought / tool narration leaking into the review.
        GEMINI_RAW_JSON="$BASE_DIR/reviewer_gemini_raw.json"
        if ! run_with_timeout "$REVIEWER_TIMEOUT" cat "$REVIEW_PROMPT_FILE" | gemini --yolo --output-format json \
            > "$GEMINI_RAW_JSON" 2>"$BASE_DIR/reviewer_subagent_stderr.log"; then
            echo "Warning: Gemini reviewer subagent returned non-zero exit code." >&2
        fi
        # Extract just the response field (final answer, no CoT)
        python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    response = data.get('response', '')
    with open(sys.argv[2], 'w') as f:
        f.write(response)
except Exception as e:
    print(f'Warning: failed to parse Gemini JSON response: {e}', file=sys.stderr)
    # Fallback: copy raw JSON as-is
    import shutil
    shutil.copy(sys.argv[1], sys.argv[2])
" "$GEMINI_RAW_JSON" "$RAW_RESPONSE"
        rm -f "$REVIEW_PROMPT_FILE" "$GEMINI_RAW_JSON"

    else
        # --- Claude Code reviewer ---
        # Snapshot existing session files so we can identify the reviewer's trace afterward.
        SESSIONS_PROJECT_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/-app"
        PRE_SESSIONS=""
        if [ -d "$SESSIONS_PROJECT_DIR" ]; then
            PRE_SESSIONS=$(find "$SESSIONS_PROJECT_DIR" -name "*.jsonl" 2>/dev/null | sort)
        fi

        # CLAUDECODE="" clears the nesting guard so claude can launch from within a running session.
        cd "$BASE_DIR"
        if ! CLAUDECODE="" run_with_timeout "$REVIEWER_TIMEOUT" claude -p \
            --agent reviewer \
            --permission-mode bypassPermissions \
            --output-format text \
            "Review the normal empirical research submission. The paper is at latex/template.tex (compiled PDF at latex/template.pdf and Word export at latex/template.docx). Inspect the full workspace: experiment_review.md, review.json, preflight_repair.md, revised_experiment_protocol.md, experiment_codebase/, results/, configs/, manifests/, reports/, manuscript_explanation.md, figures/, literature/, reviews/, submissions/, and latex/. Output the final markdown review immediately using the required headings; do not describe a plan or emit process notes. Evaluate protocol correctness, measured-result traceability, citations, companion explanation, visual artifacts, and reproducibility." \
            > "$RAW_RESPONSE" 2>"$BASE_DIR/reviewer_subagent_stderr.log"; then
            echo "Warning: Claude reviewer subagent returned non-zero exit code." >&2
        fi

        # Copy the reviewer's session trace (all JSONL files created during the review).
        if [ -d "$SESSIONS_PROJECT_DIR" ]; then
            POST_SESSIONS=$(find "$SESSIONS_PROJECT_DIR" -name "*.jsonl" 2>/dev/null | sort)
            NEW_SESSIONS=$(comm -13 <(echo "$PRE_SESSIONS") <(echo "$POST_SESSIONS"))
            if [ -n "$NEW_SESSIONS" ]; then
                REVIEWER_TRACE_DIR="$BASE_DIR/reviewer_trace"
                rm -rf "$REVIEWER_TRACE_DIR"
                mkdir -p "$REVIEWER_TRACE_DIR"
                echo "$NEW_SESSIONS" | while IFS= read -r f; do
                    FLAT_NAME=$(echo "$f" | sed "s|$SESSIONS_PROJECT_DIR/||; s|/|__|g")
                    cp "$f" "$REVIEWER_TRACE_DIR/$FLAT_NAME"
                done
                echo "Reviewer trace: $(echo "$NEW_SESSIONS" | wc -l) session file(s) saved to $REVIEWER_TRACE_DIR/"
            fi
        fi
    fi

    echo "Reviewer subagent complete."

else
    # =========================================================================
    # API MODE: External reviewer (original behavior)
    # =========================================================================
    if [ ! -f "$EXTRACT_SCRIPT" ]; then
        echo "Error: extract_and_generate_questions.sh not found at $EXTRACT_SCRIPT" >&2
        exit 1
    fi

    echo "Calling external reviewer model (this takes ~30 seconds)..."
    bash "$EXTRACT_SCRIPT" "$TEX_PATH" > "$RAW_RESPONSE"
    echo "External reviewer response received."
fi

mkdir -p "$REVIEWS_DIR"
if [ -s "$RAW_RESPONSE" ]; then
    cp "$RAW_RESPONSE" "$REVIEWS_DIR/top_tier_review.md"
fi
if [ -s "$BASE_DIR/reviewer_response_4.txt" ]; then
    cp "$BASE_DIR/reviewer_response_4.txt" "$REVIEWS_DIR/figure_audit.md"
fi
cat > "$REVIEWS_DIR/current_review_record.md" <<RECORD_EOF
# Current Review Record

- Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Reviewer mode: $REVIEWER_MODE
- Raw reviewer aggregation: $(basename "$RAW_RESPONSE")
- Static paper-quality audit: reviews/paper_quality_audit.log
- Current paper source: latex/template.tex
- Current PDF: latex/template.pdf
- Current DOCX: latex/template.docx
- Current area-chair gate: generated after this record is written

Older directories under \`submissions/\` are historical snapshots and may contain
superseded critiques from earlier manuscript states. The current gate should use
this root review record plus the root manuscript artifacts.
RECORD_EOF

run_area_chair_gate || true

# Keep a stable, top-level review trail for the verifier and for humans who do
# not want to inspect a versioned submission directory first.
mkdir -p "$REVIEWS_DIR"
if [ -s "$RAW_RESPONSE" ]; then
    cp "$RAW_RESPONSE" "$REVIEWS_DIR/top_tier_review.md"
fi
if [ -s "$BASE_DIR/reviewer_response_4.txt" ]; then
    cp "$BASE_DIR/reviewer_response_4.txt" "$REVIEWS_DIR/figure_audit.md"
fi
if [ -s "$AREA_CHAIR_RESPONSE" ]; then
    cp "$AREA_CHAIR_RESPONSE" "$REVIEWS_DIR/area_chair_gate.md"
fi
if [ -s "$REVIEWS_DIR/style_audit.md" ]; then
    cp "$REVIEWS_DIR/style_audit.md" "$REVIEWS_DIR/manuscript_style_audit.md"
fi
if [ -s "$AREA_CHAIR_RESPONSE" ] && grep -Eiq "Repair Before Finish|Reject|route.*back|fatal" "$AREA_CHAIR_RESPONSE"; then
    cat > "$REVIEWS_DIR/review_repair_plan.md" <<REPAIR_EOF
# Review Repair Plan

This file is regenerated when the final area-chair gate identifies blocking
issues. Repair the named upstream artifacts before treating the submission as
ready.

## Latest Gate Signal

\`\`\`text
$(grep -Ei "Decision|Repair Before Finish|Reject|fatal|route.*back|required repair|blocking" "$AREA_CHAIR_RESPONSE" | head -40 || true)
\`\`\`

## Area-Chair Required Repairs

\`\`\`text
$(awk '
  /^## Required Repairs Before Finish/ {capture=1}
  /^## Citation and Positioning Verdict/ {capture=0}
  capture {print}
' "$AREA_CHAIR_RESPONSE" | head -120 || true)
\`\`\`

## Repair Targets

- Manuscript or citations: edit \`latex/template.tex\`,
  \`latex/references.bib\`, and \`literature/literature_matrix.md\`.
- Protocol defects: edit \`preflight_repair.md\` and
  \`revised_experiment_protocol.md\`.
- Figure/table defects: regenerate \`figures/\` and verify captions.
- Evidence-chain defects: regenerate \`manuscript_explanation.md\`,
  \`predicted_results/predicted_results.csv\`, PDF, DOCX, and rerun this review
  script.
- Static figure provenance defects: rerun
  \`python3 scripts/generate_predicted_figures.py --app-dir .\` and
  \`python3 scripts/write_figure_provenance.py --app-dir .\`.
REPAIR_EOF
fi

# =============================================================================
# Step 2: Determine next version number
# =============================================================================
if [ -f "$VERSION_LOG" ]; then
    CURRENT_VERSION=$(python3 -c "
import json
with open('$VERSION_LOG') as f:
    data = json.load(f)
print(data.get('current_version', 0))
")
else
    CURRENT_VERSION=0
fi

NEXT_VERSION=$((CURRENT_VERSION + 1))
TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
VERSION_DIR="$SUBMISSIONS_DIR/v${NEXT_VERSION}_${TIMESTAMP}"

echo ""
echo "=== Creating version snapshot: v${NEXT_VERSION} ==="
echo "v${NEXT_VERSION}_${TIMESTAMP}" > "$SUBMISSIONS_DIR/latest_version.txt"

# =============================================================================
# Step 3: Create versioned snapshot
# =============================================================================
mkdir -p "$VERSION_DIR/reviewer_communications"

# Copy paper
cp "$TEX_PATH" "$VERSION_DIR/paper.tex" 2>/dev/null || true
# Try to find the PDF next to the tex file
TEX_DIR="$(dirname "$TEX_PATH")"
TEX_BASE="$(basename "$TEX_PATH" .tex)"
if [ -f "$TEX_DIR/$TEX_BASE.pdf" ]; then
    cp "$TEX_DIR/$TEX_BASE.pdf" "$VERSION_DIR/paper.pdf"
elif [ -f "$BASE_DIR/latex/template.pdf" ]; then
    cp "$BASE_DIR/latex/template.pdf" "$VERSION_DIR/paper.pdf"
fi
if [ -f "$TEX_DIR/$TEX_BASE.docx" ]; then
    cp "$TEX_DIR/$TEX_BASE.docx" "$VERSION_DIR/paper.docx"
elif [ -f "$PAPER_DOCX" ]; then
    cp "$PAPER_DOCX" "$VERSION_DIR/paper.docx"
fi

# Copy experiment results
if [ -d "$BASE_DIR/experiment_codebase" ]; then
    cp -r "$BASE_DIR/experiment_codebase" "$VERSION_DIR/experiment_codebase"
fi

# Copy figures
if [ -d "$BASE_DIR/figures" ]; then
    cp -r "$BASE_DIR/figures" "$VERSION_DIR/figures"
fi

# Copy the evidence bundle needed to interpret the empirical manuscript.
for artifact_dir in results predicted_results literature configs manifests reports; do
    if [ -d "$BASE_DIR/$artifact_dir" ]; then
        cp -r "$BASE_DIR/$artifact_dir" "$VERSION_DIR/$artifact_dir"
    fi
done

# Save reviewer communications
RESPONSE_FILE="$VERSION_DIR/reviewer_communications/response.md"

if [ "$REVIEWER_MODE" = "ensemble" ]; then
    # Ensemble mode: RAW_RESPONSE is the aggregated markdown with all reviews
    cp "$RAW_RESPONSE" "$RESPONSE_FILE"

    # Copy individual review files
    for i in 1 2 3 4; do
        local_review="$BASE_DIR/reviewer_response_${i}.txt"
        if [ -f "$local_review" ]; then
            cp "$local_review" "$VERSION_DIR/reviewer_communications/"
        fi
    done
    # Copy stderr logs
    for i in 1 2 3 4; do
        local_stderr="$BASE_DIR/reviewer_stderr_${i}.log"
        if [ -f "$local_stderr" ]; then
            cp "$local_stderr" "$VERSION_DIR/reviewer_communications/"
        fi
    done

    # Save ensemble assignment
    echo "$ENSEMBLE_ASSIGNMENT_JSON" > "$VERSION_DIR/reviewer_communications/ensemble_assignment.json"

    # Copy reviewer trace into the versioned snapshot
    if [ -d "$BASE_DIR/reviewer_trace" ]; then
        cp -r "$BASE_DIR/reviewer_trace" "$VERSION_DIR/reviewer_communications/trace"
    fi

elif [ "$REVIEWER_MODE" = "subagent" ]; then
    # Subagent mode: RAW_RESPONSE is plain text (the review)
    cp "$RAW_RESPONSE" "$VERSION_DIR/reviewer_communications/raw_response.txt"
    { echo "## Review"; echo ""; cat "$RAW_RESPONSE"; echo ""; } > "$RESPONSE_FILE"
    # Copy reviewer trace into the versioned snapshot
    if [ -d "$BASE_DIR/reviewer_trace" ]; then
        cp -r "$BASE_DIR/reviewer_trace" "$VERSION_DIR/reviewer_communications/trace"
    fi
else
    # API mode: RAW_RESPONSE is JSON, extract the question
    cp "$RAW_RESPONSE" "$VERSION_DIR/reviewer_communications/raw_response.json"
    python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
with open(sys.argv[2], 'w') as f:
    f.write('## Review\n\n')
    f.write(data.get('question', ''))
    f.write('\n')
" "$RAW_RESPONSE" "$RESPONSE_FILE"
fi

if [ -s "$AREA_CHAIR_RESPONSE" ]; then
    cp "$AREA_CHAIR_RESPONSE" "$VERSION_DIR/reviewer_communications/area_chair_gate.md"
fi
if [ -f "$BASE_DIR/area_chair_stderr.log" ]; then
    cp "$BASE_DIR/area_chair_stderr.log" "$VERSION_DIR/reviewer_communications/"
fi
if [ -s "$MANUSCRIPT_EXPLANATION" ]; then
    cp "$MANUSCRIPT_EXPLANATION" "$VERSION_DIR/manuscript_explanation.md"
fi
if [ -s "$REVIEWS_DIR/style_audit.md" ]; then
    cp "$REVIEWS_DIR/style_audit.md" "$VERSION_DIR/reviewer_communications/style_audit.md"
fi
if [ -s "$PAPER_QUALITY_AUDIT_LOG" ]; then
    cp "$PAPER_QUALITY_AUDIT_LOG" "$VERSION_DIR/reviewer_communications/paper_quality_audit.log"
fi

cat >> "$REVIEWS_DIR/current_review_record.md" <<RECORD_EOF

## Version Snapshot

- Latest version directory: submissions/v${NEXT_VERSION}_${TIMESTAMP}
- Latest reviewer response: submissions/v${NEXT_VERSION}_${TIMESTAMP}/reviewer_communications/response.md
- Latest area-chair gate: submissions/v${NEXT_VERSION}_${TIMESTAMP}/reviewer_communications/area_chair_gate.md
RECORD_EOF

# =============================================================================
# Step 4: Update version log
# =============================================================================
python3 -c "
import json, os

log_path = '$VERSION_LOG'
if os.path.exists(log_path):
    with open(log_path) as f:
        data = json.load(f)
else:
    data = {'versions': [], 'current_version': 0}

version_entry = {
    'version': $NEXT_VERSION,
    'timestamp': '$TIMESTAMP',
    'directory': 'v${NEXT_VERSION}_${TIMESTAMP}',
    'reviewer_mode': '$REVIEWER_MODE',
    'paper_tex': os.path.exists('$VERSION_DIR/paper.tex'),
    'paper_pdf': os.path.exists('$VERSION_DIR/paper.pdf'),
    'paper_docx': os.path.exists('$VERSION_DIR/paper.docx'),
    'has_experiments': os.path.isdir('$VERSION_DIR/experiment_codebase'),
    'has_figures': os.path.isdir('$VERSION_DIR/figures'),
    'has_results': os.path.isdir('$VERSION_DIR/results'),
    'has_predicted_results': os.path.isdir('$VERSION_DIR/predicted_results'),
    'has_literature': os.path.isdir('$VERSION_DIR/literature'),
    'has_protocol_locks': os.path.isdir('$VERSION_DIR/manifests') or os.path.isdir('$VERSION_DIR/configs') or os.path.isdir('$VERSION_DIR/reports'),
    'has_manuscript_explanation': os.path.exists('$VERSION_DIR/manuscript_explanation.md'),
    'has_area_chair_gate': os.path.exists('$VERSION_DIR/reviewer_communications/area_chair_gate.md'),
}

# Ensemble-specific metadata
ensemble_assignment = '''$ENSEMBLE_ASSIGNMENT_JSON'''
if ensemble_assignment.strip():
    try:
        version_entry['ensemble_assignment'] = json.loads(ensemble_assignment)
    except:
        pass

ensemble_results = '''${ENSEMBLE_RESULTS_JSON:-}'''
if ensemble_results.strip():
    try:
        version_entry['ensemble_results'] = json.loads(ensemble_results)
    except:
        pass

# Try to extract a preview from the response
try:
    with open('$VERSION_DIR/reviewer_communications/response.md') as f:
        text = f.read()
    # Strip the '## Review' header and grab the first 200 chars of content
    preview = text.replace('## Review', '', 1).strip()[:200]
    version_entry['reviewer_preview'] = preview
except:
    pass

data['versions'].append(version_entry)
data['current_version'] = $NEXT_VERSION

with open(log_path, 'w') as f:
    json.dump(data, f, indent=2)
"

# =============================================================================
# Step 5: Report
# =============================================================================
echo ""
echo "=== Version v${NEXT_VERSION} snapshot complete ==="
echo "  Directory: $VERSION_DIR"
echo "  Paper:     $([ -f "$VERSION_DIR/paper.tex" ] && echo 'yes' || echo 'no')"
echo "  PDF:       $([ -f "$VERSION_DIR/paper.pdf" ] && echo 'yes' || echo 'no')"
echo "  DOCX:      $([ -f "$VERSION_DIR/paper.docx" ] && echo 'yes' || echo 'no')"
echo "  Experiments: $([ -d "$VERSION_DIR/experiment_codebase" ] && echo 'yes' || echo 'no')"
echo "  Figures:   $([ -d "$VERSION_DIR/figures" ] && echo 'yes' || echo 'no')"
echo "  Explanation: $([ -f "$VERSION_DIR/manuscript_explanation.md" ] && echo 'yes' || echo 'no')"
echo "  Reviewer:  $VERSION_DIR/reviewer_communications/response.md"
if [ "$REVIEWER_MODE" = "ensemble" ]; then
    echo "  Mode:      ensemble (4 reviewers)"
    if [ -f "$VERSION_DIR/reviewer_communications/ensemble_assignment.json" ]; then
        echo "  Assignment: $(cat "$VERSION_DIR/reviewer_communications/ensemble_assignment.json")"
    fi
fi
if [ -d "$VERSION_DIR/reviewer_communications/trace" ]; then
    echo "  Trace:     $VERSION_DIR/reviewer_communications/trace/ ($(ls "$VERSION_DIR/reviewer_communications/trace/" | wc -l) file(s))"
fi
if [ -f "$VERSION_DIR/reviewer_communications/area_chair_gate.md" ]; then
    echo "  AC Gate:   $VERSION_DIR/reviewer_communications/area_chair_gate.md"
fi
echo ""
echo "Read the reviewer's feedback at:"
echo "  $VERSION_DIR/reviewer_communications/response.md"
