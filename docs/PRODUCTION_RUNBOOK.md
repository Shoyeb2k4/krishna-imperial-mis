# Production Runbook

Directive: SHOYEB-HOSPITALITY-MIS · Spec **v1.2**
Business: Hotel Krishna Imperial · Project: Krishna Imperial MIS ·
Domain: hotelkrishnaimperial.in
Project Lead / Product Decision-Maker: Shoyeb Akhtar (not the proprietor of the business;
the application role named **Owner** is a separate concept — D-057)
Status: **SKELETON — Phase 9 Slice 1 (2026-10-03, D-345).** No production environment
exists yet. Each section names the slice that fills it. Nothing here is a verified
procedure until that slice reports it tested.

> **No secret value is ever written in this file** — no password, key, token, keystore
> passphrase, database connection string or service-role secret. This file says *where* a
> secret lives and *who* holds it, never *what* it is. The secret scan runs over it.

---

## 1. Production environment inventory

*Filled in Slice 5.*

| Item | Value | Recorded by |
|---|---|---|
| Supabase organisation / plan tier | PENDING (input register #1) | |
| Production project reference | PENDING | |
| Rehearsal target (staging project or branch) | PENDING (input register #2) | |
| Region | `ap-south-1` unless later evidence requires otherwise (D-337) | |
| Site URL | PENDING (input register #11) | |
| SMTP | PENDING (input register #12) | |
| Backup / PITR posture | PENDING (D-344) | |

### 1.1 Secrets register

What exists **outside git**, who holds it, and where. Values are never recorded here.

| Secret / access | Held by | Stored where | Needed for |
|---|---|---|---|
| Supabase account access | project lead | the project lead's own account | provisioning, settings, restores |
| Production database password | project lead | password manager | replay, SQL-editor procedures |
| Production project URL | project lead | git-ignored `config/prod.json` | release builds (not secret, but not committed) |
| Production publishable key | project lead | git-ignored `config/prod.json` | release builds |
| Service-role secret | project lead | Supabase dashboard only | **never** in a client, a config file or this repository |
| Owner account password | the Owner | password manager | sign-in, administration |
| Staff credentials | each person | their own | sign-in |
| Android upload keystore | project lead | offline, backed up (losing it blocks updates) | signing releases |
| Keystore and key passwords | project lead | password manager | signing releases |
| `android/key.properties` | release machine only | local, git-ignored | Gradle release signing; every Android release build stops without it (D-346) |
| Windows production local data and key | each production Windows user | `%APPDATA%\Krishna Imperial\Krishna Imperial MIS Production` (database, `krishna_mis.db_key.prod.v1.dpapi`, session) | the production install; never the legacy `Krishna Imperial MIS` folder (D-346) |
| Google Play developer account | project lead | Play Console | Internal Testing, release |
| Windows code-signing certificate (optional) | PENDING (input register #5) | | signing the installer |
| SMTP credentials (optional) | PENDING (input register #12) | Supabase Auth settings | password-reset email |

## 2. Release artefacts

*Filled in Slices 6 and 7.* For each release: version, build date, commit, SHA-256 of the
APK, AAB, installer, `krishna_mis.exe`, `pdfium.dll` and `sqlite3mc.dll` (D-341, D-342).

## 3. User provisioning

*Filled in Slice 5, once the administration path is decided (D-340, input register #9).*

In the app, the Windows **Administration** destination tells a holder of `users.manage`:
*"Users, roles, period close and audit review are handled by the project administrator in
this version."* (D-348). Sections 3, 4 and 6 are that administrator's procedure.

## 4. Role and scope administration

*Filled in Slice 5.* Non-Owner grants always name a business unit (D-025).

## 5. Password reset

*Filled in Slice 5, after the SMTP decision.*

## 6. Period close and reopen

*Filled in Slice 5.* A reopen states a reason that is not whitespace (spec §14.1, D-145).

## 7. Android deployment

*Filled in Slice 6.* Play App Signing; Internal Testing first (D-341).

Release signing, as built in Slice 2 (D-346). On the release machine only, the project lead
creates the upload keystore and `android/key.properties` beside `android/app/`:

```
storeFile=<path to the upload keystore, absolute or relative to android/>
storePassword=<from the password manager>
keyAlias=<the upload key alias>
keyPassword=<from the password manager>
```

Both are git-ignored and are never pasted into chat, a document or a log. Without the file,
`flutter build apk|appbundle --release` stops at `verifyReleaseSigning`. Build with the
matching flavour and configuration — `--flavor prod --dart-define-from-file=config/prod.json`;
a mismatch, a missing backend or the development backend makes the app refuse to start.
Version: `pubspec.yaml`, `versionCode` +1 for every upload (D-347).

## 8. Windows deployment

*Filled in Slice 7.* Isolated data identity; never launched against the D-247 AppData
(D-336, D-342).

A production build (`config/prod.json`) keeps its data in
`%APPDATA%\Krishna Imperial\Krishna Imperial MIS Production` and its key in
`krishna_mis.db_key.prod.v1.dpapi` there — never in the legacy `Krishna Imperial MIS` folder
that development builds use (D-346). Nothing is migrated: a first launch starts empty and
downloads what the signed-in person may receive.

A staging build will use `%APPDATA%\Krishna Imperial\Krishna Imperial MIS Staging` and
`krishna_mis.db_key.staging.v1` (D-349, approved, built in Slice 4). Until it is built, do
not run a staging client on a Windows machine that holds development data.

## 9. Backup

*Filled in Slice 8.* Database posture, and Storage objects handled explicitly (D-344).

## 10. Restore

*Filled in Slice 8,* after at least one real restore into a non-production target.

## 11. Lost device

*Filled in Slice 8.* Deactivate or change the person's grants; the server is the boundary
(D-037).

## 12. Local recovery and reset

**Reading a screen that says something "could not be read on this device".** The person
presses Try again; if it keeps happening, restart the app. The cause is in the developer
log under `krishna_mis.masters`, `krishna_mis.revenue` or `krishna_mis.expenses`
(D-348) — never on screen, and never containing a secret.

*Filled in Slice 8.* The D-330 flow: Try again; reset only for unreadable or un-upgradable
data, after the stated loss and a typed RESET; data set aside, never deleted.

## 13. Server outage

*Filled in Slice 8.* Offline entry continues; reporting stays readable from the local cache
(spec §21.4).

## 14. Rollback

*Filled in Slice 8,* for both platforms and the backend.

## 15. Contact and escalation

*Filled in Slice 8.* Names roles, not secrets.

## 16. Go-live checklist

*Filled in Slice 8,* from `RELEASE_CHECKLIST.md` §W.
