#!/bin/bash
# Verify that the agent produced a review-backed paper, copy artifacts to the
# mounted logs directories, and snapshot dependencies.

set -euo pipefail

APP_DIR="${APP_DIR:-/app}"
LOGS_DIR="${LOGS_DIR:-/logs}"
REVIEW_FILE="$APP_DIR/experiment_review.md"
REVIEW_JSON="$APP_DIR/review.json"
REPAIR_FILE="$APP_DIR/preflight_repair.md"
REVISED_PROTOCOL_FILE="$APP_DIR/revised_experiment_protocol.md"
PREDICTED_DATA="$APP_DIR/predicted_results/predicted_results.csv"
DEPENDENCY_SNAPSHOT="$LOGS_DIR/verifier/requirements.txt"
PAPER_TEX="$APP_DIR/latex/template.tex"
PAPER_PDF="$APP_DIR/latex/template.pdf"
REFERENCES_FILE="$APP_DIR/latex/references.bib"

SCORE=0
TOTAL=6

# Snapshot Python dependencies for reproducibility and resume.
mkdir -p "$(dirname "$DEPENDENCY_SNAPSHOT")"
uv pip freeze --system > "$DEPENDENCY_SNAPSHOT" 2>/dev/null || \
    pip freeze > "$DEPENDENCY_SNAPSHOT" 2>/dev/null || \
    true

# Copy artifacts to both mounted dirs (agent for Docker, verifier as backup for Modal).
for dest in "$LOGS_DIR/agent/artifacts" "$LOGS_DIR/verifier/artifacts"; do
    mkdir -p "$dest"
    cp "$REVIEW_FILE" "$dest/experiment_review.md" 2>/dev/null || true
    cp "$REVIEW_JSON" "$dest/review.json" 2>/dev/null || true
    cp "$REPAIR_FILE" "$dest/preflight_repair.md" 2>/dev/null || true
    cp "$REVISED_PROTOCOL_FILE" "$dest/revised_experiment_protocol.md" 2>/dev/null || true
    cp -r "$APP_DIR/predicted_results/" "$dest/predicted_results/" 2>/dev/null || true
    cp -r "$APP_DIR/figures/" "$dest/figures/" 2>/dev/null || true
    cp "$PAPER_TEX" "$dest/paper.tex" 2>/dev/null || true
    cp "$PAPER_PDF" "$dest/paper.pdf" 2>/dev/null || true
    cp "$REFERENCES_FILE" "$dest/references.bib" 2>/dev/null || true
    cp "$DEPENDENCY_SNAPSHOT" "$dest/requirements.txt" 2>/dev/null || true
    cp -r "$APP_DIR/literature/" "$dest/literature/" 2>/dev/null || true
    cp -r "$APP_DIR/submissions/" "$dest/submissions/" 2>/dev/null || true
done

has_heading() {
    local heading="$1"
    grep -Eiq "^##[[:space:]]+$heading[[:space:]]*$" "$REVIEW_FILE" 2>/dev/null
}

paper_declares_prediction_mode() {
    grep -Eiq "predicted|expected|hypothesized|hypothetical" "$PAPER_TEX" 2>/dev/null && \
        grep -Eiq "no new experiments|not run|not executed|without running" "$PAPER_TEX" 2>/dev/null
}

paper_has_formula() {
    grep -Eq '\\begin\{equation\}|\\begin\{align\}|\\\[|\\\(|\$\$' "$PAPER_TEX" 2>/dev/null
}

paper_references_figure() {
    grep -Eq '\\includegraphics' "$PAPER_TEX" 2>/dev/null
}

figure_file() {
    find "$APP_DIR/figures" -maxdepth 1 -type f \( -name '*.png' -o -name '*.pdf' \) -size +100c 2>/dev/null | head -1
}

