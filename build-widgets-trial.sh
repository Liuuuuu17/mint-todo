#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
zsh setup-sparkle.sh
python3 DesktopWidgets/generate-project.py
TRIAL_OUTPUT="${MINT_WIDGET_TRIAL_OUTPUT:-$PWD/../../outputs/MintTodo-widgets-trial}"
TRIAL_BUILD="${MINT_WIDGET_TRIAL_BUILD:-/private/tmp/MintTodoWidgetsTrial-build}"
mkdir -p "$TRIAL_OUTPUT"
xcodebuild -project DesktopWidgets/MintWidgetsTrial.xcodeproj -scheme MintWidgetsTrial \
  -configuration Debug -derivedDataPath "$TRIAL_BUILD" -destination 'platform=macOS' \
  ARCHS="${MINT_WIDGET_TRIAL_ARCHS:-$(uname -m)}" ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY="${MINT_WIDGET_SIGN_IDENTITY:--}" build > "$TRIAL_OUTPUT/build.log" 2>&1 || {
  tail -100 "$TRIAL_OUTPUT/build.log"; exit 1
}
TRIAL_APP="$TRIAL_BUILD/Build/Products/Debug/Mint Todo Widgets Trial.app"
xattr -cr "$TRIAL_APP"
codesign --verify --deep --strict "$TRIAL_APP"
ditto --norsrc --noextattr -c -k --keepParent "$TRIAL_APP" "$TRIAL_OUTPUT/MintTodo-Widgets-Trial.zip"
zsh DesktopWidgets/make-dmg.sh "$TRIAL_APP" "$TRIAL_OUTPUT/MintTodo-Widgets-Trial.dmg"
print -r -- "Built: $TRIAL_APP"
print -r -- "Archive: $TRIAL_OUTPUT/MintTodo-Widgets-Trial.zip"
