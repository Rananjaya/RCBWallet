# RCBWallet Security Audit Report (Phase 1: Assessment)

| | |
| --- | --- |
| Application | RCBWallet (`com.rananjaya.rcbwallet`), version `1.0.0+1` |
| Upstream | [sidhant947/Wallet](https://github.com/sidhant947/Wallet) |
| Code reviewed | branch `feature/rcbwallet-fork-rebrand`, commit `dd20343` |
| Platform in scope | Android (Flutter/Dart + Kotlin). No iOS or desktop projects exist in the repository. |
| Audit date | 2026-11-10 |
| Type | Assessment only. No application code, dependencies or configuration were changed. |

---

## Executive Summary

RCBWallet's cryptography for data at rest is broadly sound. Card fields are encrypted
individually with AES-256-GCM, using a random 256-bit key held in Android-Keystore-backed
secure storage. Backups and QR transfers use Argon2id with AES-GCM, and tampering with any of
these is detected. Release builds have no `INTERNET` permission, screenshots are blocked, and
cloud backup is disabled.

The application is **not yet suitable for storing real card data**. The main problems are in
access control and the handling of untrusted input, not the cipher:

1. **The app lock can be silently skipped (RCB-01, High, reproduced).** Startup authentication
   only runs when the device has biometric *hardware* and either a screen lock or enrolled
   biometrics. On a device with a PIN but no fingerprint sensor, or with no screen lock, the
   app opens with no authentication. There is no in-app PIN.
2. **The app never re-locks (RCB-02, High).** Once unlocked, the vault stays open whenever the
   app is resumed from the background, for as long as the process lives.
3. **Security settings can be changed without re-authentication (RCB-03, RCB-04).** Anyone
   holding the unlocked app can turn off the lock, or point automatic backups at a location
   they control and set the password.
4. **Imported data is trusted too much (RCB-06).** A crafted backup or QR share can set file
   paths that the app later deletes, reads, exports or opens. This can destroy the vault's key
   material or move private app files into backups.
5. **The app lock is UI-only (RCB-07).** The encryption key is not bound to user
   authentication, so anyone able to run code in the app's process can decrypt everything.

There are also data-handling weaknesses:
- the auto-backup password is stored in plaintext (RCB-05);
- decrypted PDFs are left in the cache (RCB-09);
- restore is destructive and silently loses records (RCB-10);
- a key-storage read failure can silently regenerate the key and orphan all data (RCB-08).

No hard-coded encryption keys, analytics, trackers or network code were found.

**Finding count:** 0 Critical · 2 High · 8 Medium · 8 Low · 5 Informational.

This report does not claim the application is secure. The limits of what was verified are
listed under [Audit Limitations](#audit-limitations).

### Evidence legend

| Label | Meaning |
| --- | --- |
| **Reproduced (emulator)** | Observed on the Pixel_9a emulator (API 37) using dummy data |
| **Reproduced (isolated test)** | Demonstrated by a throwaway unit test using mocked secure storage, temporary directories and dummy keys. It is not in the repository and never touched the real app database. |
| **Code inspection** | Established from source code only; not executed |
| **Not verified** | Plausible from documentation or design, but not confirmed |

Classification used: *Confirmed vulnerability*, *Potential vulnerability*, *Design weakness*,
*Informational*.

---

## Findings Summary

| ID | Title | Severity | Class | Evidence |
| --- | --- | --- | --- | --- |
| RCB-01 | Startup authentication skipped when biometric hardware or enrolment is missing | High | Confirmed vulnerability | Reproduced (emulator) + code |
| RCB-02 | No re-authentication after backgrounding; the session never expires | High | Confirmed vulnerability | Code inspection |
| RCB-03 | App lock can be disabled without authentication, including through a restored backup | Medium | Confirmed vulnerability | Code inspection |
| RCB-04 | Auto-backup can be configured without re-authentication (silent exfiltration path) | Medium | Confirmed vulnerability | Code inspection |
| RCB-05 | Auto-backup password stored in plaintext and copied into manual backups | Medium | Confirmed vulnerability | Code inspection |
| RCB-06 | File paths in imported backups or QR shares are trusted (arbitrary private-file delete/read/export) | Medium | Confirmed vulnerability (primitives) | Reproduced (isolated test) + code |
| RCB-07 | Encryption key not bound to user authentication; the lock is UI-only | Medium | Design weakness | Code inspection |
| RCB-08 | Key-storage read failure silently generates a new key, causing permanent data loss | Medium | Potential vulnerability | Code inspection |
| RCB-09 | Decrypted PDF attachments written to the cache in plaintext and never deleted | Medium | Confirmed vulnerability | Code inspection |
| RCB-10 | Restore wipes all data before inserting, and silently drops failed records | Medium | Design weakness | Code inspection |
| RCB-11 | Field decryption accepts plaintext and unauthenticated legacy AES-CBC | Low | Design weakness | Reproduced (isolated test) |
| RCB-12 | Weak legacy backup and transfer formats still accepted | Low | Design weakness | Reproduced (isolated test) |
| RCB-13 | Clipboard exposure of card numbers | Low | Design weakness | Code inspection |
| RCB-14 | Over-broad permissions and FileProvider scope inherited from `open_filex` | Low | Design weakness | Merged manifest + plugin source |
| RCB-15 | Device-to-device transfer not excluded (`dataExtractionRules` missing) | Low | Potential vulnerability | Not verified |
| RCB-16 | Deleted records and files may remain recoverable | Low | Design weakness | Code inspection |
| RCB-17 | Denial of service through crafted archives | Low | Potential vulnerability | Code inspection |
| RCB-18 | Exception details logged in release builds | Low | Design weakness | Code inspection |
| RCB-19 | Unused exported deep-link intent filters | Informational | Informational | Merged manifest + code |
| RCB-20 | Dependency maintenance and update status | Informational | Informational | `pub outdated` + lockfile |
| RCB-21 | Database metadata stored in plaintext | Informational | Informational | Code inspection |
| RCB-22 | Store description overstates security | Informational | Informational | Documentation review |
| RCB-23 | Failed authentication leaves the user on the splash screen with no retry | Informational | Informational | Code inspection |

---

## Findings

### RCB-01: Startup authentication skipped when biometric hardware or enrolment is missing

- **Severity:** High · **Class:** Confirmed vulnerability · **Evidence:** Reproduced (emulator) + code inspection
- **Affected:** `lib/main.dart:193-214` (decision at lines 200-203, skip at 211-212)
- **Technical explanation:** The app authenticates only when
  `isDeviceSupported() && canCheckBiometrics` is true. In `local_auth_android` 1.0.56:
  - `isDeviceSupported` means "a screen lock is set **or** biometrics are enrolled";
  - `canCheckBiometrics` means only "biometric **hardware** exists".

  Otherwise the app goes straight to the home screen. The outcomes:

  | Device state | Result |
  | --- | --- |
  | Screen-lock PIN, no biometric hardware | **No authentication** (the device PIN is never requested) |
  | No screen lock, no enrolled biometrics | **No authentication** |
  | Biometric hardware present and a screen lock set | Prompt shown (device PIN fallback allowed) |

  There is no in-app PIN or passcode anywhere in the codebase, so nothing compensates. The
  setting text "Require biometrics when app starts" suggests protection that is not there.
  The Settings helper for destructive actions (`settings_page.dart:33-42`) correctly checks
  only `isDeviceSupported`, so the same device *does* prompt for its PIN on Restore, but not at
  app start.
- **Reproduction:** On the Pixel_9a emulator the lock screen was disabled, a fingerprint sensor
  was present with 0 enrolled prints, and the authentication setting was at its default (ON).
  The app opened directly to the card list with no prompt. The "PIN set, no sensor" case was
  not reproduced, because the emulator has a sensor; it follows directly from the plugin
  source.
- **Attack scenario:** Someone picks up a phone with a PIN but no fingerprint reader, unlocks
  the phone or catches it unlocked, opens RCBWallet and reads every card number, expiry date
  and attached document.
- **Impact:** Full disclosure of stored card and identity data to anyone with app access.
- **Remediation:**
  - Base the gate on `isDeviceSupported()` (device credential or biometrics), not on hardware
    presence.
  - If no device credential exists, **fail closed**: block access and explain, or offer an
    in-app PIN with its own key derivation.
  - Handle `PlatformException` from `authenticate()` (lockout, not enrolled) explicitly.
  - Rename the setting to say what it does.

### RCB-02: No re-authentication after backgrounding; the session never expires

- **Severity:** High · **Class:** Confirmed vulnerability · **Evidence:** Code inspection
- **Affected:** `lib/main.dart:57-67` (the lifecycle listener only clears the image cache), `lib/main.dart:164-175`
- **Technical explanation:** Authentication happens once, in `SplashScreen`. The
  `AppLifecycleListener` reacts to `paused` only by clearing decrypted images. Nothing
  re-locks on `resumed`, and there is no inactivity timeout. The vault stays open until Android
  kills the process. `FLAG_SECURE` hides the recents thumbnail but does not stop the app being
  reopened.
- **Attack scenario:** The owner unlocks RCBWallet, switches to another app and hands the phone
  over or leaves it unlocked. Anyone can return to RCBWallet from recents and browse, copy or
  share cards.
- **Impact:** Full data disclosure while the device is unlocked.
- **Remediation:**
  - Re-authenticate on `resumed` after a short grace period (for example 30–60 s).
  - Optionally lock immediately when the screen turns off.
  - Hide sensitive widgets while locked.
  - Add an idle timeout.

### RCB-03: App lock can be disabled without authentication, including through a restored backup

- **Severity:** Medium · **Class:** Confirmed vulnerability · **Evidence:** Code inspection
- **Affected:** `lib/pages/settings_page.dart:101-110`, `lib/models/startup_settings_provider.dart:52-57`, `lib/services/backup_service.dart:18-27` (`showAuthenticationScreen` is an allowed restore key) and `251-271`
- **Technical explanation:**
  - The "Authentication Screen" switch flips `showAuthenticationScreen` with no
    `authenticate()` call.
  - The restore allowlist includes `showAuthenticationScreen`, so a backup file can switch
    the lock off.
  - The value is kept in plain `SharedPreferences`.
- **Attack scenario:**
  - Someone with brief access to the unlocked app turns the lock off, and later opens the app
    freely.
  - Alternatively, a backup prepared by someone else silently disables the lock when it is
    restored.
- **Impact:** Persistent removal of the app lock without the owner noticing.
- **Remediation:**
  - Require authentication to turn the lock off.
  - Remove `showAuthenticationScreen` from the restore allowlist, or never let a restore lower
    security settings.
  - Show a clear warning while the lock is off.

### RCB-04: Auto-backup can be configured without re-authentication (silent exfiltration path)

- **Severity:** Medium · **Class:** Confirmed vulnerability · **Evidence:** Code inspection
- **Affected:** `lib/pages/settings_page.dart:200-205` (enable), `218-221` (location), `230-233` and `636-667` (change password), `480-615`; `lib/services/auto_backup_service.dart:14-28`
- **Technical explanation:** Manual backup, restore and delete-all require re-authentication
  (`settings_page.dart:678, 707, 756`). Enabling auto-backup, changing its folder (any Storage
  Access Framework location, including folders synced by cloud-storage apps) and changing its
  password do not. Once configured, every data change writes a full encrypted backup to that
  location (`backup_service.dart:449-539`).
- **Attack scenario:** Someone with a minute of access enables auto-backup into a cloud-synced
  folder they can read and sets a password they know. Every later card addition or edit is
  delivered to them, and the owner sees only a subtitle in Settings.
- **Impact:** Ongoing disclosure of the whole vault.
- **Remediation:**
  - Require authentication for all auto-backup configuration changes.
  - Show a persistent indicator or notification while auto-backup is active.
  - Consider confirming the destination on each change.

### RCB-05: Auto-backup password stored in plaintext and copied into manual backups

- **Severity:** Medium · **Class:** Confirmed vulnerability · **Evidence:** Code inspection
- **Affected:** `lib/models/auto_backup_provider.dart:17, 51-55`; `lib/services/backup_service.dart:42-51`
- **Technical explanation:**
  - `setBackupPassword` writes the password to `SharedPreferences`, which is a plaintext XML
    file in the app sandbox, not to secure storage.
  - `createBackup` copies every preference except the four key and migration keys, so manual
    `.wbk` backups include `autoBackupPassword` and `autoBackupUri` in their `data.json`.
  - `createAutoBackup` does exclude them.
- **Attack scenario:** Anyone who can read the app's preferences (root, device-to-device
  transfer as in RCB-15, or the file read in RCB-06) obtains the password protecting every
  auto-backup file. People often reuse passwords.
- **Impact:** Auto-backups lose their protection, and the password may be reused elsewhere.
- **Remediation:**
  - Store the password in `flutter_secure_storage`, or keep a derived key instead of the
    password.
  - Exclude all `autoBackup*` keys from manual backups.
  - Migrate and delete the existing plaintext value.

### RCB-06: File paths in imported backups or QR shares are trusted (arbitrary private-file delete/read/export)

- **Severity:** Medium · **Class:** Confirmed vulnerability (primitives reproduced; full on-device chain not executed) · **Evidence:** Reproduced (isolated test) + code inspection
- **Affected:**
  - `lib/services/backup_service.dart:297-334, 336-360, 411-438`: path remapping keeps the
    original path when no matching image exists.
  - `lib/screens/homescreen.dart:162-166, 351-355`: QR import passes the whole decoded map to
    `Wallet.fromMap`.
  - `lib/models/wallet.dart:66-68, 94-96`: paths are stored verbatim and unencrypted.
  - `lib/models/db_helper.dart:176-191` (delete), `lib/services/encryption_service.dart:551-556`
    (non-encrypted files returned as raw bytes), `lib/services/backup_service.dart:89-103`
    (backup reads every referenced path), `lib/pages/walletdetails.dart:137-157` (open PDF).
- **Technical explanation:** Imported records keep any `frontImagePath`, `backImagePath` or
  `pdfPath` (and pass `fields.pdfPath`) supplied by the file. The sender strips image paths
  (`share_secure_screen.dart:117-121`), but the receiver does not enforce this. These paths are
  later used as follows:
  - **deleting** the card calls `File(path).delete()` on them;
  - **creating a backup** reads them and adds the bytes under `images/`;
  - **opening the attachment** decrypts or reads them and hands them to an external viewer.

  Any file the app can access is in reach. That includes its own databases, the
  secure-storage preferences file, and `FlutterSharedPreferences.xml`.
- **Isolated reproduction:**
  - R4: an injected path survives `fromMap` and `toEncryptedMap` unchanged.
  - R5: `deleteImageFile` deletes an arbitrary file.
  - R6: `decryptImageToBytes` returns the raw contents of a non-encrypted UTF-8 file
    (demonstrated with a dummy `autoBackupPassword` XML).
- **Attack scenario:** An attacker sends a "shared card" QR code and its password. When the
  victim imports it and later deletes it, the secure-storage file is deleted, the master key is
  lost and the whole vault becomes undecryptable (see RCB-08). Alternatively, the victim's next
  backup silently contains private app files.
- **Impact:** Destruction of all stored data. Disclosure of private app files into backups or
  to viewer apps.
- **Remediation:**
  - Never accept paths from imported data. Clear all path fields on import and rebuild them
    only from files extracted into a dedicated directory.
  - Before deleting, reading or opening, canonicalise each path and confirm it is inside the
    app's attachment directory.
  - Refuse to treat non-encrypted files as attachments.

### RCB-07: Encryption key not bound to user authentication; the lock is UI-only

- **Severity:** Medium · **Class:** Design weakness · **Evidence:** Code inspection
- **Affected:** `lib/services/encryption_service.dart:81, 100-143`; `lib/services/app_initialization_service.dart:16`; `flutter_secure_storage` 10.3.1 defaults (`enforceBiometrics=false`)
- **Technical explanation:**
  - The 256-bit data key is created and unwrapped at process start, before any authentication.
  - Its Keystore wrapping key does not require user authentication.
  - Biometrics only gate navigation, so decryption never depends on the user proving
    presence.
- **Attack scenario:** On a rooted or compromised device, or with an instrumented or repackaged
  app process, an attacker can call the decrypt routines, or read the unwrapped key from
  memory, without passing any prompt.
- **Impact:** Every protection above the UI can be bypassed by code execution in the app's
  context.
- **Remediation:** Wrap the data key with a Keystore key that requires user authentication
  (`setUserAuthenticationRequired`, preferably StrongBox when available). Unwrap it only after
  successful authentication, and drop it from memory when the app locks. Plan the migration
  carefully, because biometric enrolment changes invalidate such keys.

### RCB-08: Key-storage read failure silently generates a new key, causing permanent data loss

- **Severity:** Medium · **Class:** Potential vulnerability (availability) · **Evidence:** Code inspection; not reproduced
- **Affected:** `lib/services/encryption_service.dart:104-115`; `flutter_secure_storage` default `resetOnError: true`
- **Technical explanation:** `init()` swallows any exception from reading the master key and
  treats it as "first launch": it generates a new key and writes it over the old one.
  `flutter_secure_storage` also wipes its storage by default when decryption fails. Keystore
  invalidation (lock-screen changes, OS or Keystore faults, restored app data) or a transient
  error would therefore replace the key. All existing ciphertext then fails to decrypt, and
  `decryptText` throws, which breaks the lists.
- **Attack scenario:** Mostly accidental. It can also be triggered on purpose through RCB-06,
  by deleting the secure-storage file.
- **Impact:** Irrecoverable loss of the vault unless a recent backup exists.
- **Remediation:**
  - Distinguish "no key" from "read failed".
  - Never overwrite an existing key entry after a read error. Fail closed and offer restore.
  - Set `resetOnError: false` explicitly.
  - Keep a key-check value, so a wrong or new key is detected before any data is written.

### RCB-09: Decrypted PDF attachments written to the cache in plaintext and never deleted

- **Severity:** Medium · **Class:** Confirmed vulnerability · **Evidence:** Code inspection
- **Affected:** `lib/pages/walletdetails.dart:137-157`, `lib/screens/identity_card_details_screen.dart:94-108`, `lib/screens/barcode_card_details_screen.dart:123-137`
- **Technical explanation:** Opening an attachment decrypts it to
  `cache/card_doc_<timestamp>.pdf` and launches an external viewer through `open_filex`. The
  file is never deleted, so a plaintext copy of the document stays in the cache until the OS
  evicts it. The external viewer may also cache it or sync it.
- **Attack scenario:** A forensic or root-level read of the cache directory, or a viewer app
  that keeps recent files, recovers identity documents or card statements long after use.
- **Impact:** Persistent plaintext copies of sensitive documents outside the encrypted store.
- **Remediation:**
  - Render PDFs inside the app from memory.
  - If an external viewer is unavoidable, use a single file that is deleted when the user
    returns, plus cleanup at startup.
  - Warn that the document leaves the app.

### RCB-10: Restore wipes all data before inserting, and silently drops failed records

- **Severity:** Medium · **Class:** Design weakness (integrity and availability) · **Evidence:** Code inspection
- **Affected:** `lib/services/backup_service.dart:246, 297-438, 541-585`
- **Technical explanation:**
  - After schema validation, `_clearAllData()` deletes every row, every `.enc` file and all
    non-key preferences.
  - Records are then inserted one by one inside `catch (_) {}`, so any record that fails is
    dropped without a message.
  - There is no transaction, staging area or rollback. Validation only checks for a few keys.
- **Attack scenario:** A partially corrupted or crafted backup is restored. The user's current
  data is erased and only some records come back, with a "success" outcome.
- **Impact:** Silent loss of financial data.
- **Remediation:**
  - Restore into staging databases and directories, then swap atomically after a full
    validation.
  - Count and report failures, and abort if any occur.
  - Keep an automatic pre-restore snapshot.

### RCB-11: Field decryption accepts plaintext and unauthenticated legacy AES-CBC

- **Severity:** Low · **Class:** Design weakness · **Evidence:** Reproduced (isolated test R1, R3); GCM tamper detection confirmed (R2)
- **Affected:** `lib/services/encryption_service.dart:187-192` (plaintext pass-through), `199-206` (CBC with the same key), `213-231`, `551-556`
- **Technical explanation:**
  - Values that don't look encrypted are returned as-is.
  - Values with a 16-byte IV are decrypted with AES-CBC under the **same key** as GCM, with no
    MAC.
  - In R3, flipping IV bits changed a dummy card number from `4111…` to `5111…` with no error.

  Restore and import re-encrypt data through `toEncryptedMap`, so exploiting this needs direct
  write access to the database files (root or a compromised sandbox).
- **Impact:** An attacker who can write the database can plant or alter values without being
  detected. Integrity guarantees are weaker than the GCM documentation claims.
- **Remediation:** After a verified migration, reject plaintext and CBC values (fail closed),
  or allow them only behind a one-time migration flag that is then removed. Use separate keys
  per purpose.

### RCB-12: Weak legacy backup and transfer formats still accepted

- **Severity:** Low · **Class:** Design weakness · **Evidence:** Reproduced (isolated test R7)
- **Affected:** `lib/services/encryption_service.dart:434-455` (PBKDF2 600k), `476-485` (SHA-256 ×10,000 with the **static salt** `wallet_app_aes256_salt_v1`), `726-768` (AES-CBC without authentication), `381-425` (v2/v1 transfers)
- **Technical explanation:** Restore auto-detects four formats. Only the current one
  (`argon2:`) uses a memory-hard KDF and authenticated encryption. The legacy formats are weak
  against offline guessing (static salt, cheap KDF) and are malleable.
- **Impact:** Limited for crafted files, because an attacker supplying a backup already
  controls its content. The real effect is lower assurance for old backups that users still
  hold.
- **Remediation:** Offer a one-time "re-encrypt old backup" path, then remove legacy decoding,
  or put it behind an explicit user choice with a warning.

### RCB-13: Clipboard exposure of card numbers

- **Severity:** Low · **Class:** Design weakness · **Evidence:** Code inspection
- **Affected:** `lib/services/clipboard_service.dart:13-33` and its callers (for example `walletdetails.dart:342, 352`, `homescreen.dart:947`)
- **Technical explanation:**
  - Card numbers go to the system clipboard and are cleared after 15 s by an in-process
    `Timer`, which never fires if the process dies first.
  - Clips are not flagged as sensitive (`ClipDescription.EXTRA_IS_SENSITIVE`), so Android 13+
    shows a visible preview, and keyboard clipboard history can keep the value.
- **Impact:** Card numbers persist outside the app, in keyboard history or in a later paste.
- **Remediation:**
  - Mark clips as sensitive through a platform channel.
  - Clear the clipboard when the app is backgrounded.
  - Consider not offering copy for full card numbers by default.

### RCB-14: Over-broad permissions and FileProvider scope inherited from `open_filex`

- **Severity:** Low · **Class:** Design weakness · **Evidence:** Merged manifest and plugin source
- **Affected:** `open_filex` 4.7.0, which adds `READ_EXTERNAL_STORAGE` (≤ API 32), `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO` and `READ_MEDIA_AUDIO`, plus a FileProvider whose `filepaths.xml` includes `<root-path path="."/>`
- **Technical explanation:**
  - The app only needs to open its own PDFs, yet it requests media access it never uses.
  - The provider is not exported and grants URIs individually, which reduces the risk.
  - But the root-path scope means any file path the app passes can be shared. This combines
    with RCB-06.
- **Remediation:**
  - Replace `open_filex` with an in-app viewer, or remove the unused permissions using
    `tools:node="remove"`.
  - Override the provider paths to a single attachments cache directory.

### RCB-15: Device-to-device transfer not excluded (`dataExtractionRules` missing)

- **Severity:** Low · **Class:** Potential vulnerability · **Evidence:** Not verified
- **Affected:** `android/app/src/main/AndroidManifest.xml:8-9` (no `android:dataExtractionRules`; targetSdk 36)
- **Technical explanation:** `allowBackup="false"` disables cloud backup. For apps targeting
  Android 12+, device-to-device migration is controlled by `dataExtractionRules`, which is not
  set.
  - Keystore keys do not migrate, so encrypted fields stay unreadable.
  - Plaintext preferences, including the auto-backup password (RCB-05), could migrate.
- **Remediation:** Add `dataExtractionRules` that exclude all domains for both `cloud-backup`
  and `device-transfer`, then verify with a D2D test.

### RCB-16: Deleted records and files may remain recoverable

- **Severity:** Low · **Class:** Design weakness · **Evidence:** Code inspection
- **Affected:** `lib/models/db_helper.dart:176-191`, `lib/services/encryption_service.dart:517-521`, `lib/services/image_service.dart:11-33`
- **Technical explanation:**
  - SQLite `DELETE` without `secure_delete` leaves old pages in the free list or journal.
  - Files are unlinked without being overwritten.
  - Deleted ciphertext therefore stays recoverable, and becomes readable if the key is ever
    extracted (RCB-07).
- **Remediation:**
  - Enable `PRAGMA secure_delete=ON` and run `VACUUM` after bulk deletes.
  - Rotate the data key when wiping all data, so remnants become useless.

### RCB-17: Denial of service through crafted archives

- **Severity:** Low · **Class:** Potential vulnerability · **Evidence:** Code inspection
- **Affected:** `lib/services/pkpass_service.dart:21-31` (unbounded recursion into nested `.pkpass` entries, no size limits); `lib/services/backup_service.dart:138-142, 197-222` (whole file read into memory; the zip-bomb check trusts sizes declared in the headers)
- **Impact:** A crash or memory exhaustion when the user opens a crafted file. No data loss
  was identified unless it happens mid-restore (RCB-10).
- **Remediation:** Limit nesting depth, entry count and actual decompressed bytes while
  streaming. Cap the input file size before reading it.

### RCB-18: Exception details logged in release builds

- **Severity:** Low · **Class:** Design weakness · **Evidence:** Code inspection
- **Affected:** `lib/services/backup_service.dart:134, 364-409, 441-443`; `lib/services/encryption_service.dart:190`; `lib/services/saf_service.dart:12-52`
- **Technical explanation:** `debugPrint` is not stripped from release builds. Restore failures
  log the full exception and stack trace. No card data or passwords are logged directly, but
  the messages reveal what the app is doing to anything that can read logcat (ADB or system
  apps).
- **Remediation:** Guard diagnostic logging with `kDebugMode`, or use a logger that is silent
  in release.

### RCB-19: Unused exported deep-link intent filters

- **Severity:** Informational
- **Affected:** `android/app/src/main/AndroidManifest.xml:31-45`
- **Details:**
  - `MainActivity` is exported with VIEW filters for `https` **and `http`**
    `pay.google.com/gp/v/save` links, and for `.pkpass` / `application/octet-stream` files.
  - No Dart or Kotlin code reads the incoming intent data, so these filters only launch the
    app. Any app or web page can therefore bring RCBWallet to the foreground. If it is already
    unlocked, it opens unlocked (see RCB-02).
- **Remediation:** Remove the filters until the feature is implemented, and never accept `http`
  for these links.

### RCB-20: Dependency maintenance and update status

- **Severity:** Informational · **Evidence:** `flutter pub outdated`, `pubspec.lock`, plugin sources
- **Details:**
  - **`encrypt` 5.0.3** (AES-GCM and AES-CBC for all data at rest):
    - this is the latest release, with no newer version available;
    - it pins `pointycastle` to 3.9.1, while 4.0.0 exists;
    - package metadata lists no active maintainers.

    Treat it as **apparently unmaintained (not conclusively verified)**. Its GCM comes from
    PointyCastle, and tag verification worked in tests R2 and R8.
  - **`cryptography_plus` 3.0.0** (Argon2id): a pure-Dart implementation. Timing confirmed the
    configured cost is applied (about 630 ms for 128 MiB, t=3, p=4, against 5 ms for a minimal
    setting on the audit machine). It was not checked against official test vectors.
  - **Newer major versions are available** for `local_auth` (3.x), `flutter_secure_storage`
    (11.x), `open_filex` (5.x) and `file_picker` (13.x). Minor updates are available for
    `archive`, `sqflite`, `image_picker`, `url_launcher`, `crypto` and `barcode_scan2`.
  - **`js`** is discontinued; it is a web-only transitive dependency.
  - **`sqflite_common_ffi`** (used for desktop testing) bundles `libsqlite3.so` (1.7 MB) into
    the Android APK, which is unnecessary native code.
  - **`http`** is present only as a transitive dependency of the platform interfaces for
    `image_picker` and `file_selector`.
  - **No analytics, crash-reporting, advertising or tracking SDKs** were found in the
    lockfile.
  - **Known-vulnerability databases were not queried** (see Limitations).
- **Remediation:**
  - Plan a dependency-update phase with tests.
  - Evaluate replacing `encrypt` with a maintained AEAD implementation, such as Android
    Keystore AES-GCM through a platform channel, or `cryptography_plus` AES-GCM.
  - Move `sqflite_common_ffi` to dev or desktop-only use.

### RCB-21: Database metadata stored in plaintext

- **Severity:** Informational
- **Details:** Field-level encryption leaves some items unencrypted:
  - the schema, row counts, ids and ordering;
  - attachment file paths;
  - pass `type`, colours, `barcodeFormat` and `transitType`;
  - identity `color`.

  An attacker with the files learns how many cards, passes and IDs exist and what kinds of
  passes they are. Whole-database encryption, for example SQLCipher, would remove this.

### RCB-22: Store description overstates security

- **Severity:** Informational
- **Details:** `fastlane/metadata/android/en-US/full_description.txt` (from upstream) makes
  several unsupported claims:
  - "MILITARY-GRADE ENCRYPTION";
  - "100% immune to cloud leaks, remote hacks";
  - "Authentication is required on app start", which is contradicted by RCB-01.

  The README already states that the app has not been audited. Revise the store text before
  publishing.

### RCB-23: Failed authentication leaves the user on the splash screen with no retry

- **Severity:** Informational
- **Affected:** `lib/main.dart:204-210`
- **Details:** If authentication is cancelled or fails, nothing happens: the app stays on the
  splash screen until it is restarted, and exceptions from `authenticate()` are not caught.
  This fails closed, which is good, but users may be tempted to switch the lock off. Add a
  retry button and error messages.

---

## Security Strengths

| Area | Verified behaviour | Evidence |
| --- | --- | --- |
| Field encryption | AES-256-GCM per field, with a fresh 96-bit IV from `Random.secure()` for each value. Tampering is detected. | Code + isolated test R2 |
| Key generation | A 256-bit random master key is generated on first run. No hard-coded data keys were found (the only static secret is the legacy salt in RCB-12). | Code inspection |
| Key storage | The key is stored through `flutter_secure_storage` 10.3.1, which by default wraps it with Android Keystore keys (RSA-OAEP key cipher, AES-GCM storage cipher). | Plugin source |
| Backups | Argon2id (128 MiB, 3 iterations, parallelism 4) with a random 16-byte salt, AES-256-GCM, and tamper detection. Keys and migration flags are excluded from backups. | Code + isolated test R8 + timing |
| QR transfer | Argon2id + AES-GCM, 8-character minimum password, sender strips image paths and ids | Code inspection |
| Network isolation | No `INTERNET` permission in the release manifest. No network APIs in app code. No telemetry SDKs. External links open only static GitHub URLs. | Release build analysed in an earlier phase + code |
| Screen capture | `FLAG_SECURE` on the only activity. Screenshots of the app came out black during testing. | `MainActivity.kt:26` + emulator |
| Cloud backup | `allowBackup="false"`, `fullBackupContent="false"` | Manifest |
| Images | Picked images are copied, encrypted and the plaintext source deleted. The decrypted-image cache is cleared when the app is paused. | `image_service.dart`, `main.dart:60-66` |
| Clipboard | Auto-clears after 15 s, only if the clipboard still holds the copied value | `clipboard_service.dart` |
| Destructive actions | Manual backup, restore and delete-all require device authentication when a credential exists | `settings_page.dart:678, 707, 756` |
| Restore input handling | Settings allowlist, basic schema checks, ZIP entry names reduced to their basename (no zip-slip), size caps, common wrong-file signatures rejected | `backup_service.dart` |
| Components | Only the launcher activity is exported (plus a `DUMP`-protected AndroidX receiver). FileProviders are not exported. | Merged manifest |
| Release signing | Release builds require a dedicated keystore and never fall back to the debug key | `android/app/build.gradle.kts` |

---

## Threat Model

| Threat | What an attacker could do | Current protection | Sufficient? | Recommended improvement |
| --- | --- | --- | --- | --- |
| **Lost or stolen device (locked)** | Try to unlock the phone, or extract its storage | Android lock screen, file-based encryption, Keystore-wrapped key | Mostly. It depends on the device lock and on the device not being rooted. | Bind the key to user authentication (RCB-07). Stop the plaintext PDF remnants (RCB-09). |
| **Physical access to an unlocked device** | Open the app and read, copy, share or export all cards. Turn off the lock. Set up auto-backup exfiltration. | Startup biometric prompt (only on some devices), `FLAG_SECURE`, re-authentication for manual backup and restore | **No** | Fix RCB-01 and RCB-02. Require authentication for all security settings (RCB-03, RCB-04). |
| **Physical access to a locked device** | Little without unlocking it | Device lock and storage encryption | Yes, for a non-rooted device with a strong lock | Same as above. Discourage use on devices with no lock (RCB-01). |
| **Malicious backup file or QR share** | Inject file paths (delete keys, read private files), disable the lock, wipe existing data on restore, cause DoS | Password-based decryption, light schema checks, settings allowlist, basename for ZIP entries | **No** | Fix RCB-06, RCB-03 and RCB-10. Validate types strictly. Show a summary before restoring. |
| **Malicious app on the same device** | Read the sandbox (not possible without root), launch the activity via intents, read the clipboard (limited on Android 10+), keep copies of opened PDFs | Android sandbox, providers not exported, `FLAG_SECURE`, clipboard auto-clear | Partly | Fix RCB-13, RCB-09 and RCB-19. Lock on resume (RCB-02). |
| **Rooted device** | Read the databases, preferences (plaintext auto-backup password) and cache. Hook the process to obtain the data key or decrypted values. | Keystore wrapping (on some devices, the hardware key cannot be extracted, but the app unwraps it automatically) | **No** | Key bound to authentication (RCB-07). Secure storage for secrets (RCB-05). Optional root/integrity detection, with a warning only. |
| **Modified or repackaged APK** | Remove the lock, add exfiltration, then distribute it | APK signature (a repackaged app has a different signer and cannot read the original's data) | Partly. It protects existing installs, but not users who install a fake app. | Publish the signing-certificate fingerprint. Consider Play Integrity or a signature self-check if distributed outside trusted stores. |
| **Database file extraction** | Learn metadata (RCB-21). Ciphertext is useless without the key. Deleted remnants could be decrypted if the key leaks (RCB-16). | Per-field AES-GCM | Yes for content, no for metadata | SQLCipher or equivalent, `secure_delete`, key rotation on wipe |
| **Encryption key extraction** | Decrypt all fields from any copy of the databases | Keystore-wrapped key, not bound to authentication | Partly. It resists offline extraction but not code running in the app's process. | RCB-07 (authentication-bound unwrap). Avoid keeping the key in memory while locked. |

---

## Remediation Roadmap

### 1. Critical and high priority (before storing real card data)

1. **RCB-01:** Fix the startup gate. Authenticate whenever any device credential exists, and
   fail closed (or use an in-app PIN) when none exists.
2. **RCB-02:** Re-lock on resume after a short grace period, and add an idle timeout.
3. **RCB-03 and RCB-04:** Require authentication to disable the lock or change any auto-backup
   setting. Remove `showAuthenticationScreen` from the restore allowlist.
4. **RCB-06:** Discard and re-derive all file paths on import, and confine every file
   operation to the attachments directory.
5. **RCB-05:** Move the auto-backup password to secure storage, and exclude `autoBackup*` from
   manual backups.
6. **RCB-08:** Never regenerate or overwrite an existing key after a read error. Set
   `resetOnError: false`.

### 2. Medium priority

7. **RCB-07:** Use a Keystore key that requires user authentication to wrap the data key.
8. **RCB-09:** View PDFs in-app, or delete temporary plaintext files promptly.
9. **RCB-10:** Make restore staged and atomic, with failure reporting and a pre-restore
   snapshot.
10. **RCB-14 and RCB-15:** Remove the unused permissions, narrow the FileProvider paths, and
    add `dataExtractionRules`.
11. **RCB-11:** After migration, reject plaintext and legacy CBC values.
12. **RCB-13:** Mark clipboard contents as sensitive, and clear them when the app is
    backgrounded.

### 3. Long-term improvements

13. **RCB-12:** Retire the legacy backup and transfer formats after a re-encryption path.
14. **RCB-20:** Run a dependency-update phase, choose a maintained AEAD library instead of
    `encrypt`, and remove `sqflite_common_ffi` from the Android build.
15. **RCB-21 and RCB-16:** Encrypt whole databases, enable `secure_delete`, and rotate keys on
    wipe.
16. **RCB-17, RCB-18, RCB-19, RCB-22, RCB-23:** Harden archive limits, silence release logs,
    remove unused intent filters, correct the store text, and add an authentication retry.
17. Add automated security regression tests for every fix above, then run a second audit,
    preferably with dynamic testing on a rooted test device.

---

## Audit Limitations

- **No dynamic instrumentation** (Frida or similar) and **no rooted-device testing**. RCB-07
  and the rooted-device threats are assessed from design only.
- **One emulator configuration only.** The emulator had no screen lock and an unenrolled
  fingerprint sensor. The "PIN set, no biometric hardware" path of RCB-01 was derived from
  plugin source, not executed. Biometric prompts, lockout and Keystore invalidation were not
  exercised.
- **No end-to-end exploit on a device** for RCB-06. Only its building blocks were reproduced
  in isolated tests. No crafted backup or QR code was imported into the real app.
- **Release APK not re-analysed in this phase.** Release builds now correctly require signing
  credentials, which were not available. The release permission set comes from an earlier
  analysis of this branch; `debuggable=false` for release relies on the Android Gradle Plugin
  defaults and was not re-checked.
- **Known-vulnerability databases (OSV, GitHub Advisories, NVD) were not queried**, and no
  software-composition-analysis tool was run. The maintenance status of `encrypt` is based on
  weak public metadata.
- **Third-party native code was not reviewed** (`barcode_scan2`, `file_picker`, `image_picker`,
  `local_auth`, `libsqlite3`, the Flutter engine). The Argon2id and AES-GCM implementations
  were not checked against official test vectors.
- **Some areas were not tested:** device-to-device transfer (RCB-15), real SAF cloud providers
  for auto-backup, and keyboard clipboard-history behaviour.
- **iOS and desktop are out of scope.** There are no iOS or desktop projects in the repository.
- Line numbers refer to commit `dd20343` and will drift as the code changes.
