#!/usr/bin/env bash
# Tests tool/ci/verify_apk.sh against real APK variants derived from one input.
#
# Usage: verify_apk_test.sh <any-built-release-apk> [apk-with-INTERNET-permission]
#
# From the input APK it creates, in a temporary folder:
#   unsigned.apk   the same APK with every signature removed;
#   expected.apk   signed with a throwaway "expected" key;
#   other.apk      signed with a different throwaway key.
# The throwaway keys are generated here and deleted afterwards. No real signing
# secrets are involved.
#
# Needs: ANDROID_HOME (zipalign, apksigner, aapt2), keytool and zip.
set -uo pipefail

SRC="${1:?usage: $0 <apk> [apk-with-internet]}"
INTERNET_APK="${2:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
VERIFY="$HERE/../verify_apk.sh"
APP_ID="com.rananjaya.rcbwallet"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
BT="$(ls -d "$SDK"/build-tools/*/ | sed 's#/$##' | while read -r d; do [[ -x "$d/apksigner" && -x "$d/zipalign" ]] && echo "$d"; done \
  | awk -F/ '{v=$NF; split(v,p,/[.-]/); printf "%05d%05d%05d %s\n", p[1], p[2], p[3], $0}' | sort | tail -n1 | cut -d' ' -f2)"
[[ -n "$BT" ]] || { echo "no build-tools with apksigner and zipalign under $SDK"; exit 2; }

