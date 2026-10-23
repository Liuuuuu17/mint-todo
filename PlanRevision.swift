import SwiftUI

struct PlanRevision {
    var goal: Goal
    var added: Int
    var removed: [String]

    static func prepare(original: Goal, proposal: Goal) throws -> PlanRevision {
        _ = try PlanCodec.validate(proposal)
        let oldTasks = original.phases.flatMap(\.tasks)
        let oldByID = Dictionary(uniqueKeysWithValues: oldTasks.map { ($0.id, $0) })
        var used = Set<UUID>()
        var ids: [UUID: UUID] = [:]
        var matched: [UUID: GoalTask] = [:]
        // Retain stable execution metadata; never trust an AI's claimed completion status.
        for task in proposal.phases.flatMap(\.tasks) {
            let byTitle = oldTasks.filter { $0.title == task.title && !used.contains($0.id) }
            let old = oldByID[task.id] ?? (byTitle.count == 1 ? byTitle.first : nil)
            if let old, !used.contains(old.id) {
                used.insert(old.id); ids[task.id] = old.id; matched[task.id] = old
            } else { ids[task.id] = UUID() }
        }
        var result = proposal
        result.id = original.id
        result.createdAt = original.createdAt
        result.updatedAt = original.updatedAt
        result.state = original.state
        result.term = original.term
        result.tags = original.tags
        result.color = original.color
        result.dateOrigin = result.startDate == original.startDate && result.dueDate == original.dueDate ? original.dateOrigin : .suggested
        for p in result.phases.indices {
            result.phases[p].id = UUID()
            for t in result.phases[p].tasks.indices {
                let proposedID = result.phases[p].tasks[t].id
                var task = result.phases[p].tasks[t]
                task.id = ids[proposedID]!
                task.goalID = original.id; task.phaseID = result.phases[p].id
                task.dependencies = task.dependencies.compactMap { ids[$0] }
                if let old = matched[proposedID] {
                    task.state = old.state; task.completedAt = old.completedAt
                    task.outcomes = old.outcomes; task.linkedTodoID = old.linkedTodoID
                    task.createdAt = old.createdAt
                    task.dateOrigin = task.startDate == old.startDate && task.dueDate == old.dueDate ? old.dateOrigin : .suggested
                } else {
                    task.state = .notStarted; task.completedAt = nil; task.outcomes = []; task.linkedTodoID = nil
                    task.dateOrigin = .suggested
                }
                result.phases[p].tasks[t] = task
            }
        }
        _ = try PlanCodec.validate(result)
        return PlanRevision(goal: result, added: result.taskCount - used.count,
                            removed: oldTasks.filter { !used.contains($0.id) }.map(\.title))
    }
}

struct PlanRevisionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: GoalStore
    let original: Goal
    @State private var instruction = ""
    @State private var operation: Task<Void, Never>?
    @State private var result: PlanRevision?
    @State private var status = ""
    @State private var preview = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("AI 修改长期计划").font(.title2.bold()); Spacer(); Button("关闭") { dismiss() } }
            Text(original.title).font(.headline)
            Text("告诉 AI 你想增删哪些任务、调整阶段、修改时间，或怎样改写执行说明。")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $instruction).frame(height: 120).border(.secondary.opacity(0.2)).disabled(operation != nil)
            Text("点击生成会把当前整份计划及本次要求发送到你配置的 AI 服务。结果先预览；保存后才替换原计划。已有任务的完成状态、成果记录和待办关联会保留。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("生成修改预览") { generate() }.disabled(operation != nil || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if operation != nil { ProgressView().controlSize(.small); Button("取消生成") { operation?.cancel() } }
            }
            Text(status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            if let result {
                Text("修改后：\(result.goal.phases.count) 个阶段，\(result.goal.taskCount) 项任务；新增 \(result.added) 项，移除 \(result.removed.count) 项。")
                if !result.removed.isEmpty {
                    ScrollView { Text("将移除：\n" + result.removed.joined(separator: "\n")).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 90)
                    Text("移除的目标任务会解除关联，已加入的日常待办仍保留。若不符合预期，请取消或在下一步调整。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("检查并编辑修改结果…") { preview = true }
            }
            Spacer(minLength: 0)
        }.padding(24).frame(width: 680, height: 570)
        .sheet(isPresented: $preview) {
            if let result {
                GoalEditorView(initial: result.goal, heading: "AI 修改预览 · 保存后替换原计划", store: store, isNew: false,
                               expectedOriginal: original, onSaved: { dismiss() })
            }
        }
        .onDisappear { operation?.cancel() }
    }
    private func generate() {
        result = nil; status = "正在生成修改…"
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                let current = try PlanCodec.export(original)
                let response = try await AIClient().complete(config: AISettings.configuration, key: AIKeychain().read(),
                    system: PlanPrompt.contract + "\n你正在修改现有计划。仅按用户要求调整，保留未要求修改的内容及已有任务 id，不虚构完成状态或成果。返回完整计划 JSON，不是补丁。",
                    user: "本次修改要求：\(instruction)\n当前完整计划：\n\(current)")
                result = try PlanRevision.prepare(original: original, proposal: PlanCodec.parse(response).goal)
                status = "修改结果已准备好，请检查阶段、任务和日期后再决定保存。"
            } catch is CancellationError { status = "已取消，原计划未改变。" }
            catch { status = error.localizedDescription }
        }
    }
}
