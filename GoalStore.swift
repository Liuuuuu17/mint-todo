import Foundation
import SwiftUI

private struct GoalFile: Codable {
    var version = 1
    var goals: [Goal]
}
@MainActor final class GoalStore: ObservableObject {
    @Published private(set) var goals: [Goal] = []
    @Published var errorMessage: String?
    @Published private(set) var recoveryRequired = false
    let fileURL: URL
    let backupURL: URL
    let daily: TaskStore
    private var reconciling = false

    init(daily: TaskStore, folder: URL? = nil) {
        self.daily = daily
        let folder = folder ?? daily.fileURL.deletingLastPathComponent()
        fileURL = folder.appendingPathComponent("goals.json")
        backupURL = folder.appendingPathComponent("goals.backup.json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do { goals = try Self.read(fileURL) }
            catch { recoveryRequired = true; errorMessage = "目标文件无法读取，原文件已保留。请先恢复备份；日常待办不受影响。" }
        }
    }
    private static func read(_ url: URL) throws -> [Goal] {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let saved = try decoder.decode(GoalFile.self, from: Data(contentsOf: url))
        guard saved.version == 1 else { throw PlanFailure("不支持的目标存储版本。") }
        for goal in saved.goals { _ = try PlanCodec.validate(goal) }
        return saved.goals
    }
    @discardableResult private func persist(_ candidate: [Goal]) -> Bool {
        guard !recoveryRequired else { errorMessage = "请先恢复备份，避免覆盖无法读取的目标文件。"; return false }
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(GoalFile(goals: candidate))
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try Self.read(fileURL)
                try Data(contentsOf: fileURL).write(to: backupURL, options: .atomic)
            }
            try data.write(to: fileURL, options: .atomic)
            goals = candidate
            return true
        } catch { errorMessage = "目标未保存：\(error.localizedDescription)"; return false }
    }
    func restoreBackup() {
        do {
            let restored = try Self.read(backupURL)
            // Keep the unreadable original for manual recovery.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let copy = fileURL.deletingLastPathComponent().appendingPathComponent("goals.damaged.\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: fileURL, to: copy)
            }
            try Data(contentsOf: backupURL).write(to: fileURL, options: .atomic)
            goals = restored; recoveryRequired = false; errorMessage = nil
            reconcileTodos()
        } catch { errorMessage = "备份无法恢复：\(error.localizedDescription)" }
    }
    func duplicate(of goal: Goal) -> Goal? {
        goals.first { PlanCodec.fingerprint($0) == PlanCodec.fingerprint(goal)
            || $0.title.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(goal.title.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }
    }
    @discardableResult func insert(_ source: Goal, allowDuplicate: Bool = false) -> UUID? {
        if !allowDuplicate && duplicate(of: source) != nil { errorMessage = "已有同名或相同内容的目标，请在预览中确认是否另存一份。"; return nil }
        do { _ = try PlanCodec.validate(source) }
        catch { errorMessage = error.localizedDescription; return nil }
        var goal = source; goal.id = UUID(); goal.createdAt = Date(); goal.updatedAt = Date()
        let ids = Dictionary(uniqueKeysWithValues: goal.phases.flatMap(\.tasks).map { ($0.id, UUID()) })
        for p in goal.phases.indices {
            goal.phases[p].id = UUID()
            for t in goal.phases[p].tasks.indices {
                var task = goal.phases[p].tasks[t]
                task.id = ids[task.id]!; task.goalID = goal.id; task.phaseID = goal.phases[p].id
                task.dependencies = task.dependencies.compactMap { ids[$0] }; task.linkedTodoID = nil
                goal.phases[p].tasks[t] = task
            }
        }
        do { _ = try PlanCodec.validate(goal) }
        catch { errorMessage = error.localizedDescription; return nil }
        guard persist(goals + [goal]) else { return nil }
        daily.groupGoalTasks(Set(goal.phases.flatMap(\.tasks).map(\.id)), category: goal.title)
        return goal.id
    }
    @discardableResult func save(_ source: Goal, expected: Goal? = nil) -> Bool {
        guard let index = goals.firstIndex(where: { $0.id == source.id }) else { errorMessage = "目标已被删除。"; return false }
        if let expected, goals[index] != expected {
            errorMessage = "计划在预览期间发生了变化，请关闭预览并重新生成，避免覆盖最新进度。"
            return false
        }
        var goal = source; goal.updatedAt = Date()
        for p in goal.phases.indices {
            for t in goal.phases[p].tasks.indices {
                goal.phases[p].tasks[t].goalID = goal.id; goal.phases[p].tasks[t].phaseID = goal.phases[p].id
            }
        }
        do { _ = try PlanCodec.validate(goal) }
        catch { errorMessage = error.localizedDescription; return false }
        let oldTasks = goals[index].phases.flatMap(\.tasks)
        var candidate = goals; candidate[index] = goal
        guard persist(candidate) else { return false }
        daily.groupGoalTasks(Set(goal.phases.flatMap(\.tasks).map(\.id)), category: goal.title)
        for old in oldTasks where !goal.phases.flatMap(\.tasks).contains(where: { $0.id == old.id }) { daily.unlinkGoalTask(old.id) }
        for task in goal.phases.flatMap(\.tasks) {
            if let id = task.linkedTodoID, let state = task.state.todoStatus,
               let todo = daily.tasks.first(where: { $0.id == id }), todo.status != state { daily.setStatus(todo, state) }
        }
        return true
    }
    func delete(_ goal: Goal) {
        if persist(goals.filter { $0.id != goal.id }) {
            for task in goal.phases.flatMap(\.tasks) { daily.unlinkGoalTask(task.id) }
        }
    }
    func task(_ id: UUID) -> GoalTask? { goals.flatMap(\.phases).flatMap(\.tasks).first { $0.id == id } }
    @discardableResult func updateTask(_ id: UUID, _ edit: (inout GoalTask) -> Void) -> Bool {
        for var goal in goals {
            for p in goal.phases.indices {
                if let t = goal.phases[p].tasks.firstIndex(where: { $0.id == id }) {
                    let before = goal.phases[p].tasks[t].state
                    edit(&goal.phases[p].tasks[t]); goal.phases[p].tasks[t].updatedAt = Date()
                    if goal.phases[p].tasks[t].state == .completed && before != .completed { goal.phases[p].tasks[t].completedAt = Date() }
                    else if goal.phases[p].tasks[t].state != .completed { goal.phases[p].tasks[t].completedAt = nil }
                    return save(goal)
                }
            }
        }
        return false
    }
    func attach(_ id: UUID, existing: UUID? = nil, today: Bool = false) {
        guard let task = task(id) else { return }
        guard let todoID = daily.ensureGoalTodo(task, existing: existing, today: today, category: goals.first(where: { $0.id == task.goalID })?.title ?? "目标任务") else { errorMessage = "待办未保存，目标关联没有变更。"; return }
        _ = updateTask(id) { task in
            task.linkedTodoID = todoID
            if let todo = daily.tasks.first(where: { $0.id == todoID }) { task.state = PlanState(todo: todo.status) }
        }
        reconcileTodos()
    }
    func reconcileTodos() {
        guard !reconciling, !recoveryRequired else { return }
        reconciling = true; defer { reconciling = false }
        var candidate = goals
        for g in candidate.indices {
            for p in candidate[g].phases.indices {
                for t in candidate[g].phases[p].tasks.indices {
                    var task = candidate[g].phases[p].tasks[t]
                    let todo = daily.tasks.first { $0.id == task.linkedTodoID || $0.goalTaskID == task.id }
                    if let todo {
                        task.linkedTodoID = todo.id
                        let state = PlanState(todo: todo.status)
                        // Pausing/archiving a goal task doesn't invent a new daily Todo state.
                        if task.state != .paused && task.state != .archived || todo.status == .completed {
                            if state == .completed && task.state != .completed { task.completedAt = Date() }
                            if state != .completed { task.completedAt = nil }
                            task.state = state
                        }
                    } else { task.linkedTodoID = nil }
                    if task != candidate[g].phases[p].tasks[t] { task.updatedAt = Date(); candidate[g].phases[p].tasks[t] = task; candidate[g].updatedAt = Date() }
                }
            }
        }
        if candidate != goals { _ = persist(candidate) }
    }
}
