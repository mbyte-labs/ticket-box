# Secrets and release builds

This repository is public. No API key, token, password or keystore may ever be committed.

## What is secret and where it lives

| Secret | Local machine | GitHub Actions secret |
|---|---|---|
| TMDB v3 API key | `secrets.json` → `TMDB_V3_KEY` | `TMDB_V3_KEY` |
| TMDB v4 read access token | `secrets.json` → `TMDB_V4_TOKEN` | `TMDB_V4_TOKEN` |
| OMDb API key | `secrets.json` → `OMDB_API_KEY` | `OMDB_API_KEY` |
| Upload keystore file | outside the repo | `ANDROID_KEYSTORE_BASE64` |
| Keystore password | `android/key.properties` → `storePassword` | `ANDROID_KEYSTORE_PASSWORD` |
| Key alias | `android/key.properties` → `keyAlias` | `ANDROID_KEY_ALIAS` |
| Key password | `android/key.properties` → `keyPassword` | `ANDROID_KEY_PASSWORD` |

`secrets.json`, `android/key.properties` and every `*.ks` / `*.jks` / `*.keystore` file are gitignored.
Keep the keystore outside the repository folder anyway.

Use GitHub **Secrets**, not **Variables**: variables are printed in logs unmasked.

Keys compiled into an app can be extracted from the published bundle by anyone determined enough.
Keeping them out of the repo stops casual scraping; it does not make them truly private. Use
read-only / free-tier keys only.

## Local setup (once)

1. API keys:

   ```bash
   cp secrets.example.json secrets.json
   ```

   Then fill in the three values. Every run and build passes the file:

   ```bash
   flutter run --dart-define-from-file=secrets.json
   ```

   The VS Code launch configurations already do this. Without the flag the app builds, but every
   TMDB / OMDb request is rejected.

2. Signing — create `android/key.properties`:

   ```properties
   storeFile=/absolute/path/outside/the/repo/upload-keystore.ks
   storePassword=...
   keyAlias=...
   keyPassword=...
   ```

## Build a release locally

```bash
tool/build_release.sh
```

It runs pub get, build_runner, analyze and tests, builds the signed bundle with the keys from
`secrets.json`, archives it under `releases/<version>/` (gitignored) and tags `v<version>` locally.
Upload `releases/<version>/app-release.aab` to Play Console by hand.

## Build a release on GitHub Actions

### One-time setup

Run these from the repository folder with the [GitHub CLI](https://cli.github.com). Each command
without `<` prompts for the value, so nothing lands in your shell history.

```bash
gh api -X PUT repos/{owner}/{repo}/environments/release
```

```bash
base64 -i /absolute/path/to/upload-keystore.ks | gh secret set ANDROID_KEYSTORE_BASE64 --env release
```

```bash
gh secret set ANDROID_KEYSTORE_PASSWORD --env release
```

```bash
gh secret set ANDROID_KEY_ALIAS --env release
```

```bash
gh secret set ANDROID_KEY_PASSWORD --env release
```

```bash
jq -j .TMDB_V3_KEY secrets.json | gh secret set TMDB_V3_KEY --env release
```

```bash
jq -j .TMDB_V4_TOKEN secrets.json | gh secret set TMDB_V4_TOKEN --env release
```

```bash
jq -j .OMDB_API_KEY secrets.json | gh secret set OMDB_API_KEY --env release
```

Recommended, in *Settings → Environments → release*: add yourself as a **required reviewer** and
limit deployment branches to `main`. Then no run can read the secrets without your approval.
Also recommended, in *Settings → Actions → General*: require approval for workflows from outside
contributors, and keep "Workflow permissions" on read-only.

### Each release

1. Bump `version:` in `pubspec.yaml`, commit, push to `main`.
2. Start the build:

   ```bash
   gh workflow run release.yml --ref main
   ```

3. Download the result (kept for 7 days):

   ```bash
   gh run download --name "ticketbox-<version>" --dir releases/<version>
   ```

4. Upload `app-release.aab` to Play Console by hand.

The workflow does not upload to Play and stores no Play credentials. Build artifacts of a public
repository can be downloaded by any signed-in GitHub user; the bundle is the same file Play
distributes, so nothing extra is exposed.

### Why this is safe

- `release.yml` only runs when someone with write access starts it; it has no `pull_request` trigger.
- `ci.yml` (push / pull request) uses no secrets, and GitHub never gives secrets to fork pull requests.
- Secrets are environment secrets, reach the scripts only through `env`, and the keystore,
  `key.properties` and `secrets.json` are deleted before the artifact upload.
- Third-party actions are pinned to commit hashes.

## If a secret leaks

Rotate it: regenerate the TMDB / OMDb key in the provider's dashboard, update `secrets.json` and
the GitHub secret, and ship a new release. For the upload keystore, request an upload key reset in
Play Console (*Setup → App signing*).
