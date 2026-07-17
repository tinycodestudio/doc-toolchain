#!/usr/bin/env bash
# build-docs.sh — generate project documentation in a hardened podman container.
#
# Self-standing: needs only podman on the host. Doxygen, Graphviz and LaTeX all
# live in the container image, which is built on first use.
#
# Typical use (from a project that vendors this as docs/doc-toolchain):
#   docs/doc-toolchain/build-docs.sh                 # HTML + PDF for the parent project
#   docs/doc-toolchain/build-docs.sh --no-pdf        # HTML only (tiny image)
#   docs/doc-toolchain/build-docs.sh --pdf --output /tmp/out
#
# Standalone / other projects:
#   build-docs.sh --project-root PATH --docs-dir PATH/docs --source-dirs "include src"
#
set -euo pipefail

# ── Locate self ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Defaults ─────────────────────────────────────────────────────────────────
# When vendored at <project>/docs/doc-toolchain, the parent project root is two
# levels up and its docs dir is one level up.
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCS_DIR=""                # default: $PROJECT_ROOT/docs (resolved after arg parse)
SOURCE_DIRS="include src"
OUTPUT_DIR=""              # default: $DOCS_DIR/_build
PROJECT_NAME=""            # default: basename of PROJECT_ROOT
PROJECT_NUMBER=""
GENERATE_PDF=1
IMAGE=""                   # default: computed from PDF toggle
REBUILD_IMAGE=0
INIT_TEMPLATES=0

usage() {
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    cat <<'EOF'

Options:
  --project-root DIR    Project root to mount read-only (default: parent of docs/doc-toolchain)
  --docs-dir DIR        Dir with Doxyfile.in + pages/ + templates/ (default: PROJECT_ROOT/docs)
  --source-dirs "A B"   Space-separated source dirs, relative to project root (default: "include src")
  --output DIR          Output dir (default: DOCS_DIR/_build)
  --project-name NAME   Doxygen PROJECT_NAME (default: basename of project root)
  --project-number VER  Doxygen PROJECT_NUMBER / version string
  --pdf | --no-pdf      Build (or skip) the LaTeX PDF manual (default: --pdf)
  --image NAME[:TAG]    Container image tag to build/use (default: doc-toolchain:pdf|html)
  --rebuild-image       Force a fresh image build
  --init-templates      Regenerate version-matched HTML templates into DOCS_DIR/templates
  -h, --help            This help
EOF
}

# ── Parse args ───────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --project-root)   PROJECT_ROOT="$(cd "$2" && pwd)"; shift 2 ;;
        --docs-dir)       DOCS_DIR="$2"; shift 2 ;;
        --source-dirs)    SOURCE_DIRS="$2"; shift 2 ;;
        --output)         OUTPUT_DIR="$2"; shift 2 ;;
        --project-name)   PROJECT_NAME="$2"; shift 2 ;;
        --project-number) PROJECT_NUMBER="$2"; shift 2 ;;
        --pdf)            GENERATE_PDF=1; shift ;;
        --no-pdf)         GENERATE_PDF=0; shift ;;
        --html)           shift ;;              # HTML is always produced; accepted for clarity
        --image)          IMAGE="$2"; shift 2 ;;
        --rebuild-image)  REBUILD_IMAGE=1; shift ;;
        --init-templates) INIT_TEMPLATES=1; shift ;;
        -h|--help)        usage; exit 0 ;;
        *) echo "build-docs: unknown option '$1'" >&2; usage >&2; exit 2 ;;
    esac
done

command -v podman >/dev/null 2>&1 || { echo "build-docs: podman is required but not found" >&2; exit 1; }

