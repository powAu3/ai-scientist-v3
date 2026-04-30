#!/bin/bash
# Verify that the agent produced a review-backed paper, copy artifacts to the
# mounted logs directories, and snapshot dependencies.

set -euo pipefail

APP_DIR="${APP_DIR:-/app}"
LOGS_DIR="${LOGS_DIR:-/logs}"
REVIEW_FILE="$APP_DIR/experiment_review.md"
REVIEW_JSON="$APP_DIR/review.json"
REQUIREMENTS_FILE="$APP_DIR/requirements.txt"
PAPER_TEX="$APP_DIR/latex/template.tex"
PAPER_PDF="$APP_DIR/latex/template.pdf"
REFERENCES_FILE="$APP_DIR/latex/references.bib"

SCORE=0
TOTAL=4

# Snapshot Python dependencies for reproducibility and resume.
uv pip freeze --system > "$REQUIREMENTS_FILE" 2>/dev/null || \
    pip freeze > "$REQUIREMENTS_FILE" 2>/dev/null || \
    true

# Copy artifacts to both mounted dirs (agent for Docker, verifier as backup for Modal).
for dest in "$LOGS_DIR/agent/artifacts" "$LOGS_DIR/verifier/artifacts"; do
    mkdir -p "$dest"
    cp "$REVIEW_FILE" "$dest/experiment_review.md" 2>/dev/null || true
    cp "$REVIEW_JSON" "$dest/review.json" 2>/dev/null || true
    cp "$PAPER_TEX" "$dest/paper.tex" 2>/dev/null || true
    cp "$PAPER_PDF" "$dest/paper.pdf" 2>/dev/null || true
    cp "$REFERENCES_FILE" "$dest/references.bib" 2>/dev/null || true
    cp "$REQUIREMENTS_FILE" "$dest/requirements.txt" 2>/dev/null || true
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

if [ -s "$REVIEW_FILE" ] && \
   has_heading "Final Recommendation" && \
   grep -Eiq "Run|Revise Before Running|Do Not Run Yet" "$REVIEW_FILE" 2>/dev/null; then
    SCORE=$((SCORE + 1))
    echo "OK: experiment_review.md with final recommendation"
else
    echo "MISSING: experiment_review.md or final recommendation"
fi

if has_heading "Hypothesis And Claim Fit" && \
   has_heading "Experimental Design Assessment" && \
   has_heading "Baselines And Controls" && \
   has_heading "Data, Metrics, And Evaluation"; then
    SCORE=$((SCORE + 1))
    echo "OK: core design assessment sections"
else
    echo "MISSING: core design assessment sections"
fi

if has_heading "Threats To Validity" && \
   has_heading "Recommended Changes Before Running" && \
   has_heading "Predicted Results And Rationale"; then
    SCORE=$((SCORE + 1))
    echo "OK: risks, predicted results, and required changes"
else
    echo "MISSING: risks, predicted results, or required changes"
fi

if [ -s "$PAPER_TEX" ] && [ -s "$PAPER_PDF" ] && paper_declares_prediction_mode; then
    SCORE=$((SCORE + 1))
    echo "OK: paper source, compiled PDF, and prediction-mode disclosure"
else
    echo "MISSING: paper source, compiled PDF, or prediction-mode disclosure"
fi

echo ""
echo "Score: $SCORE/$TOTAL"
echo "Dependencies: $(wc -l < "$REQUIREMENTS_FILE" 2>/dev/null || echo 0) packages"

# Harbor expects all reward.json values to be numeric.
mkdir -p "$LOGS_DIR/verifier"
if [ "$SCORE" -eq "$TOTAL" ]; then
    echo '{"reward": 1}' > "$LOGS_DIR/verifier/reward.json"
else
    echo "{\"reward\": 0.$((SCORE * 100 / TOTAL))}" > "$LOGS_DIR/verifier/reward.json"
fi
