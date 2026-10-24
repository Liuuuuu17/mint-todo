import AppKit
import Foundation

final class MockAPIProtocol: URLProtocol {
    static var response: (URLRequest) throws -> (Int, Data) = { _ in (200, Data()) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, data) = try Self.response(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
@main struct GoalTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        checks += 1; if try !condition() { throw PlanFailure("TEST FAILED: \(name)") }
    }
    static func rejects(_ name: String, _ action: () throws -> Void) throws {
        checks += 1
        do { try action() } catch { return }
        throw PlanFailure("TEST FAILED: accepted \(name)")
    }
    static let sample = #"""
    {"schema_version":"orb-todo-plan-v1","goal":{"title":"完成一个研究项目","description":"从整理资料到交付成果","start_date":"2026-10-22","due_date":null},"phases":[{"title":"资料整理","start_date":null,"due_date":"2026-11-30","tasks":[{"title":"检查结构与序列信息","due_date":null,"estimated_minutes":90,"notes":"## 任务目的\n理解结构组成。\n## 操作步骤\n- [ ] 下载文件\n- [ ] 核对信息\n```python\nprint('check')\n```\n## 完成标准\n形成信息表。"},{"title":"整理结果","due_date":"2026-11-20","estimated_minutes":null,"notes":"1. 收集输出\n2. 整理说明"}]},{"title":"分析与交付","start_date":"2026-12-01","due_date":null,"tasks":[]}]}
    """#
    @MainActor static func main() async {
        do {
            _ = NSApplication.shared
            try schemaTests()
            try storageTests()
            try revisionTests()
            try resizeTests()
            try dailyWorkflowTests()
            try dockingTests()
            try await apiTests()
            print("PASS: \(checks) checks — schema, transactions, backup, linkage, progress, Markdown, API and Keychain")
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
    static func dockingTests() throws {
        let screen = NSRect(x: 100, y: 50, width: 1400, height: 1000)
        for (x, y, expectedX, expectedY) in [(120.0, 70.0, 112.0, 62.0), (1100, 70, 1436, 62), (120, 700, 112, 986), (1100, 700, 1436, 986)] {
            let origin = WindowDockGeometry.collapsed(from: NSRect(x: x, y: y, width: 320, height: 380), screen: screen)
            try check(origin == NSPoint(x: expectedX, y: expectedY), "collapse chooses correct screen corner")
            let expanded = WindowDockGeometry.expanded(from: NSRect(origin: origin, size: NSSize(width: 52, height: 52)), size: NSSize(width: 405, height: 560), screen: screen)
            try check(screen.contains(expanded), "expanded window stays on selected screen")
        }
        let moved = WindowDockGeometry.clamped(NSRect(x: -200, y: 1300, width: 405, height: 560), to: screen)
        try check(moved.minX == screen.minX && moved.maxY == screen.maxY, "drag release stays reachable")
    }
    @MainActor static func dailyWorkflowTests() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TaskStore(folder: folder, watch: false)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))! }
        let friday = date(2026, 10, 23)
        var task = Todo(title: "重复任务", category: "生活", createdAt: friday, dueAt: friday)
        task.repeatRule = .weekdays; task.repeatInterval = 2; task.occurrenceAt = friday
        try check(store.saveEdited(task), "draft saves atomically")
        store.setStatus(task, .completed, now: friday)
        let completed = store.tasks[0]
        try check(!completed.visibleInTodo(), "completion immediately leaves todo list")
        try check(store.tasks.contains(where: { $0.id == task.id && $0.status == .completed }), "completion retained in completed list")
        try check(completed.completedAt == friday, "completion date persisted")
        store.refreshRecurring(now: date(2026, 10, 24), calendar: calendar)
        try check(store.tasks.count == 1, "weekend has no weekday recurrence")
        store.refreshRecurring(now: date(2026, 10, 26), calendar: calendar)
        try check(store.tasks.count == 2 && store.tasks[1].status == .todo && store.tasks[1].category == task.category, "next weekday occurrence")
        try check(calendar.component(.hour, from: store.tasks[1].dueAt!) == 9, "due time retained")
        store.refreshRecurring(now: date(2026, 10, 26), calendar: calendar)
        try check(store.tasks.count == 2, "recurrence idempotent")
        let restarted = TaskStore(folder: folder, watch: false)
        try check(restarted.tasks.count == 2 && restarted.tasks[0].recurrenceSpawnedAt != nil, "recurrence restart deduplication")
        store.setStatus(completed, .todo)
        try check(store.tasks[0].completedAt == nil && store.tasks[0].visibleInTodo(), "undo completion restores todo")
        try check(RepeatRule.interval.next(after: friday, interval: 3, calendar: calendar) == date(2026, 10, 26), "every N days")
        try check(RepeatRule.daily.next(after: date(2026, 3, 7), interval: 1, calendar: calendar) == date(2026, 3, 8), "calendar recurrence across DST")
        var once = Todo(title: "一次任务", category: "生活", createdAt: friday)
        once.completedAt = friday; once.status = .completed
        try check(store.saveEdited(once), "one-off task saves")
        let before = store.tasks.count
        store.refreshRecurring(now: date(2026, 10, 30), calendar: calendar)
        try check(store.tasks.count == before, "one-off does not recur")
        let bad = folder.appendingPathComponent("blocked")
        let rollback = TaskStore(folder: bad, watch: false)
        try FileManager.default.removeItem(at: rollback.fileURL)
        try FileManager.default.createDirectory(at: rollback.fileURL, withIntermediateDirectories: true)
        try check(!rollback.saveEdited(task) && rollback.tasks.isEmpty, "failed draft save rolls back")
    }
    @MainActor static func schemaTests() throws {
        let parsed = try PlanCodec.parse(sample)
        try check(parsed.goal.phases.count == 2 && parsed.goal.taskCount == 2, "hierarchy/order")
        try check(parsed.goal.phases[0].tasks[0].notes.contains("```python"), "Markdown newline preservation")
        try check(!parsed.warnings.isEmpty, "empty phase warning")
        let fenced = try PlanCodec.parse("```json\n" + sample + "\n```")
        try check(fenced.goal.title == parsed.goal.title, "fenced JSON")
        // The final line is the complete literal JSON example, independent of descriptive schema braces.
        let example = PlanPrompt.contract.components(separatedBy: "\n").first { $0.hasPrefix("{\"schema_version\"") }!
        try check(try PlanCodec.parse(example).goal.taskCount == 1, "copied prompt example is valid JSON")
        try rejects("missing goal title") { _ = try PlanCodec.parse(sample.replacingOccurrences(of: "\"title\":\"完成一个研究项目\",", with: "")) }
        try rejects("unknown schema") { _ = try PlanCodec.parse(sample.replacingOccurrences(of: "orb-todo-plan-v1", with: "v9")) }
        try rejects("wrong type") { _ = try PlanCodec.parse(sample.replacingOccurrences(of: "\"estimated_minutes\":90", with: "\"estimated_minutes\":\"90\"")) }
        try rejects("invalid calendar date") { _ = try PlanCodec.parse(sample.replacingOccurrences(of: "2026-11-30", with: "2026-02-30")) }
        try rejects("reversed dates") { _ = try PlanCodec.parse(sample.replacingOccurrences(of: "\"due_date\":null},\"phases\"", with: "\"due_date\":\"2020-01-01\"},\"phases\"")) }
        try rejects("negative estimate") { _ = try PlanCodec.parse(sample.replacingOccurrences(of: "\"estimated_minutes\":90", with: "\"estimated_minutes\":-2")) }
        try rejects("truncated JSON") { _ = try PlanCodec.parse(String(sample.dropLast(12))) }
        try check(try PlanCodec.parse("Here is your JSON\n```json\n" + sample + "\n```\n完成").goal.taskCount == 2, "prose and fence extraction")
        let markdown = sample.replacingOccurrences(of: "理解结构组成。", with: #"链接 https\://example\.com/path 与 \_文字\_"#)
        let repaired = try PlanCodec.parse(markdown)
        try check(repaired.goal.phases[0].tasks[0].notes.contains("https://example.com/path 与 _文字_") && repaired.warnings.contains(where: { $0.contains("修复") }), "Markdown escapes repaired with warning")
        try check(try PlanCodec.parse(sample.replacingOccurrences(of: "理解结构组成。", with: "第一行\n第二行")).goal.phases[0].tasks[0].notes.contains("第一行\n第二行"), "literal newline repair")
        try check(try PlanCodec.parse(sample.replacingOccurrences(of: "90,", with: "90,")).goal.taskCount == 2, "valid JSON unaffected")
        try check(try PlanCodec.parse(sample.replacingOccurrences(of: "\"phases\":[", with: "\"phases\":[").replacingOccurrences(of: "tasks\":[]}", with: "tasks\":[],}")).goal.taskCount == 2, "trailing comma repair")
        try rejects("multiple plans") { _ = try PlanCodec.parse(sample + "\n" + sample) }
        try rejects("array plan") { _ = try PlanCodec.parse("[" + sample + "]") }
        try check(try PlanCodec.parse("\u{FEFF}" + sample).goal.taskCount == 2, "BOM tolerated")
        let unknown = sample.replacingOccurrences(of: "\"schema_version\"", with: "\"future_optional\":true,\"schema_version\"")
        try check(try PlanCodec.parse(unknown).goal.taskCount == 2, "unknown optional field")
        var goal = parsed.goal
        goal.phases[0].tasks[0].notes += String(repeating: "\n说明", count: 5000)
        goal.phases[0].tasks[1].dependencies = [goal.phases[0].tasks[0].id]
        goal.phases[0].tasks[1].outcomes = [OutcomeRecord(text: "输出文件 /tmp/result.txt")]
        let roundtrip = try PlanCodec.parse(PlanCodec.export(goal)).goal
        try check(roundtrip.phases[0].tasks[0].notes == goal.phases[0].tasks[0].notes, "long notes roundtrip")
        try check(roundtrip.phases[0].tasks[1].dependencies == goal.phases[0].tasks[1].dependencies, "dependency roundtrip")
        try check(roundtrip.phases[0].tasks[1].outcomes.count == 1, "outcomes roundtrip")
        try check(try PlanCodec.export(goal).contains("\"due_date\" : null"), "nullable core keys")
        var duplicate = goal; duplicate.phases[0].tasks[1].id = duplicate.phases[0].tasks[0].id
        try rejects("duplicate task id") { _ = try PlanCodec.validate(duplicate) }
        var selfDependent = goal; selfDependent.phases[0].tasks[0].dependencies = [selfDependent.phases[0].tasks[0].id]
        try rejects("self dependency") { _ = try PlanCodec.validate(selfDependent) }
        var cycle = goal
        cycle.phases[0].tasks[0].dependencies = [cycle.phases[0].tasks[1].id]
        try rejects("dependency cycle") { _ = try PlanCodec.validate(cycle) }
        let blocks = MarkdownBlocks.parse(goal.phases[0].tasks[0].notes)
        try check(blocks.contains(where: { if case .code = $0.kind { return true }; return false }), "code blocks")
        let toggled = MarkdownBlocks.toggle("- [ ] first\n- [x] second", line: 0)
        try check(toggled == "- [x] first\n- [x] second", "checklist toggles line only")
        try check(PlanProgress(tasks: []).fraction == 0, "zero task progress")
    }
    @MainActor static func storageTests() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MintGoalTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = #"{"categories":["工作"],"tasks":[{"id":"11111111-1111-1111-1111-111111111111","title":"旧版任务","category":"工作","status":"todo","createdAt":1234567}]}"#
        let oldURL = folder.appendingPathComponent("tasks.json"); try Data(old.utf8).write(to: oldURL)
        let daily = TaskStore(folder: folder, watch: false)
        try check(daily.tasks.count == 1 && daily.tasks[0].goalTaskID == nil, "legacy daily load")
        let goals = GoalStore(daily: daily, folder: folder)
        daily.onChange = { [weak goals] in goals?.reconcileTodos() }
        let draft = try PlanCodec.parse(sample).goal
        try check(!FileManager.default.fileExists(atPath: goals.fileURL.path), "preview never persists")
        guard let id = goals.insert(draft) else { throw PlanFailure(goals.errorMessage ?? "insert") }
        try check(daily.tasks.count == 1 && daily.categories.contains(draft.title), "goal creates category without adding daily tasks")
        try check(goals.goals.count == 1, "whole plan inserted")
        try check(goals.insert(draft) == nil && goals.goals.count == 1, "duplicate blocked")
        try check(goals.insert(draft, allowDuplicate: true) != nil, "confirmed duplicate allowed")
        let allIDs = goals.goals.flatMap(\.phases).flatMap(\.tasks).map(\.id)
        try check(Set(allIDs).count == allIDs.count, "import rekeys IDs")
        let reloaded = GoalStore(daily: daily, folder: folder)
        try check(reloaded.goals.count == 2, "restart persistence")
        var edited = goals.goals.first { $0.id == id }!
        edited.term = .short; edited.state = .paused; edited.phases.swapAt(0, 1)
        try check(goals.save(edited), "manual edit/reorder")
        let taskID = goals.goals.first { $0.id == id }!.phases[1].tasks[0].id
        goals.attach(taskID); goals.attach(taskID)
        try check(daily.tasks.count == 2, "attach deduplication")
        let todoID = goals.task(taskID)!.linkedTodoID!
        _ = goals.updateTask(taskID) { $0.state = .completed }
        try check(daily.tasks.first { $0.id == todoID }?.status == .completed, "goal to daily state")
        try check(goals.task(taskID)?.completedAt != nil, "completion timestamp")
        daily.setStatus(daily.tasks.first { $0.id == todoID }!, .pending)
        try check(goals.task(taskID)?.state == .inProgress, "daily to goal state")
        var reminderUpdate = daily.tasks.first { $0.id == todoID }!; reminderUpdate.status = .completed
        daily.applyReminderChanges(updates: [reminderUpdate], deletedIDs: [])
        try check(goals.task(taskID)?.state == .completed, "EventKit update to goal state")
        try check(daily.tasks.first { $0.id == todoID }?.goalTaskID == taskID, "reminder metadata preserved")
        _ = goals.updateTask(taskID) { $0.state = .notStarted; $0.notes = "- [ ] 操作一步" }
        _ = goals.updateTask(taskID) { $0.notes = MarkdownBlocks.toggle($0.notes, line: 0) }
        try check(goals.task(taskID)?.state == .notStarted, "all checked steps do not complete task")
        let countBefore = daily.tasks.count
        _ = goals.updateTask(taskID) { $0.notes = MarkdownBlocks.toggle($0.notes, line: 3) }
        try check(daily.tasks.count == countBefore, "note steps never create Todo")
        daily.delete(daily.tasks.first { $0.id == todoID }!)
        try check(goals.task(taskID)?.linkedTodoID == nil && goals.task(taskID) != nil, "daily deletion clears link only")
        let dataBefore = try Data(contentsOf: goals.fileURL)
        var bad = goals.goals[0]; bad.title = ""
        try check(!goals.save(bad), "invalid goal rejected")
        try check(try Data(contentsOf: goals.fileURL) == dataBefore, "failed edit leaves disk intact")
        var progressTask = goals.goals[0].phases.flatMap(\.tasks)[0]
        progressTask.state = .completed
        var cancelled = progressTask; cancelled.id = UUID(); cancelled.state = .cancelled
        let progress = PlanProgress(tasks: [progressTask, cancelled])
        try check(progress.total == 1 && progress.fraction == 1, "cancelled denominator")
        try Data("damaged".utf8).write(to: goals.fileURL)
        let damaged = GoalStore(daily: daily, folder: folder)
        try check(damaged.recoveryRequired && damaged.insert(draft) == nil, "corruption blocks writes")
        damaged.restoreBackup()
        try check(!damaged.recoveryRequired && !damaged.goals.isEmpty, "backup recovery")
        try check(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains(where: { $0.hasPrefix("goals.damaged.") }), "damaged original preserved")
        let rollbackFolder = folder.appendingPathComponent("rollback")
        let rollback = TaskStore(folder: rollbackFolder, watch: false)
        let beforeRollback = rollback.tasks
        let beforeCategories = rollback.categories
        // A directory at the JSON path makes the actual atomic save fail deterministically.
        try FileManager.default.removeItem(at: rollback.fileURL)
        try FileManager.default.createDirectory(at: rollback.fileURL, withIntermediateDirectories: true)
        let remote = Todo(title: "remote update", category: "测试", status: .todo)
        try check(!rollback.applyReminderChanges(updates: [remote], deletedIDs: []), "reminder disk failure reported")
        try check(rollback.tasks == beforeRollback && rollback.categories == beforeCategories, "reminder disk failure rolls back memory")
        // Real EventKit is deliberately disabled in these tests.
        let reminders = RemindersSync(tasks: daily, allowSystemAccess: false, preferences: UserDefaults(suiteName: "com.minttodo.unit.\(UUID())")!)
        try check(!reminders.enabled && !reminders.hasAccess, "isolated reminder test mode")
    }
    @MainActor static func revisionTests() throws {
        var original = try PlanCodec.parse(sample).goal
        let dailyID = UUID()
        original.phases[0].tasks[0].state = .completed
        original.phases[0].tasks[0].completedAt = Date(timeIntervalSince1970: 100)
        original.phases[0].tasks[0].linkedTodoID = dailyID
        original.phases[0].tasks[0].outcomes = [OutcomeRecord(text: "已完成成果")]
        var proposal = try PlanCodec.parse(PlanCodec.export(original)).goal
        let oldTaskID = original.phases[0].tasks[0].id
        proposal.title = "调整后的计划"
        proposal.phases[0].tasks[0].title = "更明确的任务标题"
        proposal.phases[0].tasks[0].state = .notStarted
        proposal.phases[0].tasks[1].dependencies = [oldTaskID]
        var added = proposal.phases[0].tasks[0]
        added.id = UUID(); added.title = "新增步骤"; added.state = .completed
        proposal.phases[0].tasks.append(added)
        let revised = try PlanRevision.prepare(original: original, proposal: proposal)
        try check(revised.goal.id == original.id && revised.goal.title == proposal.title, "revision updates existing plan identity")
        let retained = revised.goal.phases[0].tasks[0]
        try check(retained.id == oldTaskID && retained.linkedTodoID == dailyID, "revision preserves stable daily association")
        try check(retained.state == .completed && retained.completedAt == original.phases[0].tasks[0].completedAt, "revision preserves completed state")
        try check(retained.outcomes == original.phases[0].tasks[0].outcomes, "revision preserves outcomes")
        try check(revised.added == 1 && revised.removed.isEmpty, "revision change counts")
        try check(revised.goal.phases[0].tasks[1].dependencies == [oldTaskID], "revision remaps dependencies")
        try check(revised.goal.phases[0].tasks[2].state == .notStarted && revised.goal.phases[0].tasks[2].linkedTodoID == nil, "AI cannot invent new completed or linked tasks")
        var removed = proposal; removed.phases[0].tasks.removeFirst(); removed.phases[0].tasks[0].dependencies = []
        try check(try PlanRevision.prepare(original: original, proposal: removed).removed == [original.phases[0].tasks[0].title], "revision lists removed tasks explicitly")
        let fallback = try PlanRevision.prepare(original: original, proposal: PlanCodec.parse(sample).goal)
        try check(fallback.goal.phases[0].tasks[0].id == oldTaskID, "unique title fallback when AI omits IDs")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MintRevision-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let daily = TaskStore(folder: folder, watch: false)
        let store = GoalStore(daily: daily, folder: folder)
        _ = store.insert(original)
        let snapshot = store.goals[0]
        var changed = snapshot; changed.notes = "其他窗口已修改"
        try check(store.save(changed), "concurrent update fixture")
        let before = try Data(contentsOf: store.fileURL)
        try check(!store.save(snapshot, expected: snapshot), "stale AI preview rejected")
        try check(try Data(contentsOf: store.fileURL) == before, "stale preview never overwrites recent progress")
    }
    static func resizeTests() throws {
        let frame = NSRect(x: 100, y: 100, width: 405, height: 560)
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let minimum = NSSize(width: 320, height: 380)
        let right = WindowResizeGeometry.resize(frame, delta: NSPoint(x: 80, y: 0), edges: .right, minimum: minimum, screen: screen)
        try check(right.width == 485 && right.minX == frame.minX, "right edge anchors left")
        let left = WindowResizeGeometry.resize(frame, delta: NSPoint(x: 500, y: 0), edges: .left, minimum: minimum, screen: screen)
        try check(left.width == 320 && left.maxX == frame.maxX, "left edge minimum and right anchor")
        let bottom = WindowResizeGeometry.resize(frame, delta: NSPoint(x: 0, y: 500), edges: .bottom, minimum: minimum, screen: screen)
        try check(bottom.height == 380 && bottom.maxY == frame.maxY, "bottom minimum and top anchor")
        let corner = WindowResizeGeometry.resize(frame, delta: NSPoint(x: -40, y: 50), edges: [.left, .top], minimum: minimum, screen: screen)
        try check(corner.width == 445 && corner.height == 610 && corner.maxX == frame.maxX && corner.minY == frame.minY, "corner resize anchors opposite edges")
        let cap = WindowResizeGeometry.resize(frame, delta: NSPoint(x: 5000, y: 5000), edges: [.right, .top], minimum: minimum, screen: screen)
        try check(cap.width == 900 && cap.maxY <= screen.maxY, "resize respects screen and size cap")
    }
    static func apiReply(_ content: String, reason: String = "stop") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": reason, "message": ["content": content]]]])
    }
    static func apiTests() async throws {
        try check(try AIConfiguration.endpoint("https://example.com").path == "/v1/chat/completions", "root path")
        try check(try AIConfiguration.endpoint("https://example.com/v1/").path == "/v1/chat/completions", "v1 path")
        try check(try AIConfiguration.endpoint("https://example.com/v1/chat/completions").path == "/v1/chat/completions", "full path no duplication")
        try rejects("insecure remote endpoint") { _ = try AIConfiguration.endpoint("http://example.com") }
        try rejects("credential URL") { _ = try AIConfiguration.endpoint("https://key@example.com/v1") }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockAPIProtocol.self]
        let client = AIClient(session: URLSession(configuration: config))
        let settings = AIConfiguration(baseURL: "https://example.test/v1", model: "test-model")
        do { _ = try await client.complete(config: settings, key: nil, system: "s", user: "u"); throw PlanFailure("TEST FAILED: missing key") }
        catch let error as PlanFailure { try check(error.message.contains("API Key"), "missing key error") }
        MockAPIProtocol.response = { request in
            guard request.url?.host == "example.test", request.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret" else { throw PlanFailure("request mismatch") }
            return (200, try apiReply(sample))
        }
        let plan = try await client.complete(config: settings, key: "test-secret", system: PlanPrompt.contract, user: "only supplied data")
        try check(try PlanCodec.parse(plan).goal.taskCount == 2, "compatible API to common parser")
        for status in [401, 404, 429, 500] {
            MockAPIProtocol.response = { _ in (status, Data("echo test-secret".utf8)) }
            do { _ = try await client.complete(config: settings, key: "test-secret", system: "s", user: "u"); throw PlanFailure("TEST FAILED: HTTP \(status)") }
            catch { try check(!error.localizedDescription.contains("test-secret") && !error.localizedDescription.hasPrefix("TEST FAILED"), "HTTP error redacts response/key") }
        }
        for response in [try apiReply("{", reason: "length"), Data("nonstandard".utf8), try apiReply("")] {
            MockAPIProtocol.response = { _ in (200, response) }
            do { _ = try await client.complete(config: settings, key: "test-secret", system: "s", user: "u"); throw PlanFailure("TEST FAILED: malformed response") }
            catch { try check(!error.localizedDescription.hasPrefix("TEST FAILED"), "invalid/empty/truncated response rejected") }
        }
        MockAPIProtocol.response = { _ in throw URLError(.timedOut) }
        do { _ = try await client.complete(config: settings, key: "test-secret", system: "s", user: "u"); throw PlanFailure("TEST FAILED: timeout") }
        catch { try check(error.localizedDescription.contains("超时"), "timeout retains recoverable error") }
        MockAPIProtocol.response = { _ in throw URLError(.cancelled) }
        do { _ = try await client.complete(config: settings, key: "test-secret", system: "s", user: "u"); throw PlanFailure("TEST FAILED: cancel") }
        catch is CancellationError { checks += 1 }
        for base in ["https://example.com", "https://example.com/v1/", "https://example.com/v1/chat/completions"] {
            try check(try AIConfiguration.modelsEndpoint(base).absoluteString == "https://example.com/v1/models", "models URL normalization")
        }
        try check(try AIConfiguration.modelsEndpoint("https://example.com/proxy/v1").path == "/proxy/v1/models", "models custom prefix")
        MockAPIProtocol.response = { request in
            guard request.httpMethod == "GET", request.url?.path == "/v1/models", request.httpBody == nil,
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret" else { throw PlanFailure("wrong models request") }
            return (200, Data(#"{"data":[{"id":"model-b"},{"id":"model-a"},{"id":"model-a"},{"id":" "}]}"#.utf8))
        }
        let models = try await client.models(baseURL: "https://example.test/v1", key: "test-secret")
        try check(models == ["model-a", "model-b"], "models GET authentication, sorting and deduplication")
        for reply in [#"{"data":[]}"#, #"{"data":[{"id":123}]}"#, "invalid"] {
            MockAPIProtocol.response = { _ in (200, Data(reply.utf8)) }
            do { _ = try await client.models(baseURL: "https://example.test", key: "test-secret"); throw PlanFailure("TEST FAILED: invalid model list") }
            catch { try check(!error.localizedDescription.hasPrefix("TEST FAILED"), "empty/malformed model list rejected") }
        }
        MockAPIProtocol.response = { _ in (401, Data("test-secret".utf8)) }
        do { _ = try await client.models(baseURL: "https://example.test", key: "test-secret"); throw PlanFailure("TEST FAILED: models auth") }
        catch { try check(!error.localizedDescription.contains("test-secret") && !error.localizedDescription.hasPrefix("TEST FAILED"), "models auth error redacted") }
        let keychain = AIKeychain(service: "com.minttodo.tests.\(UUID())")
        defer { try? keychain.clear() }
        try keychain.save("temporary-test-secret")
        try check(try keychain.read() == "temporary-test-secret", "Keychain read/write")
        try keychain.save("replacement-test-secret")
        try check(try keychain.read() == "replacement-test-secret", "Keychain update")
        try keychain.clear(); try check(try keychain.read() == nil, "Keychain deletion")
    }
}
