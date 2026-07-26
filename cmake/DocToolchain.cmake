# DocToolchain.cmake — optional CMake integration for the doc-toolchain.
#
# Include this from a project's CMakeLists (typically guarded by an option) to
# get `docs` and `docs-pdf` custom targets that shell out to build-docs.sh. The
# heavy lifting still happens in the hardened container (podman, or docker as a
# fallback) — CMake only wires convenient targets.
#
#   option(MCLI_BUILD_DOCS "Add doc targets" OFF)
#   if(MCLI_BUILD_DOCS)
#     include(${CMAKE_SOURCE_DIR}/docs/doc-toolchain/cmake/DocToolchain.cmake)
#   endif()
#
# Configurable cache vars: MCLI_DOCS_SOURCE_DIRS, MCLI_DOCS_DIR, MCLI_DOCS_OUTPUT.

# This file lives at <toolchain>/cmake/DocToolchain.cmake → wrapper is one dir up.
get_filename_component(_DOCTC_DIR "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(DOCTOOLCHAIN_SCRIPT "${_DOCTC_DIR}/build-docs.sh" CACHE FILEPATH
    "Path to the doc-toolchain build-docs.sh wrapper")

# build-docs.sh prefers podman and falls back to docker; warn only if neither is present.
find_program(PODMAN_EXECUTABLE podman)
find_program(DOCKER_EXECUTABLE docker)
if(NOT PODMAN_EXECUTABLE AND NOT DOCKER_EXECUTABLE)
    message(WARNING "doc-toolchain: neither podman nor docker found — 'docs' targets will fail until one is installed")
endif()

# Defaults derived from the including project.
set(MCLI_DOCS_SOURCE_DIRS "include src" CACHE STRING "Source dirs to document (relative to project root)")
set(MCLI_DOCS_DIR    "${CMAKE_SOURCE_DIR}/docs"          CACHE PATH "Docs content dir (Doxyfile.in etc.)")
set(MCLI_DOCS_OUTPUT "${CMAKE_SOURCE_DIR}/docs/_build"   CACHE PATH "Docs output dir")

set(_doctc_common
    "${DOCTOOLCHAIN_SCRIPT}"
    --project-root  "${CMAKE_SOURCE_DIR}"
    --docs-dir      "${MCLI_DOCS_DIR}"
    --source-dirs   "${MCLI_DOCS_SOURCE_DIRS}"
    --output        "${MCLI_DOCS_OUTPUT}"
    --project-name  "${PROJECT_NAME}"
    --project-number "${PROJECT_VERSION}"
)

add_custom_target(docs
    COMMAND ${_doctc_common} --no-pdf
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    COMMENT "Generating HTML documentation (podman/docker + doxygen)"
    USES_TERMINAL VERBATIM)

add_custom_target(docs-pdf
    COMMAND ${_doctc_common} --pdf
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    COMMENT "Generating HTML + PDF documentation (podman/docker + doxygen + LaTeX)"
    USES_TERMINAL VERBATIM)
