#!/usr/bin/env bash
# Tests tool/ci/check_version.sh against throwaway Git repositories.
#
# Usage: check_version_test.sh
#
# Each case creates a temporary repository with a pubspec.yaml and, where
# needed, release tags. Nothing touches the real repository or its tags.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/../check_version.sh"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
pass=0; failn=0

check() { # check <ok|fail> <description> <expected substring or ""> -- <command...>
  local want="$1" desc="$2" needle="$3"; shift 4
  local out rc got
  out="$("$@" 2>&1)"; rc=$?
  got=ok; (( rc == 0 )) || got=fail
  if [[ "$got" == "$want" && ( -z "$needle" || "$out" == *"$needle"* ) ]]; then
    pass=$((pass+1)); printf 'PASS  %s\n' "$desc"
  else
    failn=$((failn+1)); printf 'FAIL  %s (wanted %s, got %s)\n%s\n' "$desc" "$want" "$got" "$out"
  fi
}

# new_repo <name> <version-line>: a repo with one commit containing pubspec.yaml.
new_repo() {
  local dir="$W/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "ci-test@example.invalid"
  git -C "$dir" config user.name "CI test"
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" config tag.gpgsign false
  printf 'name: wallet\n%s\n' "$2" > "$dir/pubspec.yaml"
  git -C "$dir" add pubspec.yaml
  git -C "$dir" commit -q -m "version"
  echo "$dir"
}

# set_version <dir> <version-line>: commit a new version line.
set_version() {
  printf 'name: wallet\n%s\n' "$2" > "$1/pubspec.yaml"
  git -C "$1" commit -q -am "bump"
}

run() { # run <dir> [mode]
  (cd "$1" && bash "$CHECK" --mode "${2:-pr}")
}

# --- Format -----------------------------------------------------------------
d="$(new_repo first 'version: 1.0.0+1')"
check ok   "first release 1.0.0+1 with no tags is accepted" "will be the first release" -- run "$d"
check ok   "outputs tag v1.0.0" "tag=v1.0.0" -- run "$d"

d="$(new_repo nobuild 'version: 1.0.0')"
check fail "missing build number fails" "invalid version" -- run "$d"
d="$(new_repo short 'version: 1.0+1')"
check fail "MAJOR.MINOR only fails" "invalid version" -- run "$d"
d="$(new_repo lead 'version: 01.0.0+1')"
check fail "leading zero fails" "invalid version" -- run "$d"
d="$(new_repo pre 'version: 1.0.0-beta+1')"
check fail "pre-release suffix fails" "invalid version" -- run "$d"
d="$(new_repo zero 'version: 1.0.0+0')"
check fail "build number 0 fails" "invalid version" -- run "$d"
d="$(new_repo huge 'version: 1.0.0+2100000001')"
check fail "build number above Android maximum fails" "exceeds Android's maximum versionCode" -- run "$d"
d="$(new_repo text 'version: one.two.three+4')"
check fail "non-numeric version fails" "invalid version" -- run "$d"
d="$(new_repo noline 'description: no version here')"
check fail "missing version line fails" "no 'version:' line" -- run "$d"
d="$(new_repo quoted 'version: "1.0.0+1"')"
check ok   "quoted version is accepted" "first release" -- run "$d"
check fail "invalid mode is rejected" "usage" -- bash -c "cd '$d' && bash '$CHECK' --mode lenient"

# --- Against an existing release v1.0.0 (build 1) ---------------------------
d="$(new_repo released 'version: 1.0.0+1')"
git -C "$d" tag v1.0.0
check fail "duplicate version (tag exists) fails in PR mode" "has already been released" -- run "$d"

set_version "$d" 'version: 1.0.1+2'
check ok   "higher version and build passes" "is higher than v1.0.0" -- run "$d"

set_version "$d" 'version: 1.0.1+1'
check fail "same build number as last release fails" "must be higher than 1" -- run "$d"

set_version "$d" 'version: 0.9.0+5'
check fail "lower version fails" "not higher than the latest release v1.0.0" -- run "$d"

set_version "$d" 'version: 1.0.0+2'
check fail "same version, higher build, fails (tag exists)" "has already been released" -- run "$d"

# --- Release mode -----------------------------------------------------------
d="$(new_repo resume 'version: 1.0.0+1')"
git -C "$d" tag v1.0.0
check ok   "release mode: tag on HEAD resumes" "tag_exists=true" -- run "$d" release

# A later commit that keeps the same version (only another file changes).
echo "change" > "$d/other.txt"
git -C "$d" add other.txt
git -C "$d" commit -q -m "unrelated change"
check fail "release mode: same version on a different commit fails" "already exists on a different commit" -- run "$d" release

# --- Tag formats --------------------------------------------------------------
d="$(new_repo othertags 'version: 1.0.0+1')"
git -C "$d" tag release-2.0
git -C "$d" tag v2.0
check ok   "non-vX.Y.Z tags are ignored" "first release" -- run "$d"

echo "----- check_version.sh tests: $pass passed, $failn failed"
(( failn == 0 ))
