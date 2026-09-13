#!/usr/bin/env bash
# Builds every platform and pushes the manifest list to GHCR, then stages the release assets. Creating the
# release is lib/release.sh, so a run that dies here leaves an orphan image tag that no release announced and
# the next run overwrites.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ---- state ----
# GHCR_USER is deliberately NOT pre-declared: it may come from the environment, and an empty default here
# would make the ${GHCR_USER:-...} fallback below always win.
RELEASE_TAG=""    # set by resolve_build_revision
DIGEST=""         # set by build_and_push

# ---- functions ----

assert_ghcr_token() {
  : "${GHCR_TOKEN:=${GITHUB_TOKEN:-}}"
  [ -n "$GHCR_TOKEN" ] || die "GHCR_TOKEN (or GITHUB_TOKEN) is empty. Needs a token with write:packages for ${IMAGE_REPO}"
  GHCR_USER="${GHCR_USER:-${GITHUB_REPOSITORY%%/*}}"
}

# The next free build revision for this upstream version, read off the published releases. Stateless, no
# counter file. A previous run that pushed an image but never released reuses and overwrites its own N, which
# is safe because nothing could have consumed a tag no release announced.
resolve_build_revision() {
  local auth=() releases existing revision
  say "resolving the build revision"
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  releases="$(curl -fsSL --retry 3 ${auth[@]+"${auth[@]}"} \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases?per_page=100" 2>/dev/null || true)"
  # All in jq: `... | grep | sort | tail` exits 1 when nothing matches, the NORMAL case for the first release
  # of an upstream version, and pipefail turns that into a silent build failure.
  existing="$(printf '%s' "$releases" | jq -r --arg t "$SMARTCTL_EXPORTER_VERSION" \
    '[.[]?.tag_name // empty | select(startswith($t + "-")) | ltrimstr($t + "-")
      | select(test("^[0-9]+$")) | tonumber] | max // 0' 2>/dev/null || echo 0)"
  [ -n "$existing" ] || existing=0
  revision=$(( existing + 1 ))
  RELEASE_TAG="${SMARTCTL_EXPORTER_VERSION}-${revision}"
  if [ "$existing" -eq 0 ]; then echo "   ${RELEASE_TAG}  (first release for ${SMARTCTL_EXPORTER_VERSION})"
  else echo "   ${RELEASE_TAG}  (previous: ${SMARTCTL_EXPORTER_VERSION}-${existing})"; fi
}

# One buildx run emits the manifest list for every platform and all three tags. `docker tag` cannot do this:
# it only ever names a single-platform image in the local store.
build_and_push() {
  local cache_args=() tag_args=() t
  say "building and pushing ${PLATFORMS}"
  printf '%s' "$GHCR_TOKEN" | docker login "$GHCR_SERVER" -u "$GHCR_USER" --password-stdin >/dev/null \
    || die "docker login ${GHCR_SERVER} failed (is the token write:packages for ${GHCR_USER}?)"
  # In CI the runner is thrown away, and the provenance attestation step needs the session to push the
  # attestation to the registry, so only a real machine logs out.
  [ -z "${GITHUB_ACTIONS:-}" ] && trap 'docker logout "$GHCR_SERVER" >/dev/null 2>&1 || true' EXIT

  mapfile -t cache_args < <(buildx_cache_args)
  # The immutable revision, plus two moving tags: the bare upstream version for anyone tracking rebuilds by
  # digest, and latest.
  for t in "$RELEASE_TAG" "$SMARTCTL_EXPORTER_VERSION" latest; do
    tag_args+=(--tag "${IMAGE_REPO}:${t}")
  done

  docker buildx build \
    --platform "$PLATFORMS" \
    --build-arg "ALPINE_IMAGE=${ALPINE_IMAGE}" \
    --build-arg "VERSION=${BIN_VERSION}" \
    ${cache_args[@]+"${cache_args[@]}"} \
    "${tag_args[@]}" \
    --push \
    "$REPO_ROOT" || die "buildx build/push failed"

  for t in "$RELEASE_TAG" "$SMARTCTL_EXPORTER_VERSION" latest; do echo "   ${IMAGE_REPO}:${t}"; done
  DIGEST="$(docker buildx imagetools inspect "${IMAGE_REPO}:${RELEASE_TAG}" --format '{{.Manifest.Digest}}')"
}

# Generated, not hand-written: every pin that produced this image, so a reader can reproduce it without
# cloning anything.
write_release_notes() {
cat > "${OUT_DIR}/release-notes.md" <<EOF
Multi-arch (${PLATFORMS}) build of [smartctl_exporter ${SMARTCTL_EXPORTER_VERSION}](https://github.com/prometheus-community/smartctl_exporter/releases/tag/${SMARTCTL_EXPORTER_VERSION}).

Upstream publishes an amd64-only container image. This repackages their own release binary, unmodified, for
every architecture below.

## Use

\`\`\`
${IMAGE_REPO}:${RELEASE_TAG}
\`\`\`

The \`-${RELEASE_TAG##*-}\` suffix is OUR build revision of that upstream release: a rebuild for a base-image
bump keeps the upstream version and increments it. Pin the full tag. \`${IMAGE_REPO}:${SMARTCTL_EXPORTER_VERSION}\`
also moves to this build if you would rather track rebuilds by digest.

## What went into it

| Input | Pinned at |
|---|---|
| smartctl_exporter | [\`${SMARTCTL_EXPORTER_VERSION}\`](https://github.com/prometheus-community/smartctl_exporter/releases/tag/${SMARTCTL_EXPORTER_VERSION}) |
| Base image | \`${ALPINE_IMAGE}\` |
| Platforms | \`${PLATFORMS}\` |

Image digest \`${DIGEST}\`.

Licenses and the GPL-2.0 source pointer: see [NOTICE](https://github.com/${GITHUB_REPOSITORY}/blob/${RELEASE_TAG}/NOTICE).
EOF
}

write_release_env() {
cat > "${OUT_DIR}/release.env" <<EOF
RELEASE_TAG="${RELEASE_TAG}"
IMAGE_DIGEST="${DIGEST}"
IMAGE_REF="${IMAGE_REPO}:${RELEASE_TAG}"
EOF
  # Same facts, unquoted, for the workflow's attestation and release steps.
  [ -n "${GITHUB_OUTPUT:-}" ] && printf 'RELEASE_TAG=%s\nIMAGE_DIGEST=%s\nIMAGE_REF=%s\n' \
    "$RELEASE_TAG" "$DIGEST" "${IMAGE_REPO}:${RELEASE_TAG}" >> "$GITHUB_OUTPUT"
  return 0
}

print_result() {
  say "PUBLISHED ${IMAGE_REPO}:${RELEASE_TAG}"
  echo "   digest:  ${DIGEST}"
  echo "   assets:  ${OUT_DIR}"
  echo "   next:    make release   (creates the GitHub release; CI attests first)"
}

# ---- main ----

require docker jq curl
compute_fingerprint
assert_ghcr_token
resolve_build_revision
build_and_push
write_inputs_file "$RELEASE_TAG"
write_release_notes
write_release_env
print_result
