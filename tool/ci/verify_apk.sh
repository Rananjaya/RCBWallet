#!/usr/bin/env bash
# Verifies an Android APK.
#
# Usage:
#   verify_apk.sh --mode structure <apk> <application-id>
#   verify_apk.sh --mode release   <apk> <application-id> <expected-cert-sha256>
#
# Both modes check:
#   - the package name equals <application-id>;
#   - android.permission.INTERNET is not requested;
#   - versionName / versionCode match EXPECTED_VERSION_NAME /
#     EXPECTED_VERSION_CODE, when those variables are set.
#
# --mode structure  For pull-request validation builds, which are not
#                   release-signed (no secrets in PR workflows). Signatures
#                   aren't checked at all.
# --mode release    For release builds. Additionally requires that:
#                   - apksigner verifies the signature;
#                   - there is exactly one signer certificate;
#                   - its SHA-256 equals <expected-cert-sha256> (hex; colons and
#                     case are ignored). The argument is mandatory.
#                   An unsigned APK, or one signed with any other key (including
#                   the debug key), fails.
#
# Uses aapt2 and apksigner from the newest Android build-tools under
# $ANDROID_HOME (or $ANDROID_SDK_ROOT).
set -euo pipefail

fail() { echo "::error title=APK verification::$*"; echo "APK verification failed: $*" >&2; exit 1; }
usage() { echo "usage: $0 --mode structure|release <apk> <application-id> [expected-cert-sha256]" >&2; exit 2; }

[[ "${1:-}" == "--mode" ]] || usage
MODE="${2:-}"
[[ "$MODE" == "structure" || "$MODE" == "release" ]] || usage
APK="${3:-}"; APP_ID="${4:-}"; EXPECTED_CERT="${5:-}"
[[ -n "$APK" && -n "$APP_ID" ]] || usage
if [[ "$MODE" == "release" && -z "$EXPECTED_CERT" ]]; then
  fail "release mode requires the expected certificate SHA-256"
fi

[[ -f "$APK" ]] || fail "APK not found: $APK"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[[ -n "$SDK" && -d "$SDK/build-tools" ]] || fail "Android SDK build-tools not found (set ANDROID_HOME)"

# Newest build-tools directory, comparing version components numerically.
BT=""
for d in "$SDK"/build-tools/*/; do
  d="${d%/}"
  [[ -x "$d/aapt2" && -x "$d/apksigner" ]] || continue
  if [[ -z "$BT" ]]; then BT="$d"; continue; fi
  newer="$(printf '%s\n%s\n' "$(basename "$BT")" "$(basename "$d")" \
    | awk -F'[.-]' '{printf "%05d%05d%05d %s\n", $1, $2, $3, $0}' | sort | tail -n1 | cut -d' ' -f2)"
  [[ "$newer" == "$(basename "$d")" ]] && BT="$d"
done
[[ -n "$BT" ]] || fail "no build-tools with aapt2 and apksigner found under $SDK/build-tools"
echo "Mode: $MODE | build-tools: $(basename "$BT")"

# --- Structure checks (both modes) -----------------------------------------
BADGING="$("$BT/aapt2" dump badging "$APK")" || fail "aapt2 could not read $APK"
PKG_LINE="$(printf '%s\n' "$BADGING" | grep -m1 '^package:' || true)"
[[ -n "$PKG_LINE" ]] || fail "no package line in aapt2 output"
PKG="$(printf '%s\n' "$PKG_LINE" | sed -n "s/.* name='\([^']*\)'.*/\1/p")"
VNAME="$(printf '%s\n' "$PKG_LINE" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")"
VCODE="$(printf '%s\n' "$PKG_LINE" | sed -n "s/.*versionCode='\([^']*\)'.*/\1/p")"

[[ "$PKG" == "$APP_ID" ]] || fail "package is '$PKG', expected '$APP_ID'"
echo "OK: package $PKG (versionName $VNAME, versionCode $VCODE)"

if [[ -n "${EXPECTED_VERSION_NAME:-}" ]]; then
  [[ "$VNAME" == "$EXPECTED_VERSION_NAME" ]] || fail "versionName is '$VNAME', expected '$EXPECTED_VERSION_NAME'"
  echo "OK: versionName matches $EXPECTED_VERSION_NAME"
fi
if [[ -n "${EXPECTED_VERSION_CODE:-}" ]]; then
  [[ "$VCODE" == "$EXPECTED_VERSION_CODE" ]] || fail "versionCode is '$VCODE', expected '$EXPECTED_VERSION_CODE'"
  echo "OK: versionCode matches $EXPECTED_VERSION_CODE"
