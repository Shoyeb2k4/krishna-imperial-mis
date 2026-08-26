# Krishna Imperial MIS

Management MIS and profitability system for **Crystal Canopy Rooftop** and
**Hotel Krishna Imperial**.

Owner: Shoyeb Akhtar · Directive: `SHOYEB-HOSPITALITY-MIS` · Master Spec **v1.1**

A genuine installable **Android** app and a compiled **Windows** desktop app built from
one Flutter codebase. Not a web app, not a PWA. Offline-first: every entry saves locally
with no network and syncs without ever duplicating a financial record.

Start with [`CLAUDE.md`](CLAUDE.md), then [`docs/SHOYEB_MASTER_SPEC.md`](docs/SHOYEB_MASTER_SPEC.md).
Current state is always in [`docs/PROJECT_STATUS.md`](docs/PROJECT_STATUS.md) — the
repository, not chat history, is the source of project state.

## Build prerequisites

| | Required |
|---|---|
| Flutter | 3.44.x (Dart 3.12.x) |
| Android | Android SDK **36**, JDK 17 |
| Windows | Visual Studio Build Tools with **Desktop development with C++** *and* the **C++ ATL** component |

> **Windows: the C++ ATL component is mandatory.**
> `flutter_secure_storage_windows` includes `<atlstr.h>`, so without ATL the Windows
> build fails with `C1083: Cannot open include file: 'atlstr.h'`.
> Add it in **Visual Studio Installer → Modify → Individual components →
> "C++ ATL for latest build tools (x86 & x64)"**. This is a one-time machine setup.
> See `docs/DECISIONS.md` D-031.

## Running

```bash
flutter pub get
dart run build_runner build          # Drift table code

flutter run --flavor dev             # Android
flutter run -d windows               # Windows
```

Environment values come from git-ignored files under `config/` — copy an example first
and see [`config/README.md`](config/README.md):

```bash
flutter run --flavor dev --dart-define-from-file=config/dev.json
```

Only the project URL and the **publishable/anon** key ever go in those files. A
service-role key must never exist on a client machine; the app refuses to start if the
configured key looks like one.

## Verifying

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test                                                        # host suite
flutter test integration_test/ -d <device> --flavor dev             # on-device
```

The on-device suite proves encrypted local storage and platform-secure key handling on
the real platform, and must pass on **both** Android and Windows.

## Layout

```
lib/
  app/        bootstrap, environment, routing, platform shells
  core/       design tokens & components, money formatting
  domain/     Money, BusinessDate, sync contracts — pure Dart, no Flutter
  data/       encrypted Drift database, outbox, sync engine
  features/   feature presentation
docs/         specification, architecture, schema, decisions, status, release
```

`domain/` imports nothing from `data/`, `features/` or Flutter. Features never touch
Drift or Supabase types directly.

## Non-negotiables

- Money is **integer paise**. No binary floating point ever touches a currency amount.
- Indian digit grouping: `₹12,36,420`, never `₹1,236,420`.
- One canonical calculation specification; engines are parity-tested and divergence
  fails the build.
- Financial records are **voided, never deleted**. Masters archive.
- Authorisation is server-authoritative. Hiding a button is not security.
- No secrets in the repository. No real financial data in source control.
