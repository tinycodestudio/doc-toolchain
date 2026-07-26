# doc-toolchain — containerized Doxygen HTML & PDF docs for C/C++

> Generate Doxygen HTML documentation and a LaTeX PDF manual for any C or C++
> project inside a minimal, security-hardened container — **no host install of
> Doxygen, Graphviz, or LaTeX required.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Doxygen](https://img.shields.io/badge/docs-Doxygen-2C4AA8.svg)](https://www.doxygen.nl/)
[![Container: podman](https://img.shields.io/badge/container-podman-892CA0.svg)](https://podman.io/)
[![Rootless](https://img.shields.io/badge/rootless-yes-brightgreen.svg)](#image-minimal--hardened)

A **self-standing, containerized documentation tool** built on
[Doxygen](https://www.doxygen.nl/). It turns a source tree + a `Doxyfile.in`
template + Markdown pages into browsable **HTML** and an optional **PDF manual** —
without installing Doxygen, Graphviz, or LaTeX on the host. Everything runs inside
a minimal, security-hardened [podman](https://podman.io/) container.

**Why doc-toolchain?** Reproducible, one-command API docs for C/C++ with zero
toolchain drift — vendor it once as a git submodule and every contributor and CI
runner builds identical HTML and PDF output from the same pinned container image.

It is designed to be vendored into a project as a **git submodule** (e.g. at
`docs/doc-toolchain`), reading that project's documentation content from a `docs/`
folder. It works for any C/C++ project, not just the one it ships with.

## Requirements

- A container engine: **`podman`** (rootless is fine, preferred) — or **`docker`**
  as an automatic fallback if podman isn't installed. Nothing else on the host —
  no Doxygen, Graphviz, or LaTeX.

  The engine is autodetected (podman first, then docker). Force one with
  `--engine docker` / `--engine podman`, or the `CONTAINER_ENGINE` env var.

## Quick start

From a project that vendors this at `docs/doc-toolchain`:

```sh
# HTML only (small ~40 MB image, fast):
docs/doc-toolchain/build-docs.sh --no-pdf

# HTML + PDF manual (image adds a minimal LaTeX):
docs/doc-toolchain/build-docs.sh --pdf
```

Output lands in `docs/_build/` (`html/index.html` and `<Project>-manual.pdf`).

Standalone, for any project:

```sh
build-docs.sh --project-root /path/to/proj \
              --docs-dir     /path/to/proj/docs \
              --source-dirs  "include src" \
              --pdf
```

See `build-docs.sh --help` for all options, and `examples/` for a complete
minimal project you can build docs for.

## What the `docs/` folder must provide

The toolchain is generic; per-project content lives in the project's docs dir:

| File | Purpose |
|---|---|
| `Doxyfile.in` | Doxygen config template. Placeholders `${PROJECT_NAME} ${PROJECT_NUMBER} ${INPUT_DIRS} ${DOCS_DIR} ${OUTPUT_DIR} ${HAVE_DOT} ${GEN_LATEX}` are filled in-container. |
| `pages/*.md` | Markdown pages (`@mainpage`, guides). Add them to `INPUT`. |
| `templates/custom.css` | Optional extra stylesheet (`HTML_EXTRA_STYLESHEET`). |

Regenerate version-matched HTML header/footer/CSS templates with:

```sh
build-docs.sh --init-templates      # writes into docs/templates/
```

## Image: minimal & hardened

**Build-time** (`Containerfile`):
- Base `alpine:3.20` (pin to a digest in production).
- Only doc packages installed; `--no-cache`, apk cache removed.
- `--build-arg WITH_PDF=0` → HTML-only image (~40 MB). `WITH_PDF=1` adds a minimal
  TeX Live capable of building Doxygen's `refman.tex`.
- Runs as a non-root `docbuilder` user; single fixed `entrypoint.sh`.

**Run-time** (applied by `build-docs.sh`):
- `--read-only` root filesystem; only the output bind-mount and a `/tmp` tmpfs are writable.
- `--network=none` — rendering needs no network.
- `--cap-drop=ALL` and `--security-opt=no-new-privileges`.
- `--user $(id -u):$(id -g)` (plus `--userns=keep-id` on podman) so output files are owned by you.
- `--memory` / `--pids-limit` caps. Source tree mounted read-only.

## Using as a submodule

```sh
git submodule add <URL-of-this-repo> docs/doc-toolchain
git commit -m "Add doc-toolchain submodule"
```

> If you cloned a project that pins this via a **local path** URL (as in the
> reference setup, which has no remote), edit `.gitmodules` to point `url` at your
> hosted copy of this repo and run `git submodule sync`.

## CMake integration (optional)

```cmake
option(MYPROJ_BUILD_DOCS "Add doc targets" OFF)
if(MYPROJ_BUILD_DOCS)
  include(${CMAKE_SOURCE_DIR}/docs/doc-toolchain/cmake/DocToolchain.cmake)
endif()
# → `cmake --build build --target docs` / `docs-pdf`
```

## SELinux hosts

If your host enforces SELinux, append `,Z` to the volume mounts in `build-docs.sh`
(`-v "$PROJECT_ROOT:/project:ro,Z"`). It is omitted by default because relabeling
is unnecessary — and can be surprising — on non-SELinux hosts.

## License

Released under the [MIT License](LICENSE). © 2026 tinycodestudio.

---

<sub>**Keywords:** Doxygen · containerized documentation · C/C++ API docs
generator · Doxygen PDF · Doxygen HTML · podman · rootless container ·
Graphviz · LaTeX manual · doc automation · git submodule docs · CMake docs ·
reproducible documentation build · security-hardened container · Alpine Linux.</sub>
