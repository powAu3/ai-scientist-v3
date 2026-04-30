#!/usr/bin/env bash
# Convert latex/template.tex to latex/template.docx using pandoc.
#
# Usage:
#   bash scripts/convert_latex_to_docx.sh latex/

set -euo pipefail

LATEX_DIR="${1:-.}"
TEX_FILE="${2:-template.tex}"

PANDOC=$(command -v pandoc 2>/dev/null || true)
if [[ -z "$PANDOC" ]]; then
  echo "ERROR: pandoc not found; cannot generate DOCX. Install pandoc or use the Harbor image." >&2
  exit 1
fi

cd "$LATEX_DIR"

if [[ ! -f "$TEX_FILE" ]]; then
  echo "ERROR: $TEX_FILE not found in $LATEX_DIR" >&2
  exit 1
fi

DOCX_FILE="${TEX_FILE%.tex}.docx"
BIB_ARGS=()
if [[ -f "references.bib" ]]; then
  BIB_ARGS=(--citeproc --bibliography references.bib)
fi

echo "=== Converting $TEX_FILE to $DOCX_FILE ==="
"$PANDOC" "$TEX_FILE" \
  --from latex \
  --to docx \
  "${BIB_ARGS[@]}" \
  --resource-path=".:../figures:figures" \
  --metadata link-citations=true \
  -o "$DOCX_FILE"

python3 - "$DOCX_FILE" <<'PY'
import sys
import zipfile
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists() or path.stat().st_size < 1000:
    raise SystemExit(f"DOCX missing or too small: {path}")
with zipfile.ZipFile(path) as zf:
    names = set(zf.namelist())
    required = {"[Content_Types].xml", "word/document.xml"}
    missing = required - names
    if missing:
        raise SystemExit(f"DOCX missing required members: {', '.join(sorted(missing))}")
print(f"Output: {path} ({path.stat().st_size} bytes)")
PY
