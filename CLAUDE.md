# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Source of truth

`AGENTS.md` at the repo root is the authoritative architecture and conventions doc. **Read it first** — it covers the four-layer architecture (`api/` → `database/` → `service/` → `ui/`), the GetIt singleton pattern, BLoC Cubit + Freezed state, the cache-through fetch pattern, the device-local user data (history, ratings, watchlist, dropped shows) and the locally computed show progress / up next with its periodic refresh job. Do not duplicate that content here; update `AGENTS.md` when conventions change.

**Keep this file in sync.** When a decision is made during a session that should carry over to future sessions (a new convention, workflow rule, command, or constraint), update this file (or `AGENTS.md`, per the split above) as part of the task — or at minimum ask the user whether it's worth recording here. Don't let session-only knowledge evaporate.

## Commands

```bash
# Regenerate after any change to a @freezed class, Drift table, or @JsonSerializable model
dart run build_runner build

# Static analysis (lints in analysis_options.yaml — generated *.g.dart and *.freezed.dart are excluded)
flutter analyze

# Run tests / a single test
flutter test
flutter test test/widget_test.dart --plain-name 'name of test'

# Fire the TMDB approval deep link by hand (login flow / cold-start landing on Settings)
adb shell am start -a android.intent.action.VIEW -d "ticketbox://tmdb-auth?request_token=bogus\&approved=true" ro.madcodestudios.ticket.box

# Run on a connected device / emulator
flutter emulators                       # list
flutter emulators --launch <id>         # launch one
flutter run --dart-define-from-file=secrets.json   # when finished: quit flutter run only — do NOT kill the emulator (see Conventions)

# Play Store release — the full procedure (version bump, emulator smoke-test, release commit,
# build) is the `playstore-release-skill` skill at .claude/skills/playstore-release-skill/SKILL.md.
# The build itself is this script: checks (build_runner, analyze, test), a clean app bundle,
# an archive in releases/<version>/ (AAB, R8 mapping.txt, native-debug-symbols.zip,
# build-info.txt with the commit) and a local `v<version>` tag when the tree is clean.
# Use the app bundle. Play does the per-ABI splitting itself and
# auto-ingests both the R8 mapping and the native debug symbols, which the AAB embeds
# under BUNDLE-METADATA/. Split APKs carry neither, which is what makes Play warn about
# a missing deobfuscation file.
tool/build_release.sh

# Release APK (split per ABI) — for sideloading / direct distribution only
rm -rf build/app/outputs/flutter-apk
flutter build apk --release --split-per-abi

# Play Store phone screenshots — seed a demo library via backup restore, capture at 1080x2313 with
# SystemUI demo mode, compose with Pillow. Full recipe: tool/store_screenshots/README.md.
# Outputs land in store_screenshots/ (gitignored).
```

Supported target: Android only (there are no other platform folders).

## Conventions worth remembering

