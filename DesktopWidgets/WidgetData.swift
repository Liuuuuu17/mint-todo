import Foundation
import Darwin

enum MintWidgetSize { case small, medium, large }

struct MintWidgetSubtask: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var isCompleted: Bool
}

struct MintWidgetTask: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var category: String
    var status: String
    var dueAt: Date?
    var completedAt: Date?
    var goalTaskID: UUID?
    var subtasks: [MintWidgetSubtask]
    var isCompleted: Bool { status == "completed" }
}

struct MintWidgetPlanTask: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var state: String
    var linkedTodoID: UUID?
    var isCompleted: Bool { state == "completed" }
    var isCounted: Bool { !["cancelled", "archived"].contains(state) }
}

struct MintWidgetPhase: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var tasks: [MintWidgetPlanTask]
    var countedTasks: [MintWidgetPlanTask] { tasks.filter(\.isCounted) }
    var completed: Int { countedTasks.filter(\.isCompleted).count }
}

struct MintWidgetGoal: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var state: String
    var color: String
    var phases: [MintWidgetPhase]
    var tasks: [MintWidgetPlanTask] { phases.flatMap(\.countedTasks) }
    var completed: Int { tasks.filter(\.isCompleted).count }
    var fraction: Double { tasks.isEmpty ? 0 : Double(completed) / Double(tasks.count) }
    var currentPhase: MintWidgetPhase? { phases.first { $0.completed < $0.countedTasks.count } ?? phases.last }
}

struct MintWidgetTheme: Codable, Equatable {
    var background = "#F0F0FA"
    var accent = "#71BDA3"
    var paperStyle = false
    var fontName: String?
    var fontFile: String?
    var fontScale = 1.0
}

enum MintWidgetTarget: String, Codable { case daily, goal }

enum MintWidgetActionLink {
    static func url(target: MintWidgetTarget, taskID: UUID, completed: Bool) -> URL {
        var parts = URLComponents()
        parts.scheme = "minttodo-widgets-trial"; parts.host = "complete"
        parts.queryItems = [URLQueryItem(name: "target", value: target.rawValue),
                            URLQueryItem(name: "id", value: taskID.uuidString),
                            URLQueryItem(name: "completed", value: completed ? "1" : "0")]
        return parts.url!
    }
    static func command(from url: URL) -> MintWidgetCommand? {
        guard url.scheme == "minttodo-widgets-trial", url.host == "complete",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func value(_ name: String) -> String? {
            let matches = items.filter { $0.name == name }
            return matches.count == 1 ? matches[0].value : nil
        }
        guard let rawTarget = value("target"), let target = MintWidgetTarget(rawValue: rawTarget),
              let rawID = value("id"), let id = UUID(uuidString: rawID),
              let completed = value("completed"), ["0", "1"].contains(completed) else { return nil }
        return MintWidgetCommand(target: target, taskID: id, completed: completed == "1")
    }
}

/// Immutable commands keep widget writes separate from the app's task files.
/// An absolute desired state makes replay safe after a crash or restart.
struct MintWidgetCommand: Codable, Equatable, Identifiable {
    var id = UUID()
    var target: MintWidgetTarget
    var taskID: UUID
    var completed: Bool
    var createdAt = Date()
}

struct MintWidgetSnapshot: Codable, Equatable {
    var version = 1
    var generatedAt = Date()
    var tasks: [MintWidgetTask] = []
    var goals: [MintWidgetGoal] = []
    var theme = MintWidgetTheme()
    var isReady = false

    var activeGoals: [MintWidgetGoal] { goals.filter { !["completed", "cancelled", "archived"].contains($0.state) } }
    var goalTotal: Int { activeGoals.reduce(0) { $0 + $1.tasks.count } }
    var goalCompleted: Int { activeGoals.reduce(0) { $0 + $1.completed } }
    var goalFraction: Double { goalTotal == 0 ? 0 : Double(goalCompleted) / Double(goalTotal) }