# ── Resolve defaults that depend on other args ───────────────────────────────
[ -n "$DOCS_DIR" ]      || DOCS_DIR="$PROJECT_ROOT/docs"
DOCS_DIR="$(cd "$DOCS_DIR" && pwd)"
[ -n "$OUTPUT_DIR" ]    || OUTPUT_DIR="$DOCS_DIR/_build"
[ -n "$PROJECT_NAME" ]  || PROJECT_NAME="$(basename "$PROJECT_ROOT")"
if [ -z "$IMAGE" ]; then
    [ "$GENERATE_PDF" = "1" ] && IMAGE="doc-toolchain:pdf" || IMAGE="doc-toolchain:html"
fi

[ -f "$DOCS_DIR/Doxyfile.in" ] || { echo "build-docs: no Doxyfile.in in $DOCS_DIR" >&2; exit 2; }

# DOCS_DIR must live under PROJECT_ROOT so it is reachable inside the /project mount.
case "$DOCS_DIR/" in
    "$PROJECT_ROOT"/*) : ;;
    *) echo "build-docs: --docs-dir must be inside --project-root" >&2; exit 2 ;;
esac
DOCS_REL="${DOCS_DIR#"$PROJECT_ROOT"/}"

# Container-side paths.
C_DOCS_DIR="/project/$DOCS_REL"
C_INPUT_DIRS=""
for d in $SOURCE_DIRS; do C_INPUT_DIRS="$C_INPUT_DIRS /project/$d"; done
C_INPUT_DIRS="$(echo "$C_INPUT_DIRS" | sed 's/^ *//')"

# ── Build the image if needed ────────────────────────────────────────────────
if [ "$REBUILD_IMAGE" = "1" ] || ! podman image exists "$IMAGE"; then
    echo ">> building image $IMAGE (WITH_PDF=$GENERATE_PDF) ..."
    podman build --build-arg "WITH_PDF=$GENERATE_PDF" -t "$IMAGE" -f "$SCRIPT_DIR/Containerfile" "$SCRIPT_DIR"
fi

mkdir -p "$OUTPUT_DIR"

# ── Runtime hardening ────────────────────────────────────────────────────────
# read-only root fs; only /out (bind) and /tmp (tmpfs) writable; no network; all
# Linux capabilities dropped; no privilege escalation; runs as the invoking host
# uid so generated files are owned by you (not root/uid-1000).
HARDENING=(
    --rm
    --cap-drop=ALL
    --security-opt=no-new-privileges
    --read-only
    --network=none
    --tmpfs "/tmp:rw,exec,size=512m"
    --user "$(id -u):$(id -g)"
    --userns=keep-id
    --memory=2g
    --pids-limit=512
)

run_container() {
    local mode="$1" out="$2"
    podman run "${HARDENING[@]}" \
        -e "PROJECT_NAME=$PROJECT_NAME" \
        -e "PROJECT_NUMBER=$PROJECT_NUMBER" \
        -e "INPUT_DIRS=$C_INPUT_DIRS" \
        -e "DOCS_DIR=$C_DOCS_DIR" \
        -e "OUTPUT_DIR=/out" \
        -e "HAVE_DOT=YES" \
        -e "GENERATE_PDF=$GENERATE_PDF" \
        -e "MODE=$mode" \
        -v "$PROJECT_ROOT:/project:ro" \
        -v "$out:/out:rw" \
        "$IMAGE"
}

if [ "$INIT_TEMPLATES" = "1" ]; then
    mkdir -p "$DOCS_DIR/templates"
    echo ">> regenerating HTML templates into $DOCS_DIR/templates ..."
    run_container "init-templates" "$DOCS_DIR/templates"
    exit 0
fi

echo ">> generating documentation for '$PROJECT_NAME' -> $OUTPUT_DIR"
run_container "render" "$OUTPUT_DIR"

echo ""
echo "Done."
echo "  HTML: $OUTPUT_DIR/html/index.html"
if [ "$GENERATE_PDF" = "1" ]; then
    pdf="$OUTPUT_DIR/$(printf '%s' "$PROJECT_NAME" | tr ' /' '__')-manual.pdf"
    [ -f "$pdf" ] && echo "  PDF:  $pdf"
fi