review_json_valid() {
    python3 - "$REVIEW_JSON" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
required = [
    "decision", "gate_decision", "repair_required", "confidence",
    "soundness", "baseline_rigor", "data_metric_fit", "leakage_control",
    "statistical_rigor", "feasibility", "main_risks", "required_changes",
]
missing = [key for key in required if key not in data]
if missing:
    raise SystemExit(1)
if data["decision"] not in {"Run", "Revise Before Running", "Do Not Run Yet"}:
    raise SystemExit(1)
if data["gate_decision"] not in {"pass", "repair", "reject"}:
    raise SystemExit(1)
if not isinstance(data["repair_required"], bool):
    raise SystemExit(1)
for key in ["confidence", "soundness", "baseline_rigor", "data_metric_fit", "leakage_control", "statistical_rigor", "feasibility"]:
    value = data[key]
    if not isinstance(value, (int, float)) or value < 1 or value > 5:
        raise SystemExit(1)
PY
}

repair_required() {
    python3 - "$REVIEW_JSON" <<'PY' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception:
    raise SystemExit(1)
if data.get("repair_required") or data.get("decision") in {"Revise Before Running", "Do Not Run Yet"} or data.get("gate_decision") in {"repair", "reject"}:
    raise SystemExit(0)
raise SystemExit(1)
PY
}

predicted_data_valid() {
    [ -s "$PREDICTED_DATA" ] && \
        [ "$(wc -l < "$PREDICTED_DATA" 2>/dev/null || echo 0)" -ge 2 ] && \
        grep -Eiq "predicted|expected|hypothesized|assumption|rationale" "$PREDICTED_DATA" 2>/dev/null
}

if [ -s "$REVIEW_FILE" ] && \
   review_json_valid && \
   has_heading "Final Recommendation" && \
   grep -Eiq "Run|Revise Before Running|Do Not Run Yet" "$REVIEW_FILE" 2>/dev/null; then
    SCORE=$((SCORE + 1))
    echo "OK: experiment_review.md and review.json strict gate"
else
    echo "MISSING: experiment_review.md, review.json, or final recommendation"
fi

if has_heading "Hypothesis And Claim Fit" && \
   has_heading "Experimental Design Assessment" && \
   has_heading "Baselines And Controls" && \
   has_heading "Data, Metrics, And Evaluation" && \
   has_heading "Strict Gate Scorecard" && \
   has_heading "Formal Criteria"; then
    SCORE=$((SCORE + 1))
    echo "OK: strict design assessment sections"
else
    echo "MISSING: strict design assessment sections"
fi

if has_heading "Threats To Validity" && \
   has_heading "Recommended Changes Before Running" && \
   has_heading "Predicted Results And Rationale" && \
   has_heading "Preflight Repair Handoff"; then
    SCORE=$((SCORE + 1))
    echo "OK: risks, predicted results, and repair handoff"
else
    echo "MISSING: risks, predicted results, or repair handoff"
fi

if repair_required; then
    if [ -s "$REPAIR_FILE" ] && [ -s "$REVISED_PROTOCOL_FILE" ]; then
        SCORE=$((SCORE + 1))
        echo "OK: preflight repair artifacts for failed gate"
    else
        echo "MISSING: preflight repair artifacts for failed gate"
    fi
else
    SCORE=$((SCORE + 1))
    echo "OK: preflight repair not required by gate"
fi

if predicted_data_valid && [ -n "$(figure_file)" ] && paper_references_figure; then
    SCORE=$((SCORE + 1))
    echo "OK: predicted data and chart artifact"
else
    echo "MISSING: predicted data, chart artifact, or paper figure reference"
fi

if [ -s "$PAPER_TEX" ] && [ -s "$PAPER_PDF" ] && paper_declares_prediction_mode && paper_has_formula; then
    SCORE=$((SCORE + 1))
    echo "OK: paper source, compiled PDF, prediction disclosure, and formula"
else
    echo "MISSING: paper source, compiled PDF, prediction disclosure, or formula"
fi

echo ""
echo "Score: $SCORE/$TOTAL"
echo "Dependencies: $(wc -l < "$DEPENDENCY_SNAPSHOT" 2>/dev/null || echo 0) packages"

# Harbor expects all reward.json values to be numeric.
mkdir -p "$LOGS_DIR/verifier"
if [ "$SCORE" -eq "$TOTAL" ]; then
    echo '{"reward": 1}' > "$LOGS_DIR/verifier/reward.json"
else
    echo "{\"reward\": 0.$((SCORE * 100 / TOTAL))}" > "$LOGS_DIR/verifier/reward.json"
fi