    /// All actionable todos, including future dates; matches the app's pending list.
    var allPendingTasks: [MintWidgetTask] {
        tasks.filter { ["todo", "pending"].contains($0.status) }.sorted { lhs, rhs in
            if lhs.dueAt != rhs.dueAt { return (lhs.dueAt ?? .distantFuture) < (rhs.dueAt ?? .distantFuture) }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    func todayTasks(now: Date = Date(), calendar: Calendar = .current) -> [MintWidgetTask] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return tasks.filter { task in
            if task.isCompleted { return task.completedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
            guard ["todo", "pending"].contains(task.status) else { return false }
            return task.dueAt.map { $0 < tomorrow } ?? true
        }.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            if lhs.dueAt != rhs.dueAt { return (lhs.dueAt ?? .distantFuture) < (rhs.dueAt ?? .distantFuture) }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    func contains(_ command: MintWidgetCommand) -> Bool {
        switch command.target {
        case .daily: return tasks.contains { $0.id == command.taskID && $0.status != "cancelled" }
        case .goal: return goals.flatMap(\.tasks).contains { $0.id == command.taskID }
        }
    }

    func applying(_ commands: [MintWidgetCommand]) -> MintWidgetSnapshot {
        var result = self
        for command in commands {
            guard result.contains(command) else { continue }
            var dailyID: UUID? = command.target == .daily ? command.taskID : nil
            var goalID: UUID? = command.target == .goal ? command.taskID : nil
            if let dailyID { goalID = result.tasks.first { $0.id == dailyID }?.goalTaskID }
            if let goalID {
                for g in result.goals.indices {
                    for p in result.goals[g].phases.indices {
                        if let t = result.goals[g].phases[p].tasks.firstIndex(where: { $0.id == goalID }) {
                            dailyID = dailyID ?? result.goals[g].phases[p].tasks[t].linkedTodoID
                            result.goals[g].phases[p].tasks[t].state = command.completed ? "completed" : "not_started"
                        }
                    }
                }
            }
            if let dailyID, let i = result.tasks.firstIndex(where: { $0.id == dailyID }) {
                let wasCompleted = result.tasks[i].isCompleted
                result.tasks[i].status = command.completed ? "completed" : "todo"
                if !command.completed { result.tasks[i].completedAt = nil }
                else if !wasCompleted || result.tasks[i].completedAt == nil { result.tasks[i].completedAt = command.createdAt }
            }
        }
        return result
    }

    static func sample(now: Date = Date()) -> MintWidgetSnapshot {
        let first = UUID(), second = UUID(), daily = UUID()
        let phase = MintWidgetPhase(id: UUID(), title: "准备与整理", tasks: [
            MintWidgetPlanTask(id: first, title: "收集参考资料", state: "completed"),
            MintWidgetPlanTask(id: second, title: "整理第一版大纲", state: "not_started", linkedTodoID: daily)
        ])
        let next = MintWidgetPhase(id: UUID(), title: "完成初稿", tasks: [MintWidgetPlanTask(id: UUID(), title: "写出初稿", state: "not_started")])
        return MintWidgetSnapshot(generatedAt: now, tasks: [
            MintWidgetTask(id: daily, title: "整理第一版大纲", category: "完成个人作品", status: "todo", dueAt: now.addingTimeInterval(3600), goalTaskID: second, subtasks: []),
            MintWidgetTask(id: UUID(), title: "读完今天的章节", category: "学习", status: "todo", subtasks: []),
            MintWidgetTask(id: UUID(), title: "散步 20 分钟", category: "生活", status: "todo", subtasks: []),
            MintWidgetTask(id: UUID(), title: "整理工作台", category: "生活", status: "completed", completedAt: now, subtasks: [])
        ], goals: [
            MintWidgetGoal(id: UUID(), title: "完成个人作品", state: "in_progress", color: "#71BDA3", phases: [phase, next]),
            MintWidgetGoal(id: UUID(), title: "建立阅读习惯", state: "in_progress", color: "#8B9BC8", phases: [MintWidgetPhase(id: UUID(), title: "本周阅读", tasks: [
                MintWidgetPlanTask(id: UUID(), title: "选择一本书", state: "completed"),
                MintWidgetPlanTask(id: UUID(), title: "完成第一章", state: "not_started")
            ])])
        ], isReady: true)
    }
}

struct MintWidgetFiles {
    static let kind = "MintTodoTrialDashboard"
    static var defaultFolder: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/MintTodoWidgetTrial", isDirectory: true)
    }
    let folder: URL
    init(folder: URL = defaultFolder) { self.folder = folder }
    var snapshotURL: URL { folder.appendingPathComponent("widget-snapshot.json") }
    var commandsFolder: URL { folder.appendingPathComponent("WidgetActions", isDirectory: true) }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970; return decoder
    }
    func readSnapshot() throws -> MintWidgetSnapshot {
        let value = try Self.decoder.decode(MintWidgetSnapshot.self, from: Data(contentsOf: snapshotURL))
        guard value.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return value
    }
    func writeSnapshot(_ value: MintWidgetSnapshot) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.encoder.encode(value).write(to: snapshotURL, options: .atomic)
    }
    func enqueue(_ command: MintWidgetCommand) throws {
        try FileManager.default.createDirectory(at: commandsFolder, withIntermediateDirectories: true)
        try Self.encoder.encode(command).write(to: commandsFolder.appendingPathComponent(command.id.uuidString + ".json"), options: .atomic)
    }
    func commands() throws -> [MintWidgetCommand] {
        guard FileManager.default.fileExists(atPath: commandsFolder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: commandsFolder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decoder.decode(MintWidgetCommand.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
    }
    func acknowledge(_ command: MintWidgetCommand) throws {
        let url = commandsFolder.appendingPathComponent(command.id.uuidString + ".json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    func displayedSnapshot() throws -> MintWidgetSnapshot { try readSnapshot().applying(commands()) }
}
