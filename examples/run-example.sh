#!/usr/bin/env bash
# run-example.sh — build documentation for the bundled sample project.
#
# Demonstrates driving the doc-toolchain against an arbitrary project. Produces
# HTML by default; pass --pdf to also build the PDF manual.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE="$HERE/sample-project"

PDF_FLAG="--no-pdf"
[ "${1:-}" = "--pdf" ] && PDF_FLAG="--pdf"

echo ">> documenting sample-project ($PDF_FLAG)"
"$HERE/../build-docs.sh" \
    --project-root "$SAMPLE" \
    --docs-dir     "$SAMPLE/docs" \
    --source-dirs  "include" \
    --project-name "Sample Project" \
    --project-number "1.0.0" \
    --output       "$SAMPLE/_build" \
    "$PDF_FLAG"

echo ">> open $SAMPLE/_build/html/index.html"
