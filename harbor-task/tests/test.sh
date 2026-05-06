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
EXPERIMENT_CODEBASE="$APP_DIR/experiment_codebase"
PREDICTED_DATA="$APP_DIR/predicted_results/predicted_results.csv"
DEPENDENCY_SNAPSHOT="$LOGS_DIR/verifier/requirements.txt"
PAPER_TEX="$APP_DIR/latex/template.tex"
PAPER_PDF="$APP_DIR/latex/template.pdf"
PAPER_DOCX="$APP_DIR/latex/template.docx"
REFERENCES_FILE="$APP_DIR/latex/references.bib"
LITERATURE_MATRIX="$APP_DIR/literature/literature_matrix.md"
LITERATURE_README="$APP_DIR/literature/README.md"
MANUSCRIPT_EXPLANATION="$APP_DIR/manuscript_explanation.md"
FIGURE_PROVENANCE_JSON="$APP_DIR/figures/figure_provenance.json"
FIGURE_PROVENANCE_README="$APP_DIR/figures/README.md"
REVIEWS_DIR="$APP_DIR/reviews"
SUBMISSIONS_DIR="$APP_DIR/submissions"

SCORE=0
TOTAL=13

# Snapshot Python dependencies for reproducibility and resume.
mkdir -p "$(dirname "$DEPENDENCY_SNAPSHOT")"
uv pip freeze --system > "$DEPENDENCY_SNAPSHOT" 2>/dev/null || \
    pip freeze > "$DEPENDENCY_SNAPSHOT" 2>/dev/null || \
    true

if [ -f "$APP_DIR/scripts/generate_predicted_figures.py" ]; then
    python3 "$APP_DIR/scripts/generate_predicted_figures.py" --app-dir "$APP_DIR" >/dev/null 2>&1 || true
fi
if [ -f "$APP_DIR/scripts/write_figure_provenance.py" ]; then
    python3 "$APP_DIR/scripts/write_figure_provenance.py" --app-dir "$APP_DIR" >/dev/null 2>&1 || true
fi
if [ -f "$APP_DIR/scripts/create_manifest_templates.py" ]; then
    python3 "$APP_DIR/scripts/create_manifest_templates.py" --app-dir "$APP_DIR" >/dev/null 2>&1 || true
fi

# Copy artifacts to both mounted dirs (agent for Docker, verifier as backup for Modal).
for dest in "$LOGS_DIR/agent/artifacts" "$LOGS_DIR/verifier/artifacts"; do
    mkdir -p "$dest"
    cp "$REVIEW_FILE" "$dest/experiment_review.md" 2>/dev/null || true
    cp "$REVIEW_JSON" "$dest/review.json" 2>/dev/null || true
    cp "$REPAIR_FILE" "$dest/preflight_repair.md" 2>/dev/null || true
    cp "$REVISED_PROTOCOL_FILE" "$dest/revised_experiment_protocol.md" 2>/dev/null || true
    cp -r "$EXPERIMENT_CODEBASE" "$dest/experiment_codebase" 2>/dev/null || true
    cp -r "$APP_DIR/configs/" "$dest/configs/" 2>/dev/null || true
    cp -r "$APP_DIR/predicted_results/" "$dest/predicted_results/" 2>/dev/null || true
    cp -r "$APP_DIR/manifests/" "$dest/manifests/" 2>/dev/null || true
    cp -r "$APP_DIR/reports/" "$dest/reports/" 2>/dev/null || true
    cp -r "$APP_DIR/figures/" "$dest/figures/" 2>/dev/null || true
    cp -r "$APP_DIR/reviews/" "$dest/reviews/" 2>/dev/null || true
    cp "$PAPER_TEX" "$dest/paper.tex" 2>/dev/null || true
    cp "$PAPER_PDF" "$dest/paper.pdf" 2>/dev/null || true
    cp "$PAPER_DOCX" "$dest/paper.docx" 2>/dev/null || true
    cp "$REFERENCES_FILE" "$dest/references.bib" 2>/dev/null || true
    cp "$MANUSCRIPT_EXPLANATION" "$dest/manuscript_explanation.md" 2>/dev/null || true
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

paper_formula_count() {
    python3 - "$PAPER_TEX" <<'PY' 2>/dev/null
import re, sys
try:
    text = open(sys.argv[1], encoding="utf-8").read()
except Exception:
    print(0)
    raise SystemExit(0)
count = len(re.findall(r"\\begin\{(?:equation|equation\*|align|align\*|gather|gather\*|multline|multline\*)\}", text))
count += len(re.findall(r"\\\[[\s\S]*?\\\]", text))
count += len(re.findall(r"\$\$[\s\S]*?\$\$", text))
print(count)
PY
}

