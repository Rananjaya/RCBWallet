# Releasing RCBWallet

How RCBWallet is versioned, validated, signed and published.

> **Never commit or share signing secrets.** These are git-ignored and must
> stay off GitHub: `android/key.properties`, `*.jks`, `*.keystore`, `*.p12`,
> credential notes and APKs. CI only receives signing material through
> encrypted secrets on the protected `production` environment.

> **Security status:** RCBWallet has not been independently audited. See
> [docs/SECURITY_AUDIT_REPORT.md](docs/SECURITY_AUDIT_REPORT.md) for open
> findings before using a release with real card information.

## How a release happens

```text
feature branch ──► pull request into main
                     │  CI: Analyze and test · Version check · Release build check
                     ▼  (all required to pass; see "Branch protection")
                   merge
                     │
                     ▼  Release workflow (push to main)
   Validate release: analyze → test → version check → release doesn't exist yet
                     │  (any failure: nothing is published, no approval is requested)
                     ▼
   "production" environment: waits for a required reviewer to approve
                     │  (reject or ignore it: nothing is published)
                     ▼
   Build and publish: signed build → verify APK and certificate
                     │  (any failure: nothing is published)
                     ▼
   tag vX.Y.Z  →  GitHub Release "RCBWallet X.Y.Z"
                  ├─ RCBWallet-X.Y.Z-release.apk
                  └─ RCBWallet-X.Y.Z-release.apk.sha256
```

Each merge into `main` starts exactly one release, so **every pull request
into `main` must raise the version**, even one that only changes documentation.

## Versioning

`pubspec.yaml` is the single source of truth:

```yaml
version: 1.0.0+1   # MAJOR.MINOR.PATCH+BUILD
```

