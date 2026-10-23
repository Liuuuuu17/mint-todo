#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
TEST_DIR="$(mktemp -d /private/tmp/mint-goal-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
sed '/^@main struct MintTodoMain/,$d' MintTodo.swift > "$TEST_DIR/MintTodo.swift"
export CLANG_MODULE_CACHE_PATH="$TEST_DIR/cache"
export SWIFT_MODULECACHE_PATH="$TEST_DIR/cache"
TEST_SOURCE="Tests/GoalTests.swift"
if [[ "${1:-}" == "--local-reminders" ]]; then TEST_SOURCE="Tests/RemindersIntegration.swift"; fi
swiftc -parse-as-library -swift-version 5 -target $(uname -m)-apple-macos13.0 -framework AppKit -framework SwiftUI -framework CoreText -framework EventKit -framework Security "$TEST_DIR/MintTodo.swift" FontSettings.swift AppearanceSettings.swift RemindersSync.swift GoalModels.swift OrbPlanSchema.swift GoalStore.swift MarkdownNotes.swift PlanPrompt.swift AIClient.swift AISettingsView.swift GoalEditorView.swift GoalViews.swift LongTermTasksView.swift PlanRevision.swift "$TEST_SOURCE" -o "$TEST_DIR/GoalTests"
"$TEST_DIR/GoalTests"
