#!/bin/sh
# entrypoint.sh — runs *inside* the doc-toolchain container.
#
# Renders documentation from a Doxyfile template + a mounted project tree.
# Inputs arrive as environment variables (set by build-docs.sh):
#
#   PROJECT_NAME    display name (also used for the PDF filename)
#   PROJECT_NUMBER  version string (optional)
#   INPUT_DIRS      space-separated source dirs INSIDE the container (e.g. "/project/include /project/src")
#   DOCS_DIR        dir holding Doxyfile.in + pages/ + templates/ (e.g. "/project/docs")
#   OUTPUT_DIR      writable output dir (e.g. "/out")
#   HAVE_DOT        "YES"/"NO" — whether graphviz dot diagrams are enabled
#   GENERATE_PDF    "1"/"0"    — also build the LaTeX -> PDF manual
#   MODE            "render" (default) or "init-templates"
#
# The container is expected to be run with a read-only root fs, no network, all
# caps dropped and HOME=/tmp (a tmpfs). Only OUTPUT_DIR and /tmp are writable.
set -eu

: "${PROJECT_NAME:=Project}"
: "${PROJECT_NUMBER:=}"
: "${INPUT_DIRS:=/project/include /project/src}"
: "${DOCS_DIR:=/project/docs}"
: "${OUTPUT_DIR:=/out}"
: "${HAVE_DOT:=NO}"
: "${GENERATE_PDF:=1}"
: "${MODE:=render}"

TEMPLATE="$DOCS_DIR/Doxyfile.in"
if [ ! -f "$TEMPLATE" ]; then
    echo "entrypoint: Doxyfile template not found at $TEMPLATE" >&2
    exit 2
fi

# Fill only the whitelisted placeholders — never blanket-expand, so literal '$'
# elsewhere in the Doxyfile survives untouched.
export PROJECT_NAME PROJECT_NUMBER INPUT_DIRS DOCS_DIR OUTPUT_DIR HAVE_DOT GENERATE_PDF
GEN_LATEX=$([ "$GENERATE_PDF" = "1" ] && echo YES || echo NO)
export GEN_LATEX
DOXYFILE=/tmp/Doxyfile
envsubst \
    '$PROJECT_NAME $PROJECT_NUMBER $INPUT_DIRS $DOCS_DIR $OUTPUT_DIR $HAVE_DOT $GEN_LATEX' \
    < "$TEMPLATE" > "$DOXYFILE"

if [ "$MODE" = "init-templates" ]; then
    # Regenerate version-matched HTML templates into OUTPUT_DIR (mounted rw).
    cd "$OUTPUT_DIR"
    doxygen -w html header.html footer.html customdoxygen.css "$DOXYFILE"
    echo "entrypoint: wrote header.html footer.html customdoxygen.css to $OUTPUT_DIR"
    exit 0
fi

# Source paths in the Doxyfile are absolute (/project/...), but cd there anyway
# so any relative include resolves predictably.
cd /project
echo "entrypoint: running doxygen for '$PROJECT_NAME' (pdf=$GENERATE_PDF, dot=$HAVE_DOT)"
doxygen "$DOXYFILE"

if [ "$GENERATE_PDF" = "1" ]; then
    if [ -f "$OUTPUT_DIR/latex/refman.tex" ]; then
        echo "entrypoint: building PDF manual via LaTeX ..."
        cd "$OUTPUT_DIR/latex"

        # Drop any project-provided LaTeX support packages (referenced from the
        # Doxyfile via EXTRA_PACKAGES) next to refman.tex so \usepackage finds them.
        cp "$DOCS_DIR"/templates/*.sty . 2>/dev/null || true

        # Drive the passes ourselves rather than Doxygen's generated Makefile:
        # that Makefile aborts if pdflatex returns non-zero, which it does for
        # benign reasons (e.g. an undefined Unicode glyph is substituted, not
        # fatal — a valid PDF is still written). We run to cross-reference
        # convergence tolerantly and judge success by the PDF actually existing.
        rm -f refman.pdf
        pdflatex -interaction=batchmode refman >/tmp/latex.log 2>&1 || true
        makeindex refman.idx        >>/tmp/latex.log 2>&1 || true
        pdflatex -interaction=batchmode refman >>/tmp/latex.log 2>&1 || true
        n=3
        while [ "$n" -gt 0 ] && grep -Eq 'Rerun (LaTeX|to get)' refman.log 2>/dev/null; do
            pdflatex -interaction=batchmode refman >>/tmp/latex.log 2>&1 || true
            n=$((n - 1))
        done

        if [ -f refman.pdf ]; then
            safe_name=$(printf '%s' "$PROJECT_NAME" | tr ' /' '__')
            cp refman.pdf "$OUTPUT_DIR/${safe_name}-manual.pdf"
            pages=$(grep -oE 'Output written on refman\.pdf \([0-9]+ pages' refman.log | grep -oE '[0-9]+ pages' || true)
            echo "entrypoint: PDF -> $OUTPUT_DIR/${safe_name}-manual.pdf ${pages:+($pages)}"
        else
            echo "entrypoint: LaTeX produced no refman.pdf — tail of log:" >&2
            tail -n 40 /tmp/latex.log >&2
            exit 3
        fi
    else
        echo "entrypoint: GENERATE_PDF=1 but no latex/refman.tex produced — skipping PDF" >&2
    fi
fi

echo "entrypoint: HTML -> $OUTPUT_DIR/html/index.html"
