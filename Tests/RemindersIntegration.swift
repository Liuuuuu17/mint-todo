import AppKit
import EventKit
import Foundation

// Opt-in integration executable: creates and removes only its own uniquely named local list.
// Does not request access, read reminder content from existing lists, or change iCloud settings.
@main struct RemindersIntegration {
    @MainActor static func main() async {
        _ = NSApplication.shared
        let eventStore = EKEventStore()
        let authorization = EKEventStore.authorizationStatus(for: .reminder)
        let authorized: Bool
        if #available(macOS 14, *) { authorized = authorization == .fullAccess }
        else { authorized = authorization == .authorized }
        guard authorized, let local = eventStore.sources.first(where: { $0.sourceType == .local }) else {
            print("SKIP: existing full authorization and local source required; no permissions requested")
            return
        }
        let id = UUID().uuidString
        let suite = "com.minttodo.integration.\(id)"
        let prefs = UserDefaults(suiteName: suite)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MintTodoSyncTest-\(id)")
        let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
        calendar.source = local
        calendar.title = "Mint Todo QA \(id)"
        var created = false
        var sync: RemindersSync?
        defer {
            sync?.setEnabled(false)
            if created { try? eventStore.removeCalendar(calendar, commit: true) }
            prefs.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        do {
            try eventStore.saveCalendar(calendar, commit: true); created = true
            let daily = TaskStore(folder: folder, watch: false)
            // New stores contain onboarding items: replace only this isolated test file's contents.
            let task = Todo(title: "Mint sync fixture", category: "QA", status: .todo,
                            dueAt: Date(timeIntervalSince1970: 1_800_000_000))
            daily.applyReminderChanges(updates: [task], deletedIDs: Set(daily.tasks.map(\.id)))
            let manager = RemindersSync(tasks: daily, preferences: prefs, eventStore: eventStore)
            sync = manager
            manager.chooseList(calendar.calendarIdentifier)
            manager.setEnabled(true)
            try await wait { manager.status.hasPrefix("已同步") }
            var reminders = await fetch(eventStore, calendar)
            try require(reminders.count == 1 && reminders[0].title == task.title, "local creation reaches Apple Reminders")
            try require(abs((Calendar.current.date(from: reminders[0].dueDateComponents!)!).timeIntervalSince(task.dueAt!)) < 60, "deadline reaches Apple Reminders")
            reminders[0].title = "Edited in Apple Reminders"
            reminders[0].isCompleted = true
            try eventStore.save(reminders[0], commit: true)
            manager.scheduleSync()
            try await wait { daily.tasks.first?.title == "Edited in Apple Reminders" && daily.tasks.first?.status == .completed }
            try require(daily.tasks.count == 1 && daily.tasks[0].id == task.id, "remote edit/completion preserve identity")
            daily.setStatus(daily.tasks[0], .pending)
            manager.scheduleSync()
            try await wait { manager.status.hasPrefix("已同步") }
            reminders = await fetch(eventStore, calendar)
            try require(!reminders[0].isCompleted, "local reopening reaches Apple Reminders")
            // Start a fetch then invalidate selection: its callback must not import stale data.
            manager.scheduleSync()
            manager.chooseList("")
            try await Task.sleep(nanoseconds: 300_000_000)
            try require(daily.tasks.count == 1, "cancelled list fetch preserves local tasks")
            manager.chooseList(calendar.calendarIdentifier)
            manager.setEnabled(true)
            try await Task.sleep(nanoseconds: 300_000_000)
            reminders = await fetch(eventStore, calendar)
            try eventStore.remove(reminders[0], commit: true)
            manager.scheduleSync()
            try await wait { daily.tasks.isEmpty }
            try require(daily.tasks.isEmpty, "remote deletion syncs to isolated daily list")
            // Invalid saved ID is paused rather than treating unavailable list as empty.
            manager.chooseList("nonexistent-\(id)")
            manager.refreshConnection()
            try require(!manager.enabled && manager.status.contains("暂不可用"), "stale selection pauses with recoverable message")
            print("PASS: 7 live local EventKit checks; test list cleaned up; iCloud not used")
        } catch {
            sync?.setEnabled(false)
            if created { try? eventStore.removeCalendar(calendar, commit: true); created = false }
            prefs.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
            fputs("INTEGRATION FAILED: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw PlanFailure("Timed out waiting for sync")
    }
    static func require(_ value: Bool, _ title: String) throws {
        if !value { throw PlanFailure(title) }
    }
    static func fetch(_ store: EKEventStore, _ calendar: EKCalendar) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: store.predicateForReminders(in: [calendar])) {
                continuation.resume(returning: $0 ?? [])
            }
        }
    }
}
