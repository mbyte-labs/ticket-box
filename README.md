# Ticket Box

Ticket Box keeps track of what you watch, what comes next and where to watch it, all on your phone. No sign-up, no ads, no subscription. Your library lives on your device.

Metadata and images come from [TMDB](https://www.themoviedb.org); your history, ratings and watchlist stay on your device.

A Flutter app for **Android**.

- Homepage: <https://ticket-box.madcodestudios.ro/>
- TMDB API reference: <https://developer.themoviedb.org/docs>

---

## Getting started

Install the [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart `^3.9.2`), then fetch dependencies:

```bash
flutter pub get
```

### Code generation

This project uses `freezed`, `json_serializable`, and `drift`. Regenerate after any change to an annotated class or Drift table:

```bash
dart run build_runner build
```

### API keys

The TMDB and OMDb keys are not in the repository. Copy the template and fill in your own keys
([TMDB](https://www.themoviedb.org/settings/api), [OMDb](https://www.omdbapi.com/apikey.aspx)):

```bash
cp secrets.example.json secrets.json
```

### Run the app

```bash
flutter emulators                          # list available emulators
flutter emulators --launch Pixel10Pro
flutter run --dart-define-from-file=secrets.json
```

### Build a release

See [`docs/RELEASE.md`](./docs/RELEASE.md) for signing, the local release script and the GitHub Actions build.

---

## Project layout

See [`AGENTS.md`](./AGENTS.md) for the full architecture overview — the four-layer split (`api/` → `database/` → `service/` → `ui/`), dependency injection, state management, and sync system.

## New to Flutter?

- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: useful Flutter samples](https://docs.flutter.dev/cookbook)
- [Flutter documentation](https://docs.flutter.dev/)
- Format full code: dart format lib/ test/ 2>&1 | tail -5