| Part | Becomes | Rule |
|---|---|---|
| `1.0.0` | Android `versionName`, Git tag `v1.0.0`, release title "RCBWallet 1.0.0", APK name `RCBWallet-1.0.0-release.apk` | [Semantic versioning](https://semver.org); must be higher than the latest release tag |
| `+1` | Android `versionCode` | Must be higher than the build number of the latest release. Android won't install an update with an equal or lower code. |

### Choosing the version

CI checks that the version went **up**. It doesn't decide *how much*; that's
your call when you open the pull request.

| Bump | When | Example |
|---|---|---|
| **MAJOR** (`1.4.2` → `2.0.0`) | A breaking change | Saved data or backups from older versions can't be read; minimum Android version raised |
| **MINOR** (`1.4.2` → `1.5.0`) | A backward-compatible feature | New card type, new currency, new setting |
| **PATCH** (`1.4.2` → `1.4.3`) | A backward-compatible fix or small change | Bug fix, layout fix, documentation or CI-only change |

Always add 1 to the build number, whatever kind of bump it is. Reset MINOR and
PATCH to 0 when you bump MAJOR, and reset PATCH when you bump MINOR.

### Bumping the version

1. On your feature branch, edit the `version:` line in `pubspec.yaml`, for
   example `1.0.0+1` → `1.0.1+2`.
2. Commit it with your other changes and open the pull request.
3. **Version check** confirms the bump. To check locally first:

   ```bash
   git fetch --tags
   bash tool/ci/check_version.sh
   ```

**What the check enforces** (`tool/ci/check_version.sh`):

- **Format:** `MAJOR.MINOR.PATCH+BUILD`. No leading zeros, no pre-release
  suffix (`-beta`), and a build number from 1 to 2,100,000,000.
- **Higher version:** above the latest `vX.Y.Z` tag. Tags in other formats are
  ignored.
- **Higher build number:** above the build number in `pubspec.yaml` at that
  tag.
- **No duplicates:** the `vX.Y.Z` tag for this version mustn't exist yet.
- **First release:** if there are no release tags at all, any valid version is
  accepted. That will be `1.0.0+1`.

## Pull request validation

`.github/workflows/ci.yml` runs on every pull request into `main`, and on
pushes to `feature/**` branches. It runs three jobs:

| Check name | What it does |
|---|---|
| **Analyze and test** | `flutter pub get`, `flutter analyze`, `flutter test` |
| **Version check** | Runs `check_version.sh` against the tags (pull requests only), then its self-tests (`tool/ci/tests/check_version_test.sh`) |
| **Release build check** | Builds an **unsigned** release APK with `tool/ci/build_unsigned_release.sh` and checks it with `verify_apk.sh --mode structure`: package ID, version name and code, no INTERNET permission. Then runs the script's self-tests (`tool/ci/tests/verify_apk_test.sh`), using a debug APK as the "INTERNET present" negative sample. |

**Security:**

- It uses the plain `pull_request` trigger and has read-only permissions.
- It has **no access to signing secrets**, so pull requests from forks can't
  reach the keystore.
- RCBWallet never signs a release build with the debug key. The validation
  build skips only the `:app:validateReleaseSigning` Gradle task, so the APK is
  **unsigned**. It's only a compile check and is never uploaded.
- Flutter is pinned to the version the tests are verified with (`3.47.9`); see
  `FLUTTER_VERSION` in the workflows.

## Development builds

`.github/workflows/development-build.yml` builds a debug APK on every push to a
`feature/**` branch, or manually for any branch (*Actions* → *Development
build* → *Run workflow*).

- Download it from the run's **Artifacts** section:
  `RCBWallet-<version>-<commit>-debug.apk` with a `.sha256` file. Artifacts are
  kept for 14 days.
- No signing secrets are used. Each run is signed with that runner's own
  temporary debug key, so **uninstall the previous development build before
  installing a newer one** (this deletes its app data).
- Debug APKs request INTERNET for Flutter development tools. **Use dummy data
  only.** Never store real card details in a development build, and never
  distribute one.

## Automatic releases

`.github/workflows/release.yml` runs on every push to `main`. With branch
protection on, that means every merged pull request. It runs only in
`Rananjaya/RCBWallet` on `main`, never on forks or feature branches.

**Job 1: Validate release** (no secrets, no environment)

1. Checks out the exact merged commit, with full history and tags.
2. Runs `flutter analyze` and `flutter test` again.
3. Runs `check_version.sh --mode release`, and stops if a GitHub Release for
   the version already exists.

**Job 2: Build and publish release** (runs only if job 1 passed)

1. Waits for a required reviewer to approve the **`production`** environment.
   Only then can the job read the signing secrets.
2. Waits for any earlier release runs to finish (merge order).
3. Re-runs the version and existing-release checks, in case something changed
   while it waited.
4. Checks that the `RELEASE_CERT_SHA256` variable is a valid SHA-256.
5. Decodes the keystore from secrets into the runner's temporary folder (owner
   access only) and writes `android/key.properties`.
6. Builds the signed universal APK with `flutter build apk --release`. The
   Gradle build itself refuses to continue if the keystore or any credential
   is missing or invalid.
7. Runs `tool/ci/verify_apk.sh --mode release`:
   - the package is `com.rananjaya.rcbwallet`;
   - there's no INTERNET permission;
   - the versionName and versionCode match `pubspec.yaml`;
   - the signature verifies, with **exactly one** signer certificate;
   - that certificate's SHA-256 equals `RELEASE_CERT_SHA256`.

   An unsigned APK, or one signed with any other key (including a debug key),
   fails here.
8. Copies the APK to `RCBWallet-X.Y.Z-release.apk` and writes a `.sha256` file.
9. Pushes tag `vX.Y.Z` on the merged commit. It never force-pushes, so an
   existing tag can't be moved.
10. Publishes the GitHub Release "RCBWallet X.Y.Z" with the APK and checksum.
    The notes are generated from the merged pull requests.
11. Deletes the keystore and `key.properties` from the runner, even if an
    earlier step failed.

