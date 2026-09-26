#!/usr/bin/env bash
# Builds every platform, pushes the manifest list to GHCR and stages the release assets for release.sh.
# A run that dies here leaves an image tag no release announced. The next run overwrites it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ---- state ----
# No GHCR_USER default. An empty one here would erase a value set in the environment.
RELEASE_TAG="" # set by resolve_build_revision
DIGEST=""      # set by build_and_push

# ---- functions ----

assert_ghcr_token() {
  : "${GHCR_TOKEN:=${GITHUB_TOKEN:-}}"
  [ -n "$GHCR_TOKEN" ] || die "GHCR_TOKEN (or GITHUB_TOKEN) is empty. Needs a token with write:packages for ${IMAGE_REPO}"
  GHCR_USER="${GHCR_USER:-${GITHUB_REPOSITORY%%/*}}"
}

# The next free build revision, read from the published releases. A run that pushed but never released gets
# its revision again. That is safe, because nothing consumes a tag that no release announced.
resolve_build_revision() {
  local auth=() releases existing revision
  say "resolving the build revision"
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  releases="$(curl -fsSL --retry 3 ${auth[@]+"${auth[@]}"} \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases?per_page=100" 2> /dev/null || true)"
  # All in jq, because grep exits 1 on no match, which is normal for a first release, and pipefail fails the build.
  existing="$(printf '%s' "$releases" | jq -r --arg t "$SMARTCTL_EXPORTER_VERSION" \
    '[.[]?.tag_name // empty | select(startswith($t + "-")) | ltrimstr($t + "-")
      | select(test("^[0-9]+$")) | tonumber] | max // 0' 2> /dev/null || echo 0)"
  [ -n "$existing" ] || existing=0
  revision=$((existing + 1))
  RELEASE_TAG="${SMARTCTL_EXPORTER_VERSION}-${revision}"
  if [ "$existing" -eq 0 ]; then
    echo "   ${RELEASE_TAG}  (first release for ${SMARTCTL_EXPORTER_VERSION})"
  else echo "   ${RELEASE_TAG}  (previous: ${SMARTCTL_EXPORTER_VERSION}-${existing})"; fi
}

# One buildx run pushes all three tags for every platform. `docker tag` names only a single-platform image.
build_and_push() {
  local cache_args=() tag_args=() t
  say "building and pushing ${PLATFORMS}"
  printf '%s' "$GHCR_TOKEN" | docker login "$GHCR_SERVER" -u "$GHCR_USER" --password-stdin > /dev/null \
    || die "docker login ${GHCR_SERVER} failed (is the token write:packages for ${GHCR_USER}?)"
  # Only a local run logs out. In CI the attestation step still needs the session to push to the registry.
  [ -z "${GITHUB_ACTIONS:-}" ] && trap 'docker logout "$GHCR_SERVER" >/dev/null 2>&1 || true' EXIT

  mapfile -t cache_args < <(buildx_cache_args)
  # The fixed build revision, plus two moving tags: the upstream version and latest.
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

# Lists every pin behind this image, so a reader can reproduce it without cloning the repo.
write_release_notes() {
  cat > "${OUT_DIR}/release-notes.md" << EOF
Multi-arch (${PLATFORMS}) build of [smartctl_exporter ${SMARTCTL_EXPORTER_VERSION}](https://github.com/prometheus-community/smartctl_exporter/releases/tag/${SMARTCTL_EXPORTER_VERSION}).

Upstream publishes an amd64-only container image. This repackages their own release binary, unmodified, for
every architecture below.

## Use

\`\`\`
${IMAGE_REPO}:${RELEASE_TAG}
\`\`\`

The \`-${RELEASE_TAG##*-}\` suffix is this repo's build revision of that upstream release. A rebuild for a
base-image bump keeps the upstream version and increments the revision. Pin the full tag.
\`${IMAGE_REPO}:${SMARTCTL_EXPORTER_VERSION}\` also moves to this build, if you track rebuilds by digest instead.

## What went into it

| Input | Pinned at |
|---|---|
| smartctl_exporter | [\`${SMARTCTL_EXPORTER_VERSION}\`](https://github.com/prometheus-community/smartctl_exporter/releases/tag/${SMARTCTL_EXPORTER_VERSION}) |
| Base image | \`${ALPINE_IMAGE}\` |
| Platforms | \`${PLATFORMS}\` |

Image digest \`${DIGEST}\`.

The licenses and the GPL-2.0 source offer are in [NOTICE](https://github.com/${GITHUB_REPOSITORY}/blob/${RELEASE_TAG}/NOTICE).
EOF
}

write_release_env() {
  cat > "${OUT_DIR}/release.env" << EOF
RELEASE_TAG="${RELEASE_TAG}"
IMAGE_DIGEST="${DIGEST}"
IMAGE_REF="${IMAGE_REPO}:${RELEASE_TAG}"
EOF
  # The same values, unquoted, for the workflow's attestation and release steps.
  [ -n "${GITHUB_OUTPUT:-}" ] && printf 'RELEASE_TAG=%s\nIMAGE_DIGEST=%s\nIMAGE_REF=%s\n' \
    "$RELEASE_TAG" "$DIGEST" "${IMAGE_REPO}:${RELEASE_TAG}" >> "$GITHUB_OUTPUT"
  return 0
}

print_result() {
  say "published ${IMAGE_REPO}:${RELEASE_TAG}"
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