paper_has_min_formulas() {
    [ "$(paper_formula_count)" -ge 4 ]
}

paper_has_keywords() {
    grep -Eiq '\\keywords[[:space:]]*\{|Keywords[[:space:]]*:|Key words[[:space:]]*:' "$PAPER_TEX" 2>/dev/null
}

docx_valid() {
    python3 - "$PAPER_DOCX" <<'PY' 2>/dev/null
import sys
import zipfile
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists() or path.stat().st_size < 1000:
    raise SystemExit(1)
with zipfile.ZipFile(path) as zf:
    names = set(zf.namelist())
    if "[Content_Types].xml" not in names or "word/document.xml" not in names:
        raise SystemExit(1)
    document = zf.read("word/document.xml").decode("utf-8", errors="ignore")
    if "CrackYOLO" not in document and "Review" not in document:
        raise SystemExit(1)
PY
}

paper_references_figure() {
    grep -Eq '\\includegraphics' "$PAPER_TEX" 2>/dev/null
}

paper_figure_count() {
    grep -Ec '\\includegraphics' "$PAPER_TEX" 2>/dev/null || echo 0
}

paper_has_min_figures() {
    [ "$(paper_figure_count)" -ge 5 ]
}

paper_word_count() {
    python3 - "$PAPER_TEX" <<'PY' 2>/dev/null
import re, sys
try:
    text = open(sys.argv[1], encoding="utf-8").read()
except Exception:
    print(0)
    raise SystemExit(0)
text = re.sub(r"%.*", " ", text)
text = re.sub(r"\\[a-zA-Z]+\*?(?:\[[^\]]*\])?(?:\{[^{}]*\})?", " ", text)
words = re.findall(r"[A-Za-z][A-Za-z0-9-]{2,}", text)
print(len(words))
PY
}

paper_has_v2_structure() {
    local words
    words="$(paper_word_count)"
    [ "${words:-0}" -ge 1800 ] && \
        grep -Eiq '\\begin\{abstract\}' "$PAPER_TEX" 2>/dev/null && \
        grep -Eiq '\\section\{Introduction\}' "$PAPER_TEX" 2>/dev/null && \
        grep -Eiq '\\section\{Related Work\}' "$PAPER_TEX" 2>/dev/null && \
        grep -Eiq '\\section\{Background\}' "$PAPER_TEX" 2>/dev/null && \
        grep -Eiq '\\section\{Method\}' "$PAPER_TEX" 2>/dev/null && \
        grep -Eiq '\\section\{Experimental Setup\}' "$PAPER_TEX" 2>/dev/null && \
        grep -Eiq '\\section\{Predicted Results|\\section\{Experiments' "$PAPER_TEX" 2>/dev/null && \
        grep -Eiq '\\section\{Limitations\}' "$PAPER_TEX" 2>/dev/null && \
        grep -Eiq '\\section\{Conclusion\}' "$PAPER_TEX" 2>/dev/null && \
        grep -Eiq '\\begin\{table\}' "$PAPER_TEX" 2>/dev/null
}

references_valid() {
    [ -s "$REFERENCES_FILE" ] && \
        [ "$(grep -Ec '^@[A-Za-z]+' "$REFERENCES_FILE" 2>/dev/null || echo 0)" -ge 6 ] && \
        grep -Eq '\\cite(t|p)?\{' "$PAPER_TEX" 2>/dev/null
}

paper_quality_audit() {
    python3 "$APP_DIR/scripts/audit_paper_quality.py" --app-dir "$APP_DIR"
}

literature_matrix_valid() {
    [ -s "$LITERATURE_MATRIX" ] && \
        [ -s "$LITERATURE_README" ] && \
        grep -Eiq "claim|supports|baseline|dataset|method" "$LITERATURE_MATRIX" 2>/dev/null && \
        [ "$(grep -Eci 'doi:|https?://|arxiv:' "$LITERATURE_MATRIX" 2>/dev/null || echo 0)" -ge 8 ]
}

manuscript_explanation_valid() {
    [ -s "$MANUSCRIPT_EXPLANATION" ] && \
        grep -Eiq "PDF|manuscript-effect|effect test|protocol draft" "$MANUSCRIPT_EXPLANATION" 2>/dev/null && \
        grep -Eiq "predicted_results|Prediction CSV|forecast CSV" "$MANUSCRIPT_EXPLANATION" 2>/dev/null && \
        grep -Eiq "evidence status|Evidence Status|replacement trigger|Replacement Trigger" "$MANUSCRIPT_EXPLANATION" 2>/dev/null && \
        grep -Eiq "not.*measured|training|benchmark" "$MANUSCRIPT_EXPLANATION" 2>/dev/null
}

