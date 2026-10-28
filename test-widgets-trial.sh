#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
zsh setup-sparkle.sh
TRIAL_TEST_DIR="$(mktemp -d /private/tmp/mint-widget-tests.XXXXXX)"
trap 'rm -rf "$TRIAL_TEST_DIR"' EXIT
sed '/^@main struct MintTodoMain/,$d' MintTodo.swift > "$TRIAL_TEST_DIR/MintTodo.swift"
export CLANG_MODULE_CACHE_PATH="$TRIAL_TEST_DIR/cache"
export SWIFT_MODULECACHE_PATH="$TRIAL_TEST_DIR/cache"
SPARKLE_DIR="$PWD/.build-deps/Sparkle-2.10.0"
swiftc -parse-as-library -swift-version 5 -D MINT_WIDGET_TRIAL -D MINT_WIDGET_LOCAL_ACTIONS -target $(uname -m)-apple-macos14.0 \
  -F "$SPARKLE_DIR" -framework Sparkle -Xlinker -rpath -Xlinker "$SPARKLE_DIR" \
  -framework AppKit -framework SwiftUI -framework WidgetKit -framework AppIntents -framework CoreText -framework EventKit -framework Security \
  "$TRIAL_TEST_DIR/MintTodo.swift" FontSettings.swift AppearanceSettings.swift RemindersSync.swift \
  GoalModels.swift OrbPlanSchema.swift GoalStore.swift MarkdownNotes.swift PlanPrompt.swift AIClient.swift AISettingsView.swift \
  GoalEditorView.swift GoalViews.swift LongTermTasksView.swift PlanRevision.swift WindowResizeEdges.swift AppUpdater.swift NaturalTaskTime.swift Tests/NaturalTimeTests.swift \
  DesktopWidgets/WidgetData.swift DesktopWidgets/WidgetActionIntent.swift DesktopWidgets/MintWidgetViews.swift DesktopWidgets/WidgetTrialCoordinator.swift \
  Tests/WidgetTrialTests.swift -o "$TRIAL_TEST_DIR/WidgetTests"
"$TRIAL_TEST_DIR/WidgetTests"
