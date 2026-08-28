# Environment configuration

Three isolated backends — **development**, **staging**, **production** — never share a
project, a key, or a password (`docs/ARCHITECTURE.md` §3). Each has its own file here.

| File | Flavour | Backend |
|---|---|---|
| `config/dev.json` | `dev` | `krishna-mis-dev` |
| `config/staging.json` | `staging` | not created yet — do not point it at dev |
| `config/prod.json` | `prod` | not created yet — do not point it at dev |

The real files are git-ignored (`.gitignore` → `config/*.json`). Only the `*.example.json`
files are committed. Verify with `git check-ignore -v config/dev.json` if in doubt.

## Keys

| Key | Value |
|---|---|
| `APP_FLAVOR` | `dev` \| `staging` \| `prod` — already correct in each file |
| `SUPABASE_URL` | The **Project URL**: `https://<project-ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | The **publishable** key (`sb_publishable_…`) or the legacy **anon** key |

Both come from the Supabase dashboard under **Project Settings → API Keys**. They are
client-safe by design: every one of them is powerless without a matching RLS policy.

## What must never go in these files

A service-role key, a secret key (`sb_secret_…`), a database password, a Postgres
connection string, a JWT signing secret, or any private key. None of these may exist on a
client machine at all (`docs/DECISIONS.md` D-022).

This is enforced, not merely asked for:

* `AppConfig` decodes the JWT payload and classifies the key before anything connects. A
  service-role key, a secret key or a connection string **stops start-up** with a message
  naming the mistake — it never reaches the network. Anything not positively recognised
  as a publishable/anon key is refused too, because an unclassified credential compiled
  into an Android or Windows binary cannot be taken back.
* `dart run tool/check_no_client_secrets.dart --history` scans the working tree, the build
  artefacts and every blob ever committed for credential material. It is a build-failing
  check.

Migrations and other privileged operations use a **separate developer-only path** that is
never bundled into the app — see `supabase/README.md`.

## Usage

    flutter run          --flavor dev  --dart-define-from-file=config/dev.json
    flutter build apk    --flavor dev  --dart-define-from-file=config/dev.json
    flutter build windows              --dart-define-from-file=config/dev.json

With both values empty the app still starts and is fully usable offline — local entry,
local storage and local reporting never depend on a backend (D-020).
