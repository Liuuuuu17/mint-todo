#!/bin/zsh
set -euo pipefail
if (( $# != 2 )) || [[ ! -d "$1/Contents" ]]; then
  print -u2 'Usage: zsh DesktopWidgets/make-dmg.sh "/path/to/Mint Todo Widgets Trial.app" /path/to/MintTodo-Widgets-Trial.dmg'
  exit 2
fi
TRIAL_APP="$1"
TRIAL_DMG="$2"
TRIAL_STAGE="$(mktemp -d /private/tmp/mintwidgets-dmg.XXXXXX)"
trap 'rm -rf "$TRIAL_STAGE"' EXIT
codesign --verify --deep --strict "$TRIAL_APP"
ditto --norsrc --noextattr "$TRIAL_APP" "$TRIAL_STAGE/Mint Todo Widgets Trial.app"
ln -s /Applications "$TRIAL_STAGE/Applications"
mkdir -p "${TRIAL_DMG:h}"
hdiutil create -quiet -ov -format UDZO -imagekey zlib-level=9 -volname 'Mint Todo Widgets Trial' -srcfolder "$TRIAL_STAGE" "$TRIAL_DMG"
hdiutil verify -quiet "$TRIAL_DMG"
print -r -- "Disk image: $TRIAL_DMG"