review_artifacts_valid() {
    local direct_ok=1
    [ -s "$REVIEWS_DIR/top_tier_review.md" ] || direct_ok=0
    [ -s "$REVIEWS_DIR/figure_audit.md" ] || direct_ok=0
    [ -s "$REVIEWS_DIR/area_chair_gate.md" ] || direct_ok=0
    if [ "$direct_ok" -eq 1 ] && \
       grep -Eiq "soundness|weakness|overall|decision" "$REVIEWS_DIR/top_tier_review.md" 2>/dev/null && \
       grep -Eiq "figure|caption|visual|table" "$REVIEWS_DIR/figure_audit.md" 2>/dev/null && \
       grep -Eiq "Gate Decision|Repair Before Finish|Pass|Reject|Area Chair" "$REVIEWS_DIR/area_chair_gate.md" 2>/dev/null; then
        return 0
    fi

    local response gate
    response="$(find "$SUBMISSIONS_DIR" -path '*/reviewer_communications/response.md' -type f 2>/dev/null | sort | tail -1)"
    gate="$(find "$SUBMISSIONS_DIR" -path '*/reviewer_communications/area_chair_gate.md' -type f 2>/dev/null | sort | tail -1)"
    [ -s "$response" ] && [ -s "$gate" ] && \
        grep -Eiq "Figure|Caption|Soundness|Weakness|Overall" "$response" 2>/dev/null && \
        grep -Eiq "Gate Decision|Repair Before Finish|Pass|Reject|Area Chair" "$gate" 2>/dev/null
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
    if [ -f "$APP_DIR/scripts/generate_predicted_figures.py" ]; then
        python3 "$APP_DIR/scripts/generate_predicted_figures.py" --app-dir "$APP_DIR" >/dev/null 2>&1 || return 1
    fi
    if [ -f "$APP_DIR/scripts/write_figure_provenance.py" ]; then
        python3 "$APP_DIR/scripts/write_figure_provenance.py" --app-dir "$APP_DIR" >/dev/null 2>&1 || return 1
    fi
    [ -s "$PREDICTED_DATA" ] && \
        [ "$(wc -l < "$PREDICTED_DATA" 2>/dev/null || echo 0)" -ge 2 ] && \
        grep -Eiq "predicted|expected|hypothesized|assumption|rationale" "$PREDICTED_DATA" 2>/dev/null && \
        [ -s "$FIGURE_PROVENANCE_JSON" ] && \
        [ -s "$FIGURE_PROVENANCE_README" ] && \
        grep -Eiq "source_kind|regeneration|planning_forecast" "$FIGURE_PROVENANCE_JSON" 2>/dev/null
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

if predicted_data_valid && [ -n "$(figure_file)" ] && paper_references_figure && paper_has_min_figures; then
    SCORE=$((SCORE + 1))
    echo "OK: predicted data and rich figure artifacts"
else
    echo "MISSING: predicted data, chart artifact, or five paper figure references"
fi

if [ -s "$PAPER_TEX" ] && [ -s "$PAPER_PDF" ] && paper_declares_prediction_mode && paper_has_formula && paper_has_min_formulas && paper_has_keywords; then
    SCORE=$((SCORE + 1))
    echo "OK: paper source, compiled PDF, prediction disclosure, formulas, and keywords"
else
    echo "MISSING: paper source, compiled PDF, prediction disclosure, four formulas, or keywords"
fi

if docx_valid; then
    SCORE=$((SCORE + 1))
    echo "OK: Word DOCX export"
else
    echo "MISSING: valid Word DOCX export"
fi

if paper_has_v2_structure; then
    SCORE=$((SCORE + 1))
    echo "OK: substantive AI Scientist-v2-style paper structure and table"
else
    echo "MISSING: substantive AI Scientist-v2-style paper structure or table"
fi

if references_valid; then
    SCORE=$((SCORE + 1))
    echo "OK: real bibliography file and in-text citations"
else
    echo "MISSING: bibliography file with at least six entries or in-text citations"
fi

if paper_quality_audit; then
    SCORE=$((SCORE + 1))
    echo "OK: top-tier paper quality audit"
else
    echo "MISSING: top-tier paper quality audit requirements"
fi

if literature_matrix_valid; then
    SCORE=$((SCORE + 1))
    echo "OK: real literature matrix"
else
    echo "MISSING: real literature matrix with citation-to-claim mapping"
fi

if manuscript_explanation_valid; then
    SCORE=$((SCORE + 1))
    echo "OK: separate manuscript companion explanation"
else
    echo "MISSING: manuscript companion explanation"
fi

if review_artifacts_valid; then
    SCORE=$((SCORE + 1))
    echo "OK: top-tier review, figure audit, and area-chair gate artifacts"
else
    echo "MISSING: top-tier review, figure audit, or area-chair gate artifacts"
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