fi

if printf '%s\n' "$BADGING" | grep -q "uses-permission: name='android.permission.INTERNET'"; then
  fail "APK requests android.permission.INTERNET (RCBWallet release builds must stay offline; see RELEASE.md)"
fi
echo "OK: no INTERNET permission"

if [[ "$MODE" == "structure" ]]; then
  echo "Structure checks passed (signature not checked in structure mode)."
  exit 0
fi

# --- Release signing checks --------------------------------------------------
echo "apksigner $("$BT/apksigner" version 2>/dev/null || echo '?')"
# 1. The signature itself must verify. An unsigned or tampered APK fails here.
if ! VERIFY_OUT="$("$BT/apksigner" verify --verbose "$APK" 2>&1)"; then
  printf '%s\n' "$VERIFY_OUT" | sed 's/^/  apksigner: /'
  fail "apksigner could not verify the signature (unsigned or invalid APK)"
fi
printf '%s\n' "$VERIFY_OUT" | grep -E '^(Verifies|Verified using|Number of signers)' | sed 's/^/  /' || true

# 2. Collect the signer certificates.
#    Primary method: apksigner prints each signer certificate as PEM
#    (--print-certs-pem), and openssl computes its SHA-256. This doesn't depend
#    on the wording of apksigner's text output, which differs between
#    build-tools versions.
#    Fallback: if no PEM certificate is printed (older apksigner), parse the
#    "... certificate SHA-256 digest: <hex>" text lines.
#    "Source Stamp" lines describe a separate certificate, not a signer, and
#    are ignored.
CERTS="$("$BT/apksigner" verify --print-certs-pem "$APK" 2>&1)" || CERTS=""
DIGESTS=()
METHOD=""
if printf '%s\n' "$CERTS" | grep -q -- '-----BEGIN CERTIFICATE-----'; then
  METHOD="PEM + openssl"
  block=""; in_block=false
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" == "-----BEGIN CERTIFICATE-----" ]]; then in_block=true; block="$line"; continue; fi
    if $in_block; then
      block+=$'\n'"$line"
      if [[ "$line" == "-----END CERTIFICATE-----" ]]; then
        in_block=false
        fp="$(printf '%s\n' "$block" | openssl x509 -noout -fingerprint -sha256 2>/dev/null \
          | sed 's/^.*=//' | tr -d ':' | tr 'A-F' 'a-f')" || fp=""
        [[ "$fp" =~ ^[0-9a-f]{64}$ ]] || fail "could not compute the SHA-256 of a signer certificate (openssl)"
        DIGESTS+=("$fp")
      fi
    fi
  done <<< "$CERTS"
else
  METHOD="apksigner text output"
  CERTS="$("$BT/apksigner" verify --print-certs "$APK" 2>&1)" || fail "apksigner --print-certs failed"
  TEXT_RE='certificate SHA-256 digest: ([0-9a-fA-F]{64})[[:space:]]*$'
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ "$line" == Source\ Stamp* ]] && continue
    if [[ "$line" =~ $TEXT_RE ]]; then
      DIGESTS+=("$(printf '%s' "${BASH_REMATCH[1]}" | tr 'A-F' 'a-f')")
    fi
  done <<< "$CERTS"
fi

UNIQUE="$(printf '%s\n' ${DIGESTS[@]+"${DIGESTS[@]}"} | sed '/^$/d' | sort -u)"
COUNT="$(printf '%s' "$UNIQUE" | grep -c . || true)"
if [[ "$COUNT" != 1 ]]; then
  # Certificate details are public information; print the non-PEM lines so
  # the log shows what apksigner reported.
  printf '%s\n' "$CERTS" | grep -vE '^[A-Za-z0-9+/=]{40,}$' | sed 's/^/  apksigner: /'
  fail "expected exactly 1 signer certificate, found $COUNT (method: $METHOD)"
fi
ACTUAL_CERT="$UNIQUE"
echo "OK: signature verifies with exactly one signer certificate (method: $METHOD)"
echo "Signer certificate SHA-256: $ACTUAL_CERT"

WANT="$(printf '%s' "$EXPECTED_CERT" | tr -d ':[:space:]' | tr 'A-F' 'a-f')"
[[ "$WANT" =~ ^[0-9a-f]{64}$ ]] || fail "expected certificate SHA-256 is not 64 hex characters"
[[ "$ACTUAL_CERT" == "$WANT" ]] \
  || fail "signing certificate $ACTUAL_CERT does not match the expected release certificate $WANT"
echo "OK: signed with the expected release certificate"
