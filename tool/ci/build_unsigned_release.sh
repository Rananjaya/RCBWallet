#!/usr/bin/env bash
# Builds an UNSIGNED release APK for validation only (pull request CI).
#
# RCBWallet never signs release builds with the debug key: without
# android/key.properties, the Gradle task :app:validateReleaseSigning fails the
# build (see android/app/build.gradle.kts). For validation, this script skips
# only that task, so Gradle produces an unsigned APK:
#
#   build/app/outputs/apk/release/app-release-unsigned.apk
#
# The APK can't be installed or published. It proves that the release build
# (Dart AOT, resource shrinking, manifest merging) compiles, and lets
# tool/ci/verify_apk.sh --mode structure check the package ID, version and
# permissions.
#
# The script refuses to run when android/key.properties exists, so validation
# builds never touch signing material.
#
# Writes apk=<path> to $GITHUB_OUTPUT when that variable is set.
set -euo pipefail

OUT="build/app/outputs/apk/release/app-release-unsigned.apk"

if [[ -e android/key.properties ]]; then
  echo "::error title=Validation build::android/key.properties exists; validation builds must not use signing material."
  exit 1
fi

# Generates the Gradle wrapper and android/local.properties without building.
flutter build apk --release --config-only

rm -f "$OUT"
(cd android && ./gradlew --no-daemon :app:assembleRelease -x validateReleaseSigning)

[[ -f "$OUT" ]] || { echo "::error title=Validation build::unsigned release APK not found at $OUT"; exit 1; }
echo "Unsigned validation APK: $OUT"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "apk=$OUT" >> "$GITHUB_OUTPUT"
fi
