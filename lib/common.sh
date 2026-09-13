#!/usr/bin/env bash
#
# Shared helpers for every script here. Source it near the top: it self-locates the repo root, loads the
# committed versions.env, and derives what a flat file cannot hold.
# It sets no shell options; each script keeps its own `set` line.

[[ -n "${_COMMON_SH:-}" ]] && return
_COMMON_SH=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VERSIONS_FILE="${REPO_ROOT}/versions.env"
if [ ! -f "$VERSIONS_FILE" ]; then
  # die() is not defined yet, so error raw.
  printf '\033[1;31mERROR: missing %s (committed recipe; it should be in the repo checkout)\033[0m\n' \
    "$VERSIONS_FILE" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$VERSIONS_FILE"

DOCKERFILE="${REPO_ROOT}/Dockerfile"
PLATFORMS="linux/amd64,linux/arm64"   # every architecture the consuming clusters run

# The URL path uses the tag (v0.14.0); the asset filename uses the plain number. Dockerfile ARG substitution
# cannot strip the prefix, so do it here and pass only the plain number.
BIN_VERSION="${SMARTCTL_EXPORTER_VERSION#v}"

# Lowercased because GHCR rejects uppercase, and derived from the repo slug so a fork publishes to its own
# namespace with no edit. CI sets GITHUB_REPOSITORY; locally it falls back to upstream.
GHCR_SERVER="ghcr.io"
: "${GITHUB_REPOSITORY:=yama6a/smartctl-exporter-multiarch}"
IMAGE_REPO="${GHCR_SERVER}/$(printf '%s' "$GITHUB_REPOSITORY" | tr '[:upper:]' '[:lower:]')"

OUT_DIR="${REPO_ROOT}/.cache/out"     # release artifacts land here

say()  { printf '\n\033[1;36m>> %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
warn() { printf '  \033[33m[warn]\033[0m %s\n' "$*"; }

require() {
  local t
  for t in "$@"; do
    command -v "$t" >/dev/null && continue
    case "$t" in
      docker) die "docker not found on PATH (Docker Desktop, Rancher Desktop or docker.io; needs buildx)" ;;
      jq)     die "jq not found on PATH (brew install jq / apt install jq)" ;;
      gh)     die "gh not found on PATH (https://cli.github.com/); only release needs it" ;;
      *)      die "$t not found on PATH" ;;
    esac
  done
}

# macOS ships `shasum` and no `sha256sum`; most Linux images ship both. Prefer the coreutils tool.
sha256() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
sha256hex() { sha256 "$@" | awk '{print $1}'; }

# Everything that can change the published image, and nothing that cannot. should_build.sh compares this
# against the newest release's build-inputs.json, so a pin that resolves to the same three values rebuilds
# nothing. The Dockerfile is hashed rather than named because editing it changes the image with no pin moving.
compute_fingerprint() {
  [ -f "$DOCKERFILE" ] || die "missing ${DOCKERFILE}"
  FINGERPRINT="$(printf '%s|%s|%s' \
    "$SMARTCTL_EXPORTER_VERSION" "$ALPINE_IMAGE" "$(sha256hex "$DOCKERFILE")" | sha256hex)"
}

# Both the build's input record and the release's provenance asset.
write_inputs_file() {
  mkdir -p "$OUT_DIR"
  jq -n \
    --arg exporter "$SMARTCTL_EXPORTER_VERSION" \
    --arg alpine "$ALPINE_IMAGE" \
    --arg dockerfile_sha "$(sha256hex "$DOCKERFILE")" \
    --arg fingerprint "$FINGERPRINT" \
    --arg platforms "$PLATFORMS" \
    --arg tag "${1:-}" \
    '{exporter: $exporter, alpine: $alpine, dockerfile_sha256: $dockerfile_sha,
      fingerprint: $fingerprint, platforms: $platforms, release_tag: $tag}' \
    > "${OUT_DIR}/build-inputs.json"
}

# gha cache only works inside Actions (it needs ACTIONS_RUNTIME_TOKEN); locally the flags just error.
buildx_cache_args() {
  [ -n "${GITHUB_ACTIONS:-}" ] || return 0
  printf '%s\n%s\n' '--cache-from=type=gha' '--cache-to=type=gha,mode=max'
}
