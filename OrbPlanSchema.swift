import Foundation
import CryptoKit

// External interchange contract. Unknown optional keys are ignored by JSONDecoder.
struct OrbPlan: Codable {
    var schema_version = "orb-todo-plan-v1"
    var goal: PlanGoalDTO
    var phases: [PlanPhaseDTO]
}
struct PlanGoalDTO: Codable {
    var title: String
    var description: String
    var start_date: String?
    var due_date: String?
    var term: GoalTerm?
    var status: PlanState?
    var date_origin: DateOrigin?
    var tags: String?
    var color: String?
    var notes: String?
}
struct PlanPhaseDTO: Codable {
    var title: String
    var start_date: String?
    var due_date: String?
    var tasks: [PlanTaskDTO]
    var description: String?
    var status: PlanState?
    var date_origin: DateOrigin?
    var milestone: String?
    var milestone_date: String?
}
struct PlanTaskDTO: Codable {
    var title: String
    var due_date: String?
    var estimated_minutes: Int?
    var notes: String
    var id: UUID?
    var start_date: String?
    var description: String?
    var status: PlanState?
    var date_origin: DateOrigin?
    var priority: Int?
    var completion_criteria: String?
    var expected_output: String?
    var references: String?
    var dependencies: [UUID]?
    var completed_at: Date?
    var outcomes: [OutcomeRecord]?
}
struct ParsedPlan {
    var goal: Goal
    var warnings: [String]
}
enum PlanCodec {
    static func parse(_ text: String) throws -> ParsedPlan {
        guard text.utf8.count <= 10_000_000 else { throw PlanFailure("计划超过 10 MB，请分成较小的计划。") }
        var input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.hasPrefix("```") {
            var lines = input.components(separatedBy: .newlines)
            guard ["```", "```json", "```JSON"].contains(lines.first ?? ""), lines.last == "```" else {
                throw PlanFailure("代码块包装不完整。请只粘贴 JSON 或完整的 ```json 代码块。")
            }
            lines.removeFirst(); lines.removeLast(); input = lines.joined(separator: "\n")
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let dto: OrbPlan
        do { dto = try decoder.decode(OrbPlan.self, from: Data(input.utf8)) }
        catch let error as DecodingError {
            switch error {
            case .keyNotFound(let key, let context): throw PlanFailure("缺少字段：\(path(context.codingPath)).\(key.stringValue)")
            case .typeMismatch(_, let context), .valueNotFound(_, let context): throw PlanFailure("字段类型不正确：\(path(context.codingPath))")
            default: throw PlanFailure("JSON 无法解析。请检查逗号、引号、换行转义和对象是否完整。")
            }
        }
        guard dto.schema_version == "orb-todo-plan-v1" else { throw PlanFailure("不支持 schema_version：\(dto.schema_version)。需要 orb-todo-plan-v1。") }
        guard dto.phases.count <= 500, dto.phases.reduce(0, { $0 + $1.tasks.count }) <= 10_000 else { throw PlanFailure("计划过大：最多 500 个阶段、10,000 个任务。") }
        var goal = Goal(title: dto.goal.title, summary: dto.goal.description,
                        term: dto.goal.term ?? .long, startDate: dto.goal.start_date, dueDate: dto.goal.due_date,
                        dateOrigin: dto.goal.date_origin ?? .personal, state: dto.goal.status ?? .notStarted,
                        tags: dto.goal.tags ?? "", color: dto.goal.color ?? "#71BDA3", notes: dto.goal.notes ?? "")
        for item in dto.phases {
            var phase = GoalPhase(title: item.title, summary: item.description ?? "", startDate: item.start_date,
                                  dueDate: item.due_date, dateOrigin: item.date_origin ?? .personal,
                                  state: item.status ?? .notStarted, milestone: item.milestone ?? "", milestoneDate: item.milestone_date)
            phase.tasks = item.tasks.map { item in
                GoalTask(id: item.id ?? UUID(), goalID: goal.id, phaseID: phase.id,
                         title: item.title, summary: item.description ?? "", startDate: item.start_date, dueDate: item.due_date,
                         dateOrigin: item.date_origin ?? .personal, estimatedMinutes: item.estimated_minutes,
                         priority: item.priority, state: item.status ?? .notStarted, notes: item.notes,
                         completionCriteria: item.completion_criteria ?? "", expectedOutput: item.expected_output ?? "",
                         references: item.references ?? "", dependencies: item.dependencies ?? [],
                         completedAt: item.completed_at, outcomes: item.outcomes ?? [])
            }
            goal.phases.append(phase)
        }
        let warnings = try validate(goal)
        return ParsedPlan(goal: goal, warnings: warnings)
    }
    private static func path(_ keys: [CodingKey]) -> String { keys.map(\.stringValue).joined(separator: ".") }
    static func validate(_ goal: Goal) throws -> [String] {
        func title(_ value: String, _ at: String) throws {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PlanFailure("\(at)不能为空。") }
        }
        func dates(_ start: String?, _ due: String?, _ at: String) throws {
            for date in [start, due].compactMap({ $0 }) where PlanDate.parse(date) == nil { throw PlanFailure("\(at)的日期 \(date) 无效，需使用 YYYY-MM-DD 或留空。") }
            if let start, let due, start > due { throw PlanFailure("\(at)的开始日期晚于截止日期。") }
        }
        try title(goal.title, "目标名称"); try dates(goal.startDate, goal.dueDate, "目标")
        var warnings: [String] = []
        if goal.phases.isEmpty { warnings.append("尚未添加阶段，可以在保存后继续补充。") }
        var ids = Set<UUID>()
        for (p, phase) in goal.phases.enumerated() {
            try title(phase.title, "阶段 \(p + 1) 名称"); try dates(phase.startDate, phase.dueDate, "阶段 \(p + 1)")
            try dates(nil, phase.milestoneDate, "里程碑")
            if phase.tasks.isEmpty { warnings.append("\(phase.title) 没有任务，不参与完成率分母。") }
            for (t, task) in phase.tasks.enumerated() {
                try title(task.title, "阶段 \(p + 1) 的任务 \(t + 1)")
                try dates(task.startDate, task.dueDate, "任务「\(task.title)」")
                guard ids.insert(task.id).inserted else { throw PlanFailure("任务 ID 重复，请为每个任务使用不同的 id，或省略 id。") }
                if let minutes = task.estimatedMinutes, minutes < 0 { throw PlanFailure("预计分钟数不能为负数：\(task.title)") }
                if let priority = task.priority, !(1...3).contains(priority) { throw PlanFailure("优先级必须为 1、2、3 或留空：\(task.title)") }
                guard task.notes.utf8.count <= 500_000 else { throw PlanFailure("任务说明超过 500 KB：\(task.title)") }
                if task.notes.isEmpty { warnings.append("\(task.title) 尚无执行说明。") }
            }
        }
        for task in goal.phases.flatMap(\.tasks) {
            if task.dependencies.contains(task.id) { throw PlanFailure("任务不能依赖自身：\(task.title)") }
            if task.dependencies.contains(where: { !ids.contains($0) }) { throw PlanFailure("任务「\(task.title)」引用了计划中不存在的依赖 ID。") }
        }
        let tasks = Dictionary(uniqueKeysWithValues: goal.phases.flatMap(\.tasks).map { ($0.id, $0) })
        var visiting: Set<UUID> = []; var visited: Set<UUID> = []
        func visit(_ id: UUID) throws {
            if visiting.contains(id) { throw PlanFailure("任务依赖形成循环，请调整依赖关系。") }
            if visited.contains(id) { return }
            visiting.insert(id)
            for dependency in tasks[id]?.dependencies ?? [] { try visit(dependency) }
            visiting.remove(id); visited.insert(id)
        }
        for id in tasks.keys { try visit(id) }
        return warnings
    }
    static func external(_ goal: Goal) -> OrbPlan {
        OrbPlan(goal: PlanGoalDTO(title: goal.title, description: goal.summary, start_date: goal.startDate, due_date: goal.dueDate,
                                 term: goal.term, status: goal.state, date_origin: goal.dateOrigin, tags: goal.tags, color: goal.color, notes: goal.notes),
                phases: goal.phases.map { phase in
            PlanPhaseDTO(title: phase.title, start_date: phase.startDate, due_date: phase.dueDate,
                         tasks: phase.tasks.map { task in
                PlanTaskDTO(title: task.title, due_date: task.dueDate, estimated_minutes: task.estimatedMinutes, notes: task.notes,
                            id: task.id, start_date: task.startDate, description: task.summary, status: task.state,
                            date_origin: task.dateOrigin, priority: task.priority, completion_criteria: task.completionCriteria,
                            expected_output: task.expectedOutput, references: task.references, dependencies: task.dependencies,
                            completed_at: task.completedAt, outcomes: task.outcomes)
            }, description: phase.summary, status: phase.state, date_origin: phase.dateOrigin,
                         milestone: phase.milestone, milestone_date: phase.milestoneDate)
        })
    }
    static func export(_ goal: Goal) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        // Encode nullable core fields explicitly for predictable AI interchange.
        let data = try encoder.encode(external(goal))
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var header = object["goal"] as! [String: Any]
        for key in ["start_date", "due_date"] where header[key] == nil { header[key] = NSNull() }
        object["goal"] = header
        var phases = object["phases"] as! [[String: Any]]
        for p in phases.indices {
            for key in ["start_date", "due_date"] where phases[p][key] == nil { phases[p][key] = NSNull() }
            var tasks = phases[p]["tasks"] as! [[String: Any]]
            for t in tasks.indices {
                for key in ["due_date", "estimated_minutes"] where tasks[t][key] == nil { tasks[t][key] = NSNull() }
            }
            phases[p]["tasks"] = tasks
        }
        object["phases"] = phases
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }
    static func fingerprint(_ goal: Goal) -> String {
        let normalized = ([goal.title, goal.summary] + goal.phases.flatMap { [$0.title] + $0.tasks.map { $0.title + "\n" + $0.notes } }).joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