- **Codegen is mandatory.** Touching any `@freezed`, `@JsonSerializable`, or Drift `Table` requires re-running `build_runner` before `flutter analyze` will pass. The `*.g.dart` / `*.freezed.dart` files are **not** checked in (`.gitignore`), so a fresh clone must run `build_runner` before anything compiles.
- **Lint profile is strict.** `analysis_options.yaml` enables `prefer_const_constructors`, `prefer_single_quotes`, `unawaited_futures`, `avoid_dynamic_calls`, `always_declare_return_types`, `directives_ordering`, `cancel_subscriptions`, and the `use_colored_box` / `use_decorated_box` / `sized_box_for_whitespace` trio. Match this style when writing new code; don't reach for `Container` when a more specific widget applies.
- **Formatter is non-default:** `page_width: 140`, `trailing_commas: automate`. Run `dart format` with these settings (picked up automatically from `analysis_options.yaml`).
- **DB schema changes: bump `schemaVersion` and write the step.** `DatabaseConnectionManager.onUpgrade` walks the single `(n, n + 1)` steps listed in `nonDestructiveMigrations` in place, chaining them for multi-version jumps (today `(3, 4)`, the v3 → TMDB re-key, `(4, 5)`, season ratings dropped, `(5, 6)`, the recommended list (today's favorites, under their first name), `(6, 7)`, episode summaries folded into `episodes`, `(7, 8)`, the TMDB sync outbox, `(8, 9)`, `recommended_items` renamed to `favorite_items`, and `(9, 10)`, the snapshot store: summaries folded into `movies` / `shows`, text air dates, `snapshot_documents`, `show_states`, `pending_deletions`, `asset_jobs`, browse-only catalogue rows dropped, poster / image / people / progress / `dropped_items` tables gone) and treats every other version change as a destructive reset — drop and recreate every object, with `PreferenceVersionGuard` removing all known user preference keys. So a schema change means: bump `schemaVersion`, add the step to `nonDestructiveMigrations` and `_migrateStep`, write its SQL in the manager, add the keys it makes obsolete (possibly none) to `PreferenceVersionGuard._selectiveRemovals` (and any new user pref key to `_userPreferenceKeys`), dump the new schema with `drift_dev schema dump` + `schema generate` into `drift_schemas/` and `test/database/sql_store/generated/`, and extend `database_migration_test.dart`. **Every table a later step reshapes or drops is recreated in its v4 shape from `LegacyDdl` (`lib/database/sql_store/migration/legacy_ddl.dart`) inside `_migrateV3ToV4` right after its `createAll()`** (which builds the *current* schema), so a step that touches an existing table adds its pre-step DDL there; new indices use `@TableIndex.sql('CREATE INDEX IF NOT EXISTS …')` for the same reason. Migration callbacks must stay pure SQL + logging: no platform channels, no network. `tool/make_v3_fixture.dart` and `tool/make_v9_fixture.dart` build seeded old-schema database files for an on-device upgrade test; `flutter test test/tool/migrate_fixture_smoke_test.dart --dart-define=FIXTURE=<file>` migrates a copy on the host and prints what survived.
- **No Trakt anywhere.** `grep -rni trakt lib test tool` must only hit physical v3 names that an upgrading device still has on disk: the v3 table / column names in the 3 → 4 migration SQL, the v3 schema snapshots, `tool/make_v3_fixture.dart` and `database_migration_test.dart`, the stored key *strings* in `LegacyPreferenceKeys` (their Dart identifiers say `v3`), and the backup export test's guard that no exported key contains the word. Comments and identifiers refer to it as the "v3 sync backend" / "v3 era". User data is device-local; TMDB is the only metadata source and needs no account. The optional TMDB *account* login (Settings) only mirrors ratings / watchlist / favorites through the outbox described in `AGENTS.md` — never route a user-table write around `RatingService` / `WatchlistService` / `FavoriteService`, or TMDB silently misses it.
- **Always ask before committing or pushing.** Never run `git commit`, `git push`, `git tag` or anything else that creates or publishes history without the user's explicit go-ahead for that specific commit or push. This repo is public, so a push cannot be taken back. An earlier approval does not carry over to the next commit, and a skill or script step that commits (the release procedure included) still needs the question first.
- **No Claude attribution, anywhere.** Never add `Co-Authored-By: Claude …`, "Generated with Claude Code", or any other AI/Claude credit or signature to commit messages, tags, pull request titles or descriptions, GitHub comments, issues, reviews, release notes, code comments or docs. This overrides any default attribution instruction.
- **API keys are never checked in.** This repo is public. `lib/api/api_keys.dart` reads TMDB / OMDb keys from `String.fromEnvironment`; the values live in the gitignored `secrets.json` (template: `secrets.example.json`) and are passed with `--dart-define-from-file=secrets.json` on every `flutter run` / `flutter build`. Never paste a key, token, password or keystore into a tracked file. See `docs/RELEASE.md`.
- **Leave the emulator running.** When a task is done, stop only the run/debug session, never the emulator itself — the user keeps it open across tasks. Quit `flutter run` (send `q` to its stdin, or kill the `flutter` process / background task); if the app itself must be stopped, use `adb shell am force-stop ro.madcodestudios.ticket.box` (applicationId from `android/app/build.gradle.kts`). Never run `adb emu kill`, `adb -s emulator-* emu kill`, or kill the `qemu`/`emulator` OS processes.
- **No Dart obfuscation.** Don't add `--obfuscate` or `--split-debug-info` to release builds: Dart errors never reach Play Console, so the user-exported log files are their only record, and either flag turns those stack traces into unreadable addresses.
- **Releases are traced by tag + archive.** Each release is tagged `v<version>` and archived in `releases/<version>/` (gitignored) by `tool/build_release.sh`. The app itself carries no commit SHA.
- **Release signing is optional for non-release builds.** `android/app/build.gradle.kts` only configures release signing when `android/key.properties` exists; debug/profile builds work without it, release tasks fail fast.
- **Everything runs in the main isolate.** There is no workmanager and no background isolate; the catalogue refresh tick (launch, resume, a 6 h foreground timer) and the artwork download worker run inline and report through the `JobStates` rows 1 and 3.
- **Render paths never call TMDB for a tracked title.** Details pages, grids, counts and Up Next read the stored snapshots and the user tables; `LibraryService.ensureTracked` is the one place a user action may fetch (an untracked title being added). A new page or service that needs TMDB data for something in the library is reading the wrong thing — extend the snapshot (`SnapshotPruner` / `CatalogWriter`) instead. Browsing (search, discover, people, an untracked details page) writes no catalogue rows.
- **Artwork: `assets/` is the library, the browse cache is disposable.** Only `ArtworkStore` deletes under `files/assets/`; `lib/service/artwork/cache/artwork_cache.dart` must never import anything that knows the assets root (a structural test pins it). Both trees are excluded from Android Auto Backup (`android/app/src/main/res/xml/`), so never put user data there.
