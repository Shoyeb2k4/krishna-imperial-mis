# Environment configuration

Copy an example to its real name and fill it in **locally**. The real files are
git-ignored and must never be committed:

    cp config/dev.example.json config/dev.json

| Key | Value |
|---|---|
| `APP_FLAVOR` | `dev` \| `staging` \| `prod` |
| `SUPABASE_URL` | The project URL |
| `SUPABASE_ANON_KEY` | The **publishable / anon** key only |

**Never put a service-role key, database password or signing password in these files.**
The service-role key must not exist on a client machine at all. `AppConfig` refuses to
treat a key containing `service_role` as valid, but that is a backstop, not permission
to try.

No backend exists yet (Phase 1). The example files are intentionally empty, and the app
runs fully offline without them.

Usage:

    flutter run --flavor dev --dart-define-from-file=config/dev.json
