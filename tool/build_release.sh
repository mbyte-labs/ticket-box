#!/usr/bin/env bash
# Builds the Play Store app bundle and archives everything needed to trace it back later.
#
#   tool/build_release.sh
#
# 1. Preflight: signing config present, version from pubspec.yaml, commit recorded.
# 2. Checks: pub get, build_runner, analyze (infos are reported, warnings and errors fail), test —
#    stops at the first failure.
# 3. Build: clean release app bundle. No --obfuscate / --split-debug-info on purpose: either
#    one turns the stack traces in user-exported logs into unreadable addresses.
# 4. Archive to releases/<version>/: the AAB, the R8 mapping, the native debug symbols (as a
#    zip Play Console accepts) and build-info.txt. build/ is wiped on every release, this is not.
# 5. Tag v<version> locally when the tree is clean. Never pushes.
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
  echo "error: $*" >&2
  exit 1
}

step() {
  echo
  echo "==> $*"
}

# --- 1. Preflight -------------------------------------------------------------------------

[[ -f android/key.properties ]] || fail 'android/key.properties is missing — release builds need the upload keystore.'

[[ -f secrets.json ]] || fail 'secrets.json is missing — copy secrets.example.json and fill in the API keys (see docs/RELEASE.md).'

version=$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | tr -d '[:space:]')
[[ -n "$version" ]] || fail 'Could not read the version from pubspec.yaml.'

commit=$(git rev-parse --short=12 HEAD)
clean=true
if [[ -n "$(git status --porcelain)" ]]; then
  clean=false
  commit="$commit-dirty"
fi

tag="v$version"
archive="releases/$version"

[[ ! -e "$archive" ]] || fail "$archive already exists. Bump the version, or delete it to rebuild this one."
if $clean && git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  [[ "$(git rev-parse "$tag^{commit}")" == "$(git rev-parse HEAD)" ]] || fail "Tag $tag already exists on another commit. Bump the version."
fi

echo "Version : $version"
echo "Commit  : $commit"
$clean || echo 'warning: the working tree has uncommitted changes — the build is archived but not tagged.'

# --- 2. Checks ----------------------------------------------------------------------------

step 'flutter pub get'
flutter pub get

step 'build_runner'
dart run build_runner build

step 'flutter analyze'
flutter analyze --no-fatal-infos

step 'flutter test'
flutter test

# --- 3. Build -----------------------------------------------------------------------------

step 'flutter build appbundle --release'
rm -rf build/app/outputs/bundle/release
build_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
flutter build appbundle --release --dart-define-from-file=secrets.json

aab=build/app/outputs/bundle/release/app-release.aab
mapping=build/app/outputs/mapping/release/mapping.txt
[[ -f "$aab" ]] || fail "$aab was not produced."
[[ -f "$mapping" ]] || fail "$mapping was not produced."

# --- 4. Archive ---------------------------------------------------------------------------

step "Archiving to $archive"
mkdir -p "$archive"
cp "$aab" "$archive/"
cp "$mapping" "$archive/"

# The bundle carries its native symbols under BUNDLE-METADATA. Repackage them with the ABI
# folders at the zip root, which is the layout Play Console takes for a manual upload.
symbols_tmp=$(mktemp -d)
trap 'rm -rf "$symbols_tmp"' EXIT
unzip -q "$aab" 'BUNDLE-METADATA/com.android.tools.build.debugsymbols/*' -d "$symbols_tmp"
(cd "$symbols_tmp/BUNDLE-METADATA/com.android.tools.build.debugsymbols" && zip -qr - .) >"$archive/native-debug-symbols.zip"

{
  echo "version    : $version"
  echo "commit     : $commit"
  echo "branch     : $(git rev-parse --abbrev-ref HEAD)"
  echo "built (UTC): $build_time"
  echo
  flutter --version
} >"$archive/build-info.txt"

# --- 5. Tag -------------------------------------------------------------------------------

if $clean; then
  if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "Tag $tag already points at this commit."
  else
    git tag -a "$tag" -m "Release $version"
    echo "Tagged $tag. Push it with: git push origin $tag"
  fi
else
  echo 'Not tagged: the working tree had uncommitted changes.'
fi

echo
echo "Done."
echo "  Bundle  : $archive/app-release.aab  (upload this to Play Console)"
echo "  Archive : $archive/"
echo "  Commit  : $commit"