**Safety rules:**

- **Approval:** nothing can be signed or published without a reviewer
  approving the `production` deployment. Rejecting it publishes nothing.
- **Permissions:** the workflow is read-only by default. Only the release job
  gets `contents: write`, to push the tag and create the release, and
  `actions: read`, to see earlier runs.
- **Every merge gets its own release, in merge order:** the release job waits
  until every earlier run of this workflow has finished (first in, first out,
  by run number). If several pull requests are merged quickly, approve (or
  reject) their release runs in merge order. The wait gives up after 75
  minutes with an error; re-run the job once the earlier runs finish.
- **Why there's no `concurrency:` group:** GitHub keeps only one pending run per
  group and cancels older pending ones, which would skip versions.
- **No conflicting tags:** tags are pushed without `--force`, so a tag can never
  be overwritten. The version check also rejects a version whose tag already
  exists.
- **Pinned actions:** only `actions/checkout`, `actions/setup-java`,
  `subosito/flutter-action` and (for development builds)
  `actions/upload-artifact` are used, each pinned to a commit SHA. Releases are
  published with the GitHub CLI that is preinstalled on the runner.

## GitHub configuration (manual, one-time)

None of this is created by the workflows. Set it up before the first release.

### 1. The release keystore

Android identifies an app by its **application ID plus its signing
certificate**. Updates only install if they are signed with the same key, so
this key must stay the same for the life of the app.