W="$(mktemp -d)"
FAKE_BT="$W/sdk/build-tools/99.0.0"
cleanup() {
  rm -f "$W"/*.apk "$W"/*.p12 "$W"/*.idsig "$W"/dummy "$FAKE_BT/aapt2" "$FAKE_BT/apksigner" 2>/dev/null
  rmdir "$FAKE_BT" "$W/sdk/build-tools" "$W/sdk" "$W" 2>/dev/null
}
trap cleanup EXIT
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

# --- Build test APKs ---------------------------------------------------------
# Rewriting the archive with zip drops the APK Signing Block (v2/v3); removing
# META-INF signature files drops any v1 signature.
cp "$SRC" "$W/stripped.apk"
printf 'x' > "$W/dummy"
(cd "$W" && zip -q stripped.apk dummy && zip -q -d stripped.apk dummy)
zip -q -d "$W/stripped.apk" 'META-INF/*.SF' 'META-INF/*.RSA' 'META-INF/*.EC' 'META-INF/*.DSA' 'META-INF/MANIFEST.MF' >/dev/null 2>&1 || true
"$BT/zipalign" -f -p 4 "$W/stripped.apk" "$W/unsigned.apk"

make_key() { # make_key <file> <cn>
  keytool -genkeypair -storetype PKCS12 -keystore "$1" -alias test -keyalg RSA -keysize 2048 \
    -validity 1 -dname "CN=$2" -storepass test-only-password -keypass test-only-password >/dev/null 2>&1
}
sign_with() { # sign_with <keystore> <out>
  "$BT/apksigner" sign --ks "$1" --ks-key-alias test --ks-pass pass:test-only-password \
    --v4-signing-enabled false --out "$2" "$W/unsigned.apk"
}
make_key "$W/expected.p12" "RCBWallet Test Expected"
make_key "$W/other.p12" "RCBWallet Test Other"
sign_with "$W/expected.p12" "$W/expected.apk"
sign_with "$W/other.p12" "$W/other.apk"
EXPECTED_SHA="$(keytool -list -v -keystore "$W/expected.p12" -storepass test-only-password 2>/dev/null \
  | sed -n 's/.*SHA256: //p' | head -n1)"
[[ -n "$EXPECTED_SHA" ]] || { echo "could not read throwaway certificate fingerprint"; exit 2; }

# Sanity: the "unsigned" APK really has no signature.
if "$BT/apksigner" verify "$W/unsigned.apk" >/dev/null 2>&1; then
  echo "FAIL  test setup: unsigned.apk still verifies"; exit 2
fi

# --- Structure mode (PR builds) -----------------------------------------------
check ok   "structure: unsigned APK passes structural validation" "Structure checks passed" -- \
  bash "$VERIFY" --mode structure "$W/unsigned.apk" "$APP_ID"
check ok   "structure: input APK passes" "Structure checks passed" -- \
  bash "$VERIFY" --mode structure "$SRC" "$APP_ID"
check fail "structure: wrong application id fails" "expected 'com.example.wrong'" -- \
  bash "$VERIFY" --mode structure "$W/unsigned.apk" com.example.wrong
check fail "structure: versionCode mismatch fails" "versionCode is" -- \
  env EXPECTED_VERSION_CODE=999999 bash "$VERIFY" --mode structure "$W/unsigned.apk" "$APP_ID"
check fail "structure: versionName mismatch fails" "versionName is" -- \
  env EXPECTED_VERSION_NAME=0.0.0-nope bash "$VERIFY" --mode structure "$W/unsigned.apk" "$APP_ID"

# --- Release mode -------------------------------------------------------------
check ok   "release: signed with expected cert passes" "signed with the expected release certificate" -- \
  bash "$VERIFY" --mode release "$W/expected.apk" "$APP_ID" "$EXPECTED_SHA"
check fail "release: unsigned APK fails" "could not verify the signature" -- \
  bash "$VERIFY" --mode release "$W/unsigned.apk" "$APP_ID" "$EXPECTED_SHA"
check fail "release: signed with a different key fails" "does not match the expected release certificate" -- \
  bash "$VERIFY" --mode release "$W/other.apk" "$APP_ID" "$EXPECTED_SHA"
check fail "release: missing expected cert argument fails" "requires the expected certificate" -- \
  bash "$VERIFY" --mode release "$W/expected.apk" "$APP_ID"
check fail "release: malformed expected cert fails" "not 64 hex" -- \
  bash "$VERIFY" --mode release "$W/expected.apk" "$APP_ID" "abc123"
check fail "invalid mode is rejected" "usage" -- \
  bash "$VERIFY" --mode lenient "$W/expected.apk" "$APP_ID"

# --- More than one signer -------------------------------------------------------
# Several signers are only allowed with schemes v1/v2, so this APK is signed
# with v2 only (minSdk 24 supports v2).
"$BT/apksigner" sign --v1-signing-enabled false --v3-signing-enabled false --v4-signing-enabled false \
  --ks "$W/expected.p12" --ks-key-alias test --ks-pass pass:test-only-password \
  --next-signer --ks "$W/other.p12" --ks-key-alias test --ks-pass pass:test-only-password \
  --out "$W/two-signers.apk" "$W/unsigned.apk" \
  || { echo "test setup: could not create two-signers.apk"; exit 2; }
check fail "release: APK with two signers fails" "expected exactly 1 signer certificate, found 2" -- \
  bash "$VERIFY" --mode release "$W/two-signers.apk" "$APP_ID" "$EXPECTED_SHA"

# --- Different apksigner output formats ------------------------------------------
# A wrapper around the real apksigner simulates other build-tools versions:
#   alt-text        "Signer (minSdkVersion=..., maxSdkVersion=...)" instead of "Signer #1"
#   no-digest-text  no "... digest:" text lines at all (unknown wording)
#   no-pem          --print-certs-pem unsupported, plus the alternative text
mkdir -p "$FAKE_BT"
ln -s "$BT/aapt2" "$FAKE_BT/aapt2"
cat > "$FAKE_BT/apksigner" <<EOF
#!/usr/bin/env bash
REAL="$BT/apksigner"
ALT='s/^Signer #1 /Signer (minSdkVersion=24, maxSdkVersion=2147483647) /'
case "\${FAKE_MODE:-}" in
  alt-text)       "\$REAL" "\$@" | sed -E "\$ALT"; exit "\${PIPESTATUS[0]}" ;;
  no-digest-text) "\$REAL" "\$@" | sed '/digest:/d'; exit "\${PIPESTATUS[0]}" ;;
  no-pem)
    for a in "\$@"; do
      [ "\$a" = "--print-certs-pem" ] && { echo "Unrecognized option: --print-certs-pem" >&2; exit 2; }
    done
    "\$REAL" "\$@" | sed -E "\$ALT"; exit "\${PIPESTATUS[0]}" ;;
  *) exec "\$REAL" "\$@" ;;
esac
EOF
chmod +x "$FAKE_BT/apksigner"
fake() { env ANDROID_HOME="$W/sdk" FAKE_MODE="$1" bash "$VERIFY" --mode release "$2" "$APP_ID" "$EXPECTED_SHA"; }
check ok   "format alt-text: expected key passes (PEM)" "method: PEM + openssl" -- fake alt-text "$W/expected.apk"
check fail "format alt-text: wrong key fails" "does not match" -- fake alt-text "$W/other.apk"
check ok   "format no-digest-text: expected key passes (PEM)" "method: PEM + openssl" -- fake no-digest-text "$W/expected.apk"
check fail "format no-digest-text: wrong key fails" "does not match" -- fake no-digest-text "$W/other.apk"
check ok   "format no-pem: expected key passes (text fallback)" "method: apksigner text output" -- fake no-pem "$W/expected.apk"
check fail "format no-pem: wrong key fails" "does not match" -- fake no-pem "$W/other.apk"
check fail "format no-pem: two signers fail" "found 2" -- fake no-pem "$W/two-signers.apk"
check fail "format no-pem: unsigned fails" "could not verify the signature" -- fake no-pem "$W/unsigned.apk"

# --- INTERNET permission (optional second APK, e.g. a debug build) -------------
if [[ -n "$INTERNET_APK" ]]; then
  check fail "structure: APK with INTERNET permission fails" "INTERNET" -- \
    bash "$VERIFY" --mode structure "$INTERNET_APK" "$APP_ID"
fi

echo "----- verify_apk.sh tests: $pass passed, $failn failed"
(( failn == 0 ))
