#!/usr/bin/env bash
# Creates the GitHub release from the assets publish.sh staged. The release list is the only record of a
# build revision, so should_build.sh and publish.sh read nothing else.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ---- functions ----

load_staged_release() {
  [ -f "${OUT_DIR}/release.env" ] || die "missing ${OUT_DIR}/release.env, run: make publish"
  # shellcheck disable=SC1090
  source "${OUT_DIR}/release.env" # publish.sh writes RELEASE_TAG, IMAGE_DIGEST, IMAGE_REF
}

assert_release_absent() {
  if gh release view "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" > /dev/null 2>&1; then
    die "release ${RELEASE_TAG} already exists. publish.sh should have picked the next revision."
  fi
}

create_release() {
  say "creating release ${RELEASE_TAG}"
  gh release create "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" \
    --title "$RELEASE_TAG" --notes-file "${OUT_DIR}/release-notes.md" \
    "${OUT_DIR}/build-inputs.json"
}

print_result() {
  say "released"
  echo "   https://github.com/${GITHUB_REPOSITORY}/releases/tag/${RELEASE_TAG}"
}

# ---- main ----

require gh
load_staged_release
assert_release_absent
create_release
print_result
