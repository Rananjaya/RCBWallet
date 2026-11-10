#!/usr/bin/env bash
# Validates the app version in pubspec.yaml against existing release tags.
#
# pubspec.yaml is the source of truth:  version: MAJOR.MINOR.PATCH+BUILD
# Release tags are:                     vMAJOR.MINOR.PATCH
#
# Rules:
#   - The version must be strict semver: no leading zeros, no pre-release, and
#     a build number from 1 to 2100000000 (the Android versionCode limit).
#   - It must be higher than the latest existing vX.Y.Z tag.
#   - The build number must be higher than the build number in pubspec.yaml at
#     that tag.
#   - If there are no release tags yet, any valid version is accepted as the
#     first release.
#
# Modes:
#   --mode pr       (default) fail if the tag for this version already exists.
#   --mode release  if the tag already exists and points at HEAD, report
#                   tag_exists=true so a failed release can resume; if it points
#                   anywhere else, fail.
#
# Needs the full history and tags (actions/checkout with fetch-depth: 0).
# Writes version, build, tag, previous_tag and tag_exists to $GITHUB_OUTPUT
# when that variable is set.
set -euo pipefail

MODE="pr"
if [[ "${1:-}" == "--mode" ]]; then MODE="${2:-}"; fi
if [[ "$MODE" != "pr" && "$MODE" != "release" ]]; then
  echo "usage: $0 [--mode pr|release]" >&2; exit 2
fi
PUBSPEC="${PUBSPEC:-pubspec.yaml}"

fail() { echo "::error title=Version check::$*"; echo "Version check failed: $*" >&2; exit 1; }

SEMVER_TAG_RE='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
PUBSPEC_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\+([1-9][0-9]*)$'

# Reads "version:" from pubspec text on stdin, prints "MAJOR MINOR PATCH BUILD".
parse_pubspec_version() {
  local line raw
  line="$(grep -E '^version:' | head -n1 || true)"
  [[ -n "$line" ]] || return 1
  raw="${line#version:}"
  raw="$(printf '%s' "$raw" | tr -d "[:space:]\"'")"
  [[ "$raw" =~ $PUBSPEC_RE ]] || { printf '%s' "$raw"; return 2; }
  echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]}"
}

# Compares two "MAJOR MINOR PATCH" triples; prints -1, 0 or 1.
cmp_semver() {
  local -a a b
  read -r -a a <<< "$1"
  read -r -a b <<< "$2"
  for i in 0 1 2; do
    if (( 10#${a[$i]} > 10#${b[$i]} )); then echo 1; return; fi
    if (( 10#${a[$i]} < 10#${b[$i]} )); then echo -1; return; fi
  done
  echo 0
}

# --- Current version -------------------------------------------------------
[[ -f "$PUBSPEC" ]] || fail "$PUBSPEC not found"
set +e
parsed="$(parse_pubspec_version < "$PUBSPEC")"; rc=$?
set -e
if (( rc == 1 )); then fail "no 'version:' line in $PUBSPEC"; fi
if (( rc == 2 )); then
  fail "invalid version '$parsed' in $PUBSPEC (expected MAJOR.MINOR.PATCH+BUILD, e.g. 1.0.1+2, no leading zeros or pre-release suffix)"
fi
read -r MAJOR MINOR PATCH BUILD <<< "$parsed"
(( BUILD <= 2100000000 )) || fail "build number $BUILD exceeds Android's maximum versionCode (2100000000)"
VERSION="$MAJOR.$MINOR.$PATCH"
TAG="v$VERSION"

# --- Existing release tags -------------------------------------------------
TAG_EXISTS=false
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  TAG_EXISTS=true
  if [[ "$MODE" == "pr" ]]; then
    fail "$TAG has already been released; bump 'version:' in $PUBSPEC above it"
  fi
  tag_commit="$(git rev-parse "refs/tags/$TAG^{commit}")"
  head_commit="$(git rev-parse HEAD)"
  if [[ "$tag_commit" != "$head_commit" ]]; then
    fail "$TAG already exists on a different commit ($tag_commit); refusing to release $head_commit under the same version"
  fi
fi

# Latest semver tag, excluding this version's own tag (relevant when resuming).
PREV_TAG=""
PREV_TRIPLE=""
while IFS= read -r t; do
  [[ "$t" =~ $SEMVER_TAG_RE ]] || continue
  [[ "$t" == "$TAG" ]] && continue
  triple="${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
  if [[ -z "$PREV_TAG" || "$(cmp_semver "$triple" "$PREV_TRIPLE")" == 1 ]]; then
    PREV_TAG="$t"; PREV_TRIPLE="$triple"
  fi
done < <(git tag --list 'v*')

if [[ -z "$PREV_TAG" ]]; then
  echo "No previous release tag found: $VERSION+$BUILD will be the first release."
else
  [[ "$(cmp_semver "$MAJOR $MINOR $PATCH" "$PREV_TRIPLE")" == 1 ]] \
    || fail "version $VERSION is not higher than the latest release $PREV_TAG"
  set +e
  prev_parsed="$(git show "$PREV_TAG:$PUBSPEC" 2>/dev/null | parse_pubspec_version)"; prc=$?
  set -e
  (( prc == 0 )) || fail "could not read a valid version from $PUBSPEC at $PREV_TAG"
  read -r _ _ _ PREV_BUILD <<< "$prev_parsed"
  (( BUILD > PREV_BUILD )) \
    || fail "build number $BUILD must be higher than $PREV_BUILD (the build number of $PREV_TAG)"
  echo "OK: $VERSION+$BUILD is higher than $PREV_TAG (build $PREV_BUILD)."
fi

if [[ "$TAG_EXISTS" == true ]]; then
  echo "Tag $TAG already exists on this commit; the release step will resume."
fi
echo "version=$VERSION build=$BUILD tag=$TAG previous_tag=${PREV_TAG:-none} tag_exists=$TAG_EXISTS"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "version=$VERSION"
    echo "build=$BUILD"
    echo "tag=$TAG"
    echo "previous_tag=$PREV_TAG"
    echo "tag_exists=$TAG_EXISTS"
  } >> "$GITHUB_OUTPUT"
fi
