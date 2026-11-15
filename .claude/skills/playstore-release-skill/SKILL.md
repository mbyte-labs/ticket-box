---
name: playstore-release-skill
description: Prepare the Google Play Store release bundle for Ticket Box. Use when asked to prepare a Play Store release, build the release bundle/AAB, bump the version for release, or ship a new version to Google Play. Bumps the pubspec version, smoke-tests the app on the Android emulator, commits the bump, then builds, archives and tags the release with tool/build_release.sh.
---

# Play Store Release

Prepare a Google Play Store release bundle. Run the steps **in order**; if any step fails, stop and report — do not continue to the build with a broken app.

## Step 1 — Bump the version in `pubspec.yaml`

Read the `version:` line in `pubspec.yaml`. It has the format `X.Y.Z+B` (e.g. `1.3.8+5127`).

- Increment the **patch** number: `Z` → `Z+1`
- Increment the **build** number: `B` → `B+1`

Example: `1.3.8+5127` → `1.3.9+5128`. Edit the line in place and report the old → new version to the user. A pubspec version change needs no codegen (`build_runner` is not required).

## Step 2 — Smoke-test on the Android emulator

Verify the app actually starts before shipping it:

1. Check `flutter devices` for a running Android emulator. If none is running, list emulators with `flutter emulators` and start one with `flutter emulators --launch <id>`, then wait for it to boot (poll `adb shell getprop sys.boot_completed` until it prints `1`).
2. Start `flutter run --dart-define-from-file=secrets.json` as a background task and monitor its output.
3. The launch counts as successful when the app is installed and running (the "Flutter run key commands" banner appears / first frame is rendered). Keep watching the output briefly (~15–30 s) for exceptions, crash stack traces, or startup errors.
4. If the app crashes or logs startup errors, **abort the release**: stop the run, report the errors, and leave the version bump in place for the user to decide (revert or fix).

## Step 3 — Stop the app (NEVER the emulator)

Quit only the run session, per repo convention — the user keeps the emulator open across tasks:

- Quit `flutter run` by sending `q` to its stdin, or stop/kill the background `flutter` task.
- If the app itself must be force-stopped: `adb shell am force-stop ro.madcodestudios.ticket.box`
- **Never** run `adb emu kill`, `adb -s emulator-* emu kill`, or kill the `qemu`/`emulator` OS processes.

## Step 4 — Commit the version bump

The release must be built from a clean tree, otherwise `tool/build_release.sh` archives it with a `-dirty` commit and does not tag it.

1. Run `git status`. If anything besides `pubspec.yaml` is modified, stop and ask the user how to handle it.
2. Confirm with the user, then commit just `pubspec.yaml` as `Release X.Y.Z+B`.

## Step 5 — Build, archive and tag

```bash
tool/build_release.sh
```

It runs pub get, build_runner, `flutter analyze` and `flutter test`, then builds a clean release app bundle. It copies the AAB, the R8 `mapping.txt`, the native debug symbols and a `build-info.txt` (version, commit, Flutter version) into `releases/X.Y.Z+B/`, and creates the local annotated tag `vX.Y.Z+B`. It never pushes. If it fails, stop and report the output.

## Step 6 — Report

Tell the user:

- The new version (`X.Y.Z+B`) now in `pubspec.yaml`, and the release commit's SHA.
- The tag `vX.Y.Z+B`, and that it still needs pushing (`git push origin vX.Y.Z+B`) along with the commit.
- The bundle to upload: `releases/X.Y.Z+B/app-release.aab`. Play does the per-ABI splitting itself and auto-ingests the R8 mapping and native debug symbols embedded in the bundle.
- That `releases/X.Y.Z+B/` is the only copy of this build's mapping and symbols outside Play, and is worth backing up.