- Create a **new, dedicated** RCBWallet keystore. Never reuse another app's
  key (for example RCBFlow's).
- Keep it, and its passwords, in a password manager plus an offline backup. If
  it's lost, existing installs can never receive updates.

Create it yourself on your own computer; `keytool` asks for the passwords
interactively, so they don't end up in your shell history:

```bash
mkdir -p ~/.android/keystores
keytool -genkeypair -v -storetype PKCS12 \
  -keystore ~/.android/keystores/rcbwallet-release.jks \
  -alias rcbwallet-release -keyalg RSA -keysize 4096 -validity 10000
```

Read its certificate fingerprint (public, not a secret):

```bash
keytool -list -v -keystore ~/.android/keystores/rcbwallet-release.jks \
  -alias rcbwallet-release | grep 'SHA256:'
```

### 2. The `production` environment

*Settings* → *Environments* → *New environment* → name it **`production`**.

- **Required reviewers:** add yourself (and anyone else allowed to publish).
- **Prevent self-review:** leave it off if you're the only maintainer, or you
  won't be able to approve your own releases.
- **Deployment branches and tags:** *Selected branches and tags* → add `main`.

### 3. Environment secrets (in `production`, not repository secrets)

In the `production` environment → *Environment secrets* → *Add secret*:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | The keystore file, base64-encoded (see below) |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password, from your password manager |
| `ANDROID_KEY_ALIAS` | `rcbwallet-release` (or the alias you chose) |
| `ANDROID_KEY_PASSWORD` | The key password. For a PKCS12 keystore this is the **same** as the keystore password. |

**Encode the keystore without showing it on screen** (macOS):

```bash
base64 -i ~/.android/keystores/rcbwallet-release.jks | pbcopy   # copies to clipboard
# paste into the ANDROID_KEYSTORE_BASE64 secret, then clear the clipboard:
pbcopy < /dev/null
```

**Passwords:** paste them directly from your password manager into the GitHub
secret form. Don't put them in shell commands, files in the repository, issues
or chat.

Because the secrets belong to the `production` environment, only the approved
release job can read them. The CI and development-build workflows have no
access. GitHub hides secret values in logs, and the workflows never print them.
If a secret is missing, the release fails at *Set up release signing* and names
the missing secret. Nothing is published.

### 4. Environment variable `RELEASE_CERT_SHA256`

In the `production` environment → *Environment variables* → *Add variable*:

| Variable | Value |
|---|---|
| `RELEASE_CERT_SHA256` | The `SHA256:` fingerprint from step 1, e.g. `AB:CD:…` (colons and case are ignored) |

It's public, so it's a variable rather than a secret. Every release APK must be
signed with exactly this certificate.

### 5. GitHub Actions permissions

*Settings* → *Actions* → *General*:

- **Actions permissions:** allow actions. To restrict them, allow only
  `actions/checkout`, `actions/setup-java`, `actions/upload-artifact` and
  `subosito/flutter-action`.
- **Workflow permissions:** *Read repository contents and packages
  permissions* (read-only default). The release job requests its own write
  permission.
- Leave *Allow GitHub Actions to create and approve pull requests* **off**.
- **Fork pull request workflows:** require approval for outside
  collaborators.

### 6. Branch protection for `main`

Adding workflow files **doesn't** protect `main` by itself. Set it up under
*Settings* → *Rules* → *Rulesets* → *New branch ruleset*, or the classic
*Settings* → *Branches* → *Add branch protection rule*:

- **Target:** `main` (default branch).
- **Require a pull request before merging.**
- **Require status checks to pass**, and select exactly:
  - `Analyze and test`
  - `Version check`
  - `Release build check`
- **Require branches to be up to date before merging** (recommended). This
  re-runs Version check against the latest tags, so two pull requests can't
  claim the same version.
- **Block force pushes** and **restrict deletions**.
- **Don't allow bypassing** the rules, or in classic rules, *Include
  administrators*.

Status checks only appear in the picker after they have run at least once, so
open a pull request first.

If you later add **tag** rules, let GitHub Actions create `v*` tags, otherwise
the release job can't push them.

## Recovering from a failed release

Open the failed run under *Actions* → *Release*.

| Where it failed | What happened | What to do |
|---|---|---|
| *Validate release* (analyze, test, version check) | Nothing tagged or published; no approval requested | Fix it in a new pull request. The version wasn't released, so you can keep it. |
| Approval rejected or timed out | Nothing published | Merge a new pull request with a bumped version, or re-run the workflow to request approval again |
| *Check expected release certificate* or *Set up release signing* | Variable or secrets missing or wrong; nothing published | Fix them in the `production` environment, then **Re-run jobs** on the same run |
| Build or APK verification | Nothing tagged or published | Fix the cause. A certificate mismatch means the wrong keystore or `RELEASE_CERT_SHA256`. |
| *Publish GitHub Release*, with the tag already created | Tag exists, no release | **Re-run jobs.** The version check sees the tag on the same commit and resumes, skipping tag creation. |
| A release exists but is incomplete (e.g. missing an asset) | Re-runs refuse to overwrite it | Delete the incomplete release (not the tag) on the *Releases* page, then **Re-run jobs** |
| A bad build was released | — | Never reuse a version and never move a tag. Fix it, bump the version (e.g. PATCH) and merge. You can mark the bad release as a pre-release or delete it. |

## Building locally

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug                   # build/app/outputs/flutter-apk/app-debug.apk
bash tool/ci/build_unsigned_release.sh      # unsigned validation build, as in CI
```

- `flutter build apk --release` needs a valid `android/key.properties`
  (git-ignored; see `android/key.properties.example`). Without it, the build
  **fails on purpose**: RCBWallet never falls back to the debug key.
- `tool/ci/build_unsigned_release.sh` refuses to run while
  `android/key.properties` exists, so validation builds never use signing
  material.
- Run the CI script tests locally:

  ```bash
  bash tool/ci/tests/check_version_test.sh
  bash tool/ci/tests/verify_apk_test.sh \
    build/app/outputs/apk/release/app-release-unsigned.apk \
    build/app/outputs/flutter-apk/app-debug.apk
  ```

- Releases ship the universal APK only. (`--split-per-abi` builds multiply the
  versionCode: `versionCode * 100 + abi`.)
