#!/bin/zsh
set -euo pipefail
if (( $# != 2 )) || [[ ! -d "$1/Contents" ]]; then
  print -u2 'Usage: zsh make-dmg.sh "/path/to/Mint Todo.app" /path/to/MintTodo-macOS.dmg'
  exit 2
fi
APP="$1"
OUTPUT="$2"
STAGING="$(mktemp -d /private/tmp/minttodo-dmg.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Mint Todo.app"
ln -s /Applications "$STAGING/Applications"
mkdir -p "${OUTPUT:h}"
rm -f "$OUTPUT"
hdiutil create -quiet -format UDZO -imagekey zlib-level=9 -volname 'Mint Todo' -srcfolder "$STAGING" "$OUTPUT"
hdiutil verify -quiet "$OUTPUT"
