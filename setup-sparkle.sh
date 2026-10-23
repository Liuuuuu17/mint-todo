#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
SPARKLE_DIR="$PWD/.build-deps/Sparkle-2.10.0"
SPARKLE_SHA='c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c'
if [[ -f "$SPARKLE_DIR/Sparkle.framework/Sparkle" && -f "$SPARKLE_DIR/bin/generate_appcast" ]]; then exit 0; fi
DOWNLOAD_DIR="$(mktemp -d /private/tmp/mint-sparkle.XXXXXX)"
trap 'rm -rf "$DOWNLOAD_DIR"' EXIT
curl -fLsS --retry 2 'https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz' -o "$DOWNLOAD_DIR/Sparkle.tar.xz"
ACTUAL_SHA="$(shasum -a 256 "$DOWNLOAD_DIR/Sparkle.tar.xz" | cut -d ' ' -f 1)"
if [[ "$ACTUAL_SHA" != "$SPARKLE_SHA" ]]; then print -u2 'Sparkle checksum mismatch; build stopped.'; exit 1; fi
mkdir -p "$SPARKLE_DIR"
tar -xJf "$DOWNLOAD_DIR/Sparkle.tar.xz" -C "$SPARKLE_DIR"
