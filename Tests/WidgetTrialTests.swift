import AppKit
import Foundation

@main struct WidgetTrialTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
        checks += 1
        if try !condition() { throw PlanFailure("Widget test failed: " + label) }
    }

    @MainActor static func main() {
        do { try run() }
        catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
    @MainActor static func run() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MintWidgetTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try NaturalTimeTests.run { condition, name in try check(condition, name) }
        try todayTests()
        try journalTests(root.appendingPathComponent("journal"))
        try syncTests(root.appendingPathComponent("sync"))
        print("PASS: \(checks) widget checks — today filtering, command replay, app/goal sync, restart and write-failure recovery")
    }

    static func todayTests() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 23, minute: 59))!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        var snapshot = MintWidgetSnapshot.sample(now: now)
        snapshot.tasks = [
            MintWidgetTask(id: UUID(), title: "today", category: "QA", status: "todo", dueAt: now, subtasks: []),
            MintWidgetTask(id: UUID(), title: "overdue", category: "QA", status: "pending", dueAt: now.addingTimeInterval(-86400), subtasks: []),
            MintWidgetTask(id: UUID(), title: "undated", category: "QA", status: "todo", subtasks: []),
            MintWidgetTask(id: UUID(), title: "tomorrow", category: "QA", status: "todo", dueAt: tomorrow, subtasks: []),
            MintWidgetTask(id: UUID(), title: "done today", category: "QA", status: "completed", completedAt: now, subtasks: []),
            MintWidgetTask(id: UUID(), title: "done yesterday", category: "QA", status: "completed", completedAt: now.addingTimeInterval(-86400), subtasks: []),
            MintWidgetTask(id: UUID(), title: "cancelled", category: "QA", status: "cancelled", subtasks: [])
        ]
        try check(Set(snapshot.allPendingTasks.map(\.title)) == Set(["today", "overdue", "undated", "tomorrow"]), "all pending includes future tasks and excludes completed/cancelled")
        try check(snapshot.allPendingTasks.first?.title == "overdue", "all pending sorts by due date")
        let visible = snapshot.todayTasks(now: now, calendar: calendar)
        try check(Set(visible.map(\.title)) == Set(["today", "overdue", "undated", "done today"]), "today includes overdue/undated and excludes tomorrow/cancelled/history")
        try check(visible.first?.title == "overdue" && visible.last?.title == "done today", "due ordering and completed items last")
        try check(snapshot.todayTasks(now: tomorrow, calendar: calendar).contains { $0.title == "tomorrow" }, "midnight changes eligibility")
        try check(!snapshot.todayTasks(now: tomorrow, calendar: calendar).contains { $0.title == "done today" }, "midnight resets today's completion count")
    }

    static func journalTests(_ folder: URL) throws {
        let files = MintWidgetFiles(folder: folder)
        let snapshot = MintWidgetSnapshot.sample()
        try files.writeSnapshot(snapshot)
        let task = snapshot.tasks[0]
        let command = MintWidgetCommand(target: .daily, taskID: task.id, completed: true)
        let actionURL = MintWidgetActionLink.url(target: .daily, taskID: task.id, completed: true)
        try check(MintWidgetActionLink.command(from: actionURL)?.taskID == task.id, "local widget action link preserves the task identity")
        try check(MintWidgetActionLink.command(from: URL(string: "minttodo-widgets-trial://complete?target=daily&id=invalid&completed=1")!) == nil, "malformed action links are rejected")
        try check(MintWidgetActionLink.command(from: URL(string: actionURL.absoluteString + "&completed=0")!) == nil, "ambiguous duplicate parameters are rejected")
        try files.enqueue(command)
        let displayed = try files.displayedSnapshot()
        try check(displayed.tasks[0].isCompleted, "closed app still has pending completion in widget")
        try check(!files.readSnapshot().tasks[0].isCompleted, "pending commands never rewrite app snapshot")
        try check(displayed.goals[0].completed == snapshot.goals[0].completed + 1, "pending linked completion updates goal progress")
        try check(displayed.applying([command]) == displayed, "command replay is idempotent")
        let goal = snapshot.goals[0].tasks[1]
        let undo = MintWidgetCommand(target: .goal, taskID: goal.id, completed: false, createdAt: command.createdAt.addingTimeInterval(1))
        try files.enqueue(undo)
        try check(!files.displayedSnapshot().tasks[0].isCompleted, "goal command restores linked daily item in preview")
        try files.acknowledge(command)
        try files.acknowledge(command)
        try check(files.commands().count == 1, "acknowledgment is idempotent and preserves newer commands")
        try Data("malformed".utf8).write(to: files.commandsFolder.appendingPathComponent("bad.json"))
        try check(files.commands().count == 1, "malformed journal entry does not block valid commands")
        try files.acknowledge(undo)
        let rapidFirst = MintWidgetCommand(target: .daily, taskID: task.id, completed: true, createdAt: Date(timeIntervalSince1970: 1_792_973_000.1))
        let rapidLast = MintWidgetCommand(target: .daily, taskID: task.id, completed: false, createdAt: Date(timeIntervalSince1970: 1_792_973_000.2))
        try files.enqueue(rapidFirst); try files.enqueue(rapidLast)
        try check(files.commands().map(\.completed) == [true, false], "subsecond interaction order survives encoding")
        try files.acknowledge(rapidFirst); try files.acknowledge(rapidLast)
        DispatchQueue.concurrentPerform(iterations: 20) { i in
            try! files.enqueue(MintWidgetCommand(target: .daily, taskID: task.id, completed: i % 2 == 0))
        }
        try check(files.commands().count == 20, "concurrent immutable journal writes do not lose commands")
    }

    @MainActor static func syncTests(_ folder: URL) throws {
        let daily = TaskStore(folder: folder, watch: false)
        let goals = GoalStore(daily: daily, folder: folder)
        var goal = Goal(title: "Widget QA")
        var phase = GoalPhase(title: "First phase")
        phase.tasks = [GoalTask(goalID: goal.id, phaseID: phase.id, title: "Linked item"), GoalTask(goalID: goal.id, phaseID: phase.id, title: "Goal-only item")]
        goal.phases = [phase]
        let id = goals.insert(goal)!
        let linkedID = goals.goals.first { $0.id == id }!.phases[0].tasks[0].id
        let unlinkedID = goals.goals.first { $0.id == id }!.phases[0].tasks[1].id
        goals.attach(linkedID, today: true)
        let dailyID = goals.task(linkedID)!.linkedTodoID!
        let files = MintWidgetFiles(folder: folder)
        try files.enqueue(MintWidgetCommand(target: .daily, taskID: dailyID, completed: true))
        let coordinator = MintWidgetTrialCoordinator(daily: daily, goals: goals, watch: false, seedDemo: false, themeProvider: { _ in MintWidgetTheme() })
        daily.onChange = { [weak goals, weak coordinator] in goals?.reconcileTodos(); coordinator?.refresh() }
        goals.onChange = { [weak coordinator] in coordinator?.refresh() }
        try check(daily.tasks.first { $0.id == dailyID }?.status == .completed, "launch replays widget completion into daily store")
        try check(goals.task(linkedID)?.state == .completed, "launch reconciles linked goal state")
        try check(files.commands().isEmpty, "persisted app state acknowledges widget command")
        let restarted = TaskStore(folder: folder, watch: false)
        try check(restarted.tasks[0].status == .completed, "widget completion survives app restart")
        daily.setStatus(daily.tasks[0], .todo)
        try check(!files.readSnapshot().tasks[0].isCompleted, "main app restoration updates widget snapshot")
        coordinator.submit(MintWidgetCommand(target: .goal, taskID: unlinkedID, completed: true))
        try check(goals.task(unlinkedID)?.state == .completed && coordinator.snapshot.goals[0].completed == 1, "large widget completes goal-only item")
        try check(daily.tasks.count == 1, "goal-only completion does not invent a daily task")

        let original = try Data(contentsOf: daily.fileURL)
        try FileManager.default.removeItem(at: daily.fileURL)
        try FileManager.default.createDirectory(at: daily.fileURL, withIntermediateDirectories: true)
        coordinator.submit(MintWidgetCommand(target: .daily, taskID: dailyID, completed: true))
        try check(daily.tasks[0].status == .todo && files.commands().count == 1, "failed daily write retains command without false app completion")
        try check(coordinator.notice != nil, "failed save is reported")
        try FileManager.default.removeItem(at: daily.fileURL)
        try original.write(to: daily.fileURL, options: .atomic)
        coordinator.refresh()
        try check(daily.tasks[0].status == .completed && files.commands().isEmpty, "queued write retries after storage recovery")

        daily.setStatus(daily.tasks[0], .todo)
        try FileManager.default.removeItem(at: files.snapshotURL)
        try FileManager.default.createDirectory(at: files.snapshotURL, withIntermediateDirectories: true)
        coordinator.submit(MintWidgetCommand(target: .daily, taskID: dailyID, completed: true))
        try check(daily.tasks[0].status == .completed && files.commands().count == 1, "snapshot write failure cannot acknowledge pending command")
        try FileManager.default.removeItem(at: files.snapshotURL)
        coordinator.refresh()
        try check(files.commands().isEmpty && files.readSnapshot().tasks[0].isCompleted, "snapshot recovery safely replays persisted completion")
        coordinator.submit(MintWidgetCommand(target: .daily, taskID: UUID(), completed: true))
        try check(files.commands().isEmpty && daily.tasks.count == 1, "stale commands do not resurrect deleted tasks")
        daily.setStatus(daily.tasks[0], .cancelled)
        coordinator.submit(MintWidgetCommand(target: .daily, taskID: dailyID, completed: true))
        try check(daily.tasks[0].status == .cancelled && files.commands().isEmpty, "stale widget commands preserve cancellation")
    }
}
