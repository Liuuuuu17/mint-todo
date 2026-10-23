#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
BUILD_DIR="$(mktemp -d /private/tmp/minttodo.XXXXXX)"
APP="$BUILD_DIR/Mint Todo.app"
OUTPUT_DIR="${ORBTODO_OUTPUT_DIR:-$PWD/dist}"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources" "$BUILD_DIR/icon.iconset"
mkdir -p "$BUILD_DIR/swift-cache" "$OUTPUT_DIR"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/swift-cache"
export SWIFT_MODULECACHE_PATH="$BUILD_DIR/swift-cache"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -framework AppKit make-icon.swift -o "$BUILD_DIR/make-icon"
"$BUILD_DIR/make-icon" "$BUILD_DIR/icon-1024.png"
for n in 16 32 128 256 512; do
  sips -z "$n" "$n" "$BUILD_DIR/icon-1024.png" --out "$BUILD_DIR/icon.iconset/icon_${n}x${n}.png" >/dev/null
  double=$((n * 2))
  sips -z "$double" "$double" "$BUILD_DIR/icon-1024.png" --out "$BUILD_DIR/icon.iconset/icon_${n}x${n}@2x.png" >/dev/null
done
iconutil -c icns "$BUILD_DIR/icon.iconset" -o "$APP/Contents/Resources/MintTodo.icns"
swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos13.0 -O -framework AppKit -framework SwiftUI -framework CoreText -framework EventKit -framework Security MintTodo.swift FontSettings.swift AppearanceSettings.swift RemindersSync.swift GoalModels.swift OrbPlanSchema.swift GoalStore.swift MarkdownNotes.swift PlanPrompt.swift AIClient.swift AISettingsView.swift GoalEditorView.swift GoalViews.swift LongTermTasksView.swift PlanRevision.swift WindowResizeEdges.swift -o "$BUILD_DIR/MintTodo-arm64"
swiftc -parse-as-library -swift-version 5 -target x86_64-apple-macos13.0 -O -framework AppKit -framework SwiftUI -framework CoreText -framework EventKit -framework Security MintTodo.swift FontSettings.swift AppearanceSettings.swift RemindersSync.swift GoalModels.swift OrbPlanSchema.swift GoalStore.swift MarkdownNotes.swift PlanPrompt.swift AIClient.swift AISettingsView.swift GoalEditorView.swift GoalViews.swift LongTermTasksView.swift PlanRevision.swift WindowResizeEdges.swift -o "$BUILD_DIR/MintTodo-x86_64"
lipo -create "$BUILD_DIR/MintTodo-arm64" "$BUILD_DIR/MintTodo-x86_64" -output "$APP/Contents/MacOS/MintTodo"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
rm -f "$OUTPUT_DIR/MintTodo-macOS.zip"
ditto -c -k --keepParent "$APP" "$OUTPUT_DIR/MintTodo-macOS.zip"
if [[ -n "${ORBTODO_BUILD_PATH_FILE:-}" ]]; then
  print -r -- "$APP" > "$ORBTODO_BUILD_PATH_FILE"
fi
echo "Built: $OUTPUT_DIR/MintTodo-macOS.zip"
