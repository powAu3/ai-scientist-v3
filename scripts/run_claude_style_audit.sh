#!/usr/bin/env bash
# Run a concise Claude manuscript style audit and save it under reviews/.
#
# This script intentionally audits rather than silently rewrites. The main
# Claude Code agent should apply the useful edits, then rerun compile/review.

set -euo pipefail

BASE_DIR="${1:-.}"
TEX_PATH="${2:-$BASE_DIR/latex/template.tex}"
OUTPUT_PATH="${3:-$BASE_DIR/reviews/style_audit.md}"

if [[ ! -f "$TEX_PATH" ]]; then
  echo "ERROR: manuscript not found: $TEX_PATH" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "Warning: claude CLI not found; skipping style audit." >&2
  exit 0
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
PROMPT_FILE="$(mktemp)"
trap 'rm -f "$PROMPT_FILE"' EXIT

cat > "$PROMPT_FILE" <<'PROMPT'
You are a strict scientific writing editor. Review the LaTeX manuscript below
for AI-writing traces.

Goal: lower AI-writing fingerprints without hiding that this is a review-backed
low-compute protocol manuscript. Do not ask to run experiments. Do not rewrite
the full file. Return:
1. verdict,
2. top exact phrases/sentences that still sound AI-generated or too generic,
3. concise replacement text for each,
4. any claim that risks sounding like measured evidence.

Manuscript:
PROMPT

{
  echo '```latex'
  cat "$TEX_PATH"
  echo '```'
} >> "$PROMPT_FILE"

CLAUDECODE="" claude -p \
  --model "${CLAUDE_STYLE_MODEL:-${CLAUDE_REVIEWER_MODEL:-sonnet}}" \
  --output-format text \
  "$(cat "$PROMPT_FILE")" \
  > "$OUTPUT_PATH"

echo "Wrote $OUTPUT_PATH"
