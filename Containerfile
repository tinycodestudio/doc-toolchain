# doc-toolchain — minimal, hardened Doxygen documentation image.
#
# A self-standing container that turns a Doxyfile + source tree + markdown into
# HTML (and optionally a PDF manual). Nothing is installed on the host; the whole
# toolchain lives here.
#
# Build (HTML only — small, ~40 MB):   podman build --build-arg WITH_PDF=0 -t doc-toolchain:html .
# Build (with PDF — adds LaTeX):        podman build -t doc-toolchain .
#
# Hardening baked into the image (runtime hardening is applied by build-docs.sh):
#   * pinned distro tag, no package cache left behind
#   * only the packages needed to render docs
#   * runs as an unprivileged, non-root user
#   * no shell entrypoint that could be abused — a single fixed entrypoint script
#
# Pin to a digest in production for full reproducibility, e.g.:
#   FROM docker.io/library/alpine:3.20@sha256:<digest>
FROM docker.io/library/alpine:3.20

# WITH_PDF=1 pulls in a minimal LaTeX capable of building Doxygen's refman.tex.
# WITH_PDF=0 yields an HTML-only image that stays tiny.
ARG WITH_PDF=1

# hadolint ignore=DL3018  (Alpine packages are intentionally unpinned; tag-pinned base)
RUN set -eux; \
    apk add --no-cache \
        doxygen \
        graphviz \
        ttf-freefont \
        make \
        gettext; \
    if [ "$WITH_PDF" = "1" ]; then \
        apk add --no-cache \
            texlive \
            texmf-dist-latexextra \
            texmf-dist-latexrecommended \
            texmf-dist-fontsrecommended; \
    fi; \
    # unprivileged build user with a home it owns
    adduser -D -u 1000 -h /home/docbuilder docbuilder; \
    rm -rf /var/cache/apk/* /tmp/*

# The only executable surface: a fixed entrypoint that renders the docs.
COPY --chmod=0555 entrypoint.sh /usr/local/bin/entrypoint.sh

USER docbuilder
WORKDIR /project

# HOME must be writable for some LaTeX/fontconfig scratch; point it at tmpfs at runtime.
ENV HOME=/tmp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
