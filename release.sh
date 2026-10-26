#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
zsh setup-sparkle.sh
SPARKLE_DIR="$PWD/.build-deps/Sparkle-2.10.0"
RELEASE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
RELEASE_OUTPUT="${1:-$PWD/release/v$RELEASE_VERSION}"
EXPECTED_PUBLIC="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' Info.plist)"
ACTUAL_PUBLIC="$("$SPARKLE_DIR/bin/generate_keys" --account com.codex.orbtodo.release -p)"
if [[ "$ACTUAL_PUBLIC" != "$EXPECTED_PUBLIC" ]]; then print -u2 'Release signing key does not match Info.plist. Use the original signing Mac/keychain.'; exit 1; fi
mkdir -p "$RELEASE_OUTPUT"
ORBTODO_OUTPUT_DIR="$RELEASE_OUTPUT" zsh build.sh
# This version directory owns one freshly signed feed; never reuse stale signatures after a rebuild.
rm -f "$RELEASE_OUTPUT/appcast.xml"
# Only the ZIP is an automatic-update archive. Keep the DMG out of Sparkle's scan.
APPCAST_DIR="$(mktemp -d /private/tmp/minttodo-appcast.XXXXXX)"
trap 'rm -rf "$APPCAST_DIR"' EXIT
cp "$RELEASE_OUTPUT/MintTodo-macOS.zip" "$APPCAST_DIR/MintTodo-macOS.zip"
"$SPARKLE_DIR/bin/generate_appcast" --account com.codex.orbtodo.release --maximum-deltas 0 --download-url-prefix "https://github.com/Liuuuuu17/mint-todo/releases/download/v$RELEASE_VERSION/" --link 'https://github.com/Liuuuuu17/mint-todo/releases/latest' "$APPCAST_DIR"
cp "$APPCAST_DIR/appcast.xml" "$RELEASE_OUTPUT/appcast.xml"
print -r -- "Publish tag v$RELEASE_VERSION and upload MintTodo-macOS.dmg, MintTodo-macOS.zip and appcast.xml from $RELEASE_OUTPUT to the same GitHub Release. Mark it as latest. Never edit signed appcast/archive bytes after signing."
