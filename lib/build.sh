#!/usr/bin/env bash
# Builds every platform WITHOUT pushing, to prove the Dockerfile still works on both arches. This is what a
# dry run exercises; the real build happens inside publish.sh, cheaply, off the same buildx cache.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ---- main ----

require docker jq
compute_fingerprint

say "building ${PLATFORMS} (no push)"
echo "   exporter:  ${SMARTCTL_EXPORTER_VERSION}"
echo "   base:      ${ALPINE_IMAGE}"
echo "   fingerprint: ${FINGERPRINT:0:12}"

mapfile -t CACHE_ARGS < <(buildx_cache_args)

# cacheonly, not `--load`: buildx cannot load a multi-platform result into the local docker store, and the
# point here is only to prove both arches compile.
docker buildx build \
  --platform "$PLATFORMS" \
  --build-arg "ALPINE_IMAGE=${ALPINE_IMAGE}" \
  --build-arg "VERSION=${BIN_VERSION}" \
  ${CACHE_ARGS[@]+"${CACHE_ARGS[@]}"} \
  --output=type=cacheonly \
  "$REPO_ROOT"

say "BUILD OK"
