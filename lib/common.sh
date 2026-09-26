#!/usr/bin/env bash
# Shared helpers. Loads versions.env and derives what it cannot hold. Sets no shell options.

[[ -n "${_COMMON_SH:-}" ]] && return
_COMMON_SH=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VERSIONS_FILE="${REPO_ROOT}/versions.env"
if [ ! -f "$VERSIONS_FILE" ]; then
  # die() is not defined yet
  printf '\033[1;31mERROR: missing %s (committed recipe; it should be in the repo checkout)\033[0m\n' \
    "$VERSIONS_FILE" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$VERSIONS_FILE"

DOCKERFILE="${REPO_ROOT}/Dockerfile"
PLATFORMS="linux/amd64,linux/arm64" # every architecture the consuming clusters run

# The release asset name needs the version without its leading v, and a Dockerfile ARG cannot strip it.
BIN_VERSION="${SMARTCTL_EXPORTER_VERSION#v}"

# From the repo slug, so a fork publishes to its own namespace. Lowercased, because GHCR rejects uppercase.
# CI sets GITHUB_REPOSITORY. Locally it falls back to this repo.
GHCR_SERVER="ghcr.io"
: "${GITHUB_REPOSITORY:=yama6a/smartctl-exporter-multiarch}"
IMAGE_REPO="${GHCR_SERVER}/$(printf '%s' "$GITHUB_REPOSITORY" | tr '[:upper:]' '[:lower:]')"

OUT_DIR="${REPO_ROOT}/.cache/out" # release artifacts land here

say() { printf '\n\033[1;36m>> %s\033[0m\n' "$*"; }
die() {
  printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2
  exit 1
}
warn() { printf '  \033[33m[warn]\033[0m %s\n' "$*"; }

require() {
  local t
  for t in "$@"; do
    command -v "$t" > /dev/null && continue
    case "$t" in
      docker) die "docker not found on PATH (Docker Desktop, Rancher Desktop or docker.io; needs buildx)" ;;
      jq) die "jq not found on PATH (brew install jq / apt install jq)" ;;
      gh) die "gh not found on PATH (https://cli.github.com/); only release needs it" ;;
      *) die "$t not found on PATH" ;;
    esac
  done
}

# macOS ships `shasum` but no `sha256sum`.
sha256() { if command -v sha256sum > /dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
sha256hex() { sha256 "$@" | awk '{print $1}'; }

# Covers everything that can change the image. The Dockerfile is hashed, because an edit to it moves no pin.
compute_fingerprint() {
  [ -f "$DOCKERFILE" ] || die "missing ${DOCKERFILE}"
  FINGERPRINT="$(printf '%s|%s|%s' \
    "$SMARTCTL_EXPORTER_VERSION" "$ALPINE_IMAGE" "$(sha256hex "$DOCKERFILE")" | sha256hex)"
}

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

# The gha cache needs ACTIONS_RUNTIME_TOKEN, so it works only inside Actions. Locally the flags fail the build.
buildx_cache_args() {
  [ -n "${GITHUB_ACTIONS:-}" ] || return 0
  printf '%s\n%s\n' '--cache-from=type=gha' '--cache-to=type=gha,mode=max'
}
