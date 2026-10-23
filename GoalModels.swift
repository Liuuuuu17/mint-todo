import Foundation

// Planning data stays separate from daily Todo and EventKit records.
enum PlanState: String, Codable, CaseIterable, Identifiable {
    case notStarted = "not_started", inProgress = "in_progress", completed, paused, cancelled, archived
    var id: String { rawValue }
    var title: String {
        switch self {
        case .notStarted: return "未开始"
        case .inProgress: return "进行中"
        case .completed: return "已完成"
        case .paused: return "已暂停"
        case .cancelled: return "已取消"
        case .archived: return "已归档"
        }
    }
    var counted: Bool { self != .cancelled && self != .archived }
    var todoStatus: TaskStatus? {
        switch self {
        case .notStarted: return .todo
        case .inProgress: return .pending
        case .completed: return .completed
        case .cancelled: return .cancelled
        case .paused, .archived: return nil
        }
    }
    init(todo: TaskStatus) {
        switch todo {
        case .todo: self = .notStarted
        case .pending: self = .inProgress
        case .completed: self = .completed
        case .cancelled: self = .cancelled
        }
    }
}
enum GoalTerm: String, Codable, CaseIterable, Identifiable {
    case long, short
    var id: String { rawValue }
    var title: String { self == .long ? "长期" : "短期" }
}
enum DateOrigin: String, Codable, CaseIterable, Identifiable {
    case personal, suggested, confirmed
    var id: String { rawValue }
    var title: String { self == .confirmed ? "正式期限" : self == .suggested ? "建议排期" : "自行安排" }
}
struct OutcomeRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    var date = Date()
    var text: String
}
struct GoalTask: Codable, Equatable, Identifiable {
    var id = UUID()
    var goalID: UUID
    var phaseID: UUID
    var title = "新任务"
    var summary = ""
    var startDate: String?
    var dueDate: String?
    var dateOrigin: DateOrigin = .personal
    var estimatedMinutes: Int?
    var priority: Int?
    var state: PlanState = .notStarted
    var notes = ""
    var completionCriteria = ""
    var expectedOutput = ""
    var references = ""
    var dependencies: [UUID] = []
    var linkedTodoID: UUID?
    var completedAt: Date?
    var outcomes: [OutcomeRecord] = []
    var createdAt = Date()
    var updatedAt = Date()
}
struct GoalPhase: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = "新阶段"
    var summary = ""
    var startDate: String?
    var dueDate: String?
    var dateOrigin: DateOrigin = .personal
    var state: PlanState = .notStarted
    var milestone = ""
    var milestoneDate: String?
    var tasks: [GoalTask] = []
    var progress: PlanProgress { PlanProgress(tasks: tasks) }
}
struct Goal: Codable, Equatable, Identifiable {
    var id = UUID()
    var title = "新目标"
    var summary = ""
    var term: GoalTerm = .long
    var startDate: String?
    var dueDate: String?
    var dateOrigin: DateOrigin = .personal
    var state: PlanState = .notStarted
    var tags = ""
    var color = "#71BDA3"
    var notes = ""
    var phases: [GoalPhase] = []
    var createdAt = Date()
    var updatedAt = Date()
    var taskCount: Int { phases.reduce(0) { $0 + $1.tasks.count } }
    var progress: PlanProgress { PlanProgress(tasks: phases.flatMap(\.tasks)) }
    var currentPhase: String? {
        phases.first(where: { $0.state == .inProgress })?.title
            ?? phases.first(where: { $0.state.counted && $0.progress.fraction < 1 })?.title
    }
}
struct PlanProgress {
    let completed: Int
    let total: Int
    init(tasks: [GoalTask]) {
        let counted = tasks.filter { $0.state.counted }
        completed = counted.filter { $0.state == .completed }.count
        total = counted.count
    }
    var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
    var label: String { "\(completed) / \(total) 项完成" }
}
struct PlanFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
enum PlanDate {
    static func parse(_ value: String?) -> Date? {
        guard let value, value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }
    static func localDeadline(_ value: String?) -> Date? {
        guard let value, parse(value) != nil else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 23, minute: 59))
    }
    static func range(_ start: String?, _ end: String?) -> String {
        if start == nil && end == nil { return "时间待定" }
        return "\(start ?? "未定") → \(end ?? "未定")"
    }
}
