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
| `android/key.properties` | release machine only | local, git-ignored | Gradle release signing |
| Google Play developer account | project lead | Play Console | Internal Testing, release |
| Windows code-signing certificate (optional) | PENDING (input register #5) | | signing the installer |
| SMTP credentials (optional) | PENDING (input register #12) | Supabase Auth settings | password-reset email |

## 2. Release artefacts

*Filled in Slices 6 and 7.* For each release: version, build date, commit, SHA-256 of the
APK, AAB, installer, `krishna_mis.exe`, `pdfium.dll` and `sqlite3mc.dll` (D-341, D-342).

## 3. User provisioning

*Filled in Slice 5, once the administration path is decided (D-340, input register #9).*

## 4. Role and scope administration

*Filled in Slice 5.* Non-Owner grants always name a business unit (D-025).

## 5. Password reset

*Filled in Slice 5, after the SMTP decision.*

## 6. Period close and reopen

*Filled in Slice 5.* A reopen states a reason that is not whitespace (spec §14.1, D-145).

## 7. Android deployment

*Filled in Slice 6.* Play App Signing; Internal Testing first (D-341).

## 8. Windows deployment

*Filled in Slice 7.* Isolated data identity; never launched against the D-247 AppData
(D-336, D-342).

## 9. Backup

*Filled in Slice 8.* Database posture, and Storage objects handled explicitly (D-344).

## 10. Restore

*Filled in Slice 8,* after at least one real restore into a non-production target.

## 11. Lost device

*Filled in Slice 8.* Deactivate or change the person's grants; the server is the boundary
(D-037).

## 12. Local recovery and reset

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
