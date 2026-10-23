import AppKit
import SwiftUI
import UniformTypeIdentifiers

func optionalText(_ value: Binding<String?>) -> Binding<String> {
    Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
}
struct PlanDateFields: View {
    @Binding var start: String?
    @Binding var due: String?
    @Binding var origin: DateOrigin
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { TextField("开始 YYYY-MM-DD（可空）", text: optionalText($start)); TextField("截止 YYYY-MM-DD（可空）", text: optionalText($due)) }
            Picker("日期性质", selection: $origin) { ForEach(DateOrigin.allCases) { Text($0.title).tag($0) } }.font(.caption)
        }
    }
}
struct StatePicker: View {
    @Binding var state: PlanState
    var body: some View { Picker("状态", selection: $state) { ForEach(PlanState.allCases) { Text($0.title).tag($0) } } }
}
struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: GoalStore
    @State private var draft: Goal
    let heading: String
    let isNew: Bool
    let expectedOriginal: Goal?
    var onSaved: () -> Void
    @State private var taskEditor: GoalTask?
    @State private var issue = ""
    @State private var duplicateConfirmation = false
    init(initial: Goal, heading: String, store: GoalStore, isNew: Bool, expectedOriginal: Goal? = nil, onSaved: @escaping () -> Void = {}) {
        _draft = State(initialValue: initial); self.heading = heading; self.store = store; self.isNew = isNew; self.expectedOriginal = expectedOriginal; self.onSaved = onSaved
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(heading).font(.title2.bold()); Spacer()
                Button("取消") { dismiss() }
                Button(isNew ? "确认导入 / 创建" : "保存修改") { submit() }.keyboardShortcut(.defaultAction)
            }
            Text("\(draft.phases.count) 个阶段 · \(draft.taskCount) 项任务 · 确认前的编辑不会写入数据库")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("目标名称", text: $draft.title).font(.title3)
                    HStack {
                        Picker("类型", selection: $draft.term) { ForEach(GoalTerm.allCases) { Text($0.title).tag($0) } }
                        StatePicker(state: $draft.state)
                    }
                    TextField("目标描述", text: $draft.summary, axis: .vertical).lineLimit(2...5)
                    PlanDateFields(start: $draft.startDate, due: $draft.dueDate, origin: $draft.dateOrigin)
                    HStack { TextField("标签（可空）", text: $draft.tags); TextField("颜色 #RRGGBB", text: $draft.color) }
                    TextField("补充备注", text: $draft.notes, axis: .vertical).lineLimit(2...5)
                    Divider()
                    ForEach(Array(draft.phases.enumerated()), id: \.element.id) { index, phase in
                        PhaseDraftCard(phase: $draft.phases[index], onTask: { taskEditor = $0 }, onAddTask: {
                            let task = GoalTask(goalID: draft.id, phaseID: phase.id)
                            draft.phases[index].tasks.append(task); taskEditor = task
                        }, onMove: { direction in
                            let target = index + direction
                            if draft.phases.indices.contains(target) { draft.phases.swapAt(index, target) }
                        }, onDelete: { draft.phases.removeAll { $0.id == phase.id } })
                    }
                    Button("添加阶段", systemImage: "plus.circle") { draft.phases.append(GoalPhase()) }
                    if let warnings = try? PlanCodec.validate(draft), !warnings.isEmpty {
                        Text(warnings.prefix(20).joined(separator: "\n")).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.trailing, 8)
            }
            if !issue.isEmpty { Text(issue).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
        }.padding(24).frame(width: 780, height: 700)
        .sheet(item: $taskEditor) { task in
            GoalTaskEditor(initial: task) { edited in
                for p in draft.phases.indices {
                    if let t = draft.phases[p].tasks.firstIndex(where: { $0.id == edited.id }) { draft.phases[p].tasks[t] = edited }
                }
            }
        }
        .alert("已有同名或相同内容的目标", isPresented: $duplicateConfirmation) {
            Button("取消", role: .cancel) {}
            Button("仍作为新目标导入") { save(allowDuplicate: true) }
        } message: { Text("此次操作会保留原目标，另存一个可独立编辑的新目标。") }
    }
    private func submit() {
        do { _ = try PlanCodec.validate(draft) }
        catch { issue = error.localizedDescription; return }
        if isNew && store.duplicate(of: draft) != nil { duplicateConfirmation = true }
        else { save(allowDuplicate: false) }
    }
    private func save(allowDuplicate: Bool) {
        let success = isNew ? store.insert(draft, allowDuplicate: allowDuplicate) != nil : store.save(draft, expected: expectedOriginal)
        if success { onSaved(); dismiss() } else { issue = store.errorMessage ?? "保存失败。" }
    }
}
private struct PhaseDraftCard: View {
    @Binding var phase: GoalPhase
    let onTask: (GoalTask) -> Void
    let onAddTask: () -> Void
    let onMove: (Int) -> Void
    let onDelete: () -> Void
    @State private var deleteConfirmation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("阶段名称", text: $phase.title).font(.headline)
                Button { onMove(-1) } label: { Image(systemName: "arrow.up") }.help("上移阶段")
                Button { onMove(1) } label: { Image(systemName: "arrow.down") }.help("下移阶段")
                Button(role: .destructive) { deleteConfirmation = true } label: { Image(systemName: "trash") }
            }
            TextField("阶段描述", text: $phase.summary, axis: .vertical).lineLimit(1...4)
            PlanDateFields(start: $phase.startDate, due: $phase.dueDate, origin: $phase.dateOrigin)
            StatePicker(state: $phase.state)
            HStack { TextField("里程碑名称（可空）", text: $phase.milestone); TextField("里程碑日期（可空）", text: optionalText($phase.milestoneDate)) }
            ForEach(Array(phase.tasks.enumerated()), id: \.element.id) { index, task in
                HStack {
                    Button { onTask(task) } label: { VStack(alignment: .leading) { Text(task.title); Text("\(task.state.title) · \(task.notes.isEmpty ? "待补充执行说明" : "含执行说明")").font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain)
                    Spacer()
                    Button { if index > 0 { phase.tasks.swapAt(index, index - 1) } } label: { Image(systemName: "arrow.up") }
                    Button { if index + 1 < phase.tasks.count { phase.tasks.swapAt(index, index + 1) } } label: { Image(systemName: "arrow.down") }
                    Button(role: .destructive) { phase.tasks.removeAll { $0.id == task.id } } label: { Image(systemName: "minus.circle") }
                }.padding(.vertical, 4)
            }
            Button("添加任务", action: onAddTask)
        }.padding(16).background(RoundedRectangle(cornerRadius: 14).fill(.primary.opacity(0.035)))
        .confirmationDialog("删除整个阶段及其目标任务？日常待办会保留并解除关联。", isPresented: $deleteConfirmation) {
            Button("删除阶段", role: .destructive, action: onDelete)
        }
    }
}
struct GoalTaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var task: GoalTask
    @State private var preview = false
    @State private var issue = ""
    let onSave: (GoalTask) -> Void
    init(initial: GoalTask, onSave: @escaping (GoalTask) -> Void) { _task = State(initialValue: initial); self.onSave = onSave }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("编辑目标任务").font(.title2.bold()); Spacer(); Button("取消") { dismiss() }; Button("保存") { save() }.keyboardShortcut(.defaultAction) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("任务标题", text: $task.title).font(.title3)
                    TextField("简短描述", text: $task.summary, axis: .vertical).lineLimit(2...5)
                    StatePicker(state: $task.state)
                    PlanDateFields(start: $task.startDate, due: $task.dueDate, origin: $task.dateOrigin)
                    HStack {
                        TextField("预计分钟（可空）", text: Binding(get: { task.estimatedMinutes.map(String.init) ?? "" }, set: { value in task.estimatedMinutes = value.isEmpty ? nil : Int(value) ?? -1 }))
                        Picker("优先级", selection: Binding(get: { task.priority ?? 0 }, set: { task.priority = $0 == 0 ? nil : $0 })) {
                            Text("未设置").tag(0); Text("高").tag(1); Text("中").tag(2); Text("低").tag(3)
                        }
                    }
                    HStack { Text("Markdown 执行说明").font(.headline); Spacer(); Toggle("阅读预览", isOn: $preview).toggleStyle(.switch) }
                    if preview { MarkdownNotes(text: task.notes, onToggle: { task.notes = MarkdownBlocks.toggle(task.notes, line: $0) }).padding(12) }
                    else { TextEditor(text: $task.notes).font(.system(size: 13, design: .monospaced)).frame(minHeight: 220).border(.secondary.opacity(0.2)) }
                    if task.notes.isEmpty { Button("插入执行指南模板") { task.notes = "## 任务目的\n\n## 操作步骤\n1. \n\n## 完成标准\n\n## 预期产出\n\n## 参考资料\n\n## 注意事项\n" } }
                    TextField("完成标准", text: $task.completionCriteria, axis: .vertical).lineLimit(2...5)
                    TextField("预期产出", text: $task.expectedOutput, axis: .vertical).lineLimit(2...5)
                    TextField("参考资料 / 链接", text: $task.references, axis: .vertical).lineLimit(2...5)
                }
            }
            Text(issue).foregroundStyle(.red).font(.caption)
        }.padding(24).frame(width: 730, height: 690)
    }
    private func save() {
        var phase = GoalPhase(id: task.phaseID); phase.tasks = [task]
        var test = Goal(id: task.goalID); test.phases = [phase]
        // Dependencies belong to the complete plan and are validated when that plan is saved.
        test.phases[0].tasks[0].dependencies = []
        do {
            _ = try PlanCodec.validate(test); task.updatedAt = Date()
            if task.state == .completed && task.completedAt == nil { task.completedAt = Date() }
            if task.state != .completed { task.completedAt = nil }
            onSave(task); dismiss()
        } catch { issue = error.localizedDescription }
    }
}
struct PlanImportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: GoalStore
    let parseImmediately: Bool
    @State private var initialized = false
    @State private var text: String
    init(store: GoalStore, initialText: String = "", parseImmediately: Bool = false) {
        self.store = store
        self.parseImmediately = parseImmediately
        _text = State(initialValue: initialText)
    }
    @State private var issue = ""
    @State private var preview: Goal?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("导入长期任务").font(.title2.bold()); Spacer(); Button("关闭") { dismiss() } }
            Text("把 AI 生成的完整计划 JSON 粘贴到下方，点“解析并预览”，编辑确认后存入长期任务。无需 API Key。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("复制 AI 提示词") { AISettings.copyPrompt() }
                Button("从剪贴板粘贴") { text = NSPasteboard.general.string(forType: .string) ?? "" }
                Button("选择 JSON 文件…") { chooseFile() }
            }
            TextEditor(text: $text).font(.system(size: 12, design: .monospaced)).border(.secondary.opacity(0.2))
            Text(issue).foregroundStyle(.red).font(.callout).textSelection(.enabled)
            HStack { Text("支持完整的 Markdown JSON 代码块包装。").font(.caption).foregroundStyle(.secondary); Spacer(); Button("解析并预览") { parse() }.disabled(text.isEmpty).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 740, height: 620)
        .task {
            guard !initialized else { return }
            initialized = true
            if parseImmediately {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issue = "剪贴板中没有文本，请粘贴 AI 返回的计划 JSON。" }
                else { parse() }
            }
        }
        .sheet(item: $preview) { goal in GoalEditorView(initial: goal, heading: "计划导入预览", store: store, isNew: true, onSaved: { dismiss() }) }
    }
    private func parse() { do { preview = try PlanCodec.parse(text).goal; issue = "" } catch { issue = error.localizedDescription } }
    private func chooseFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 10_000_000 else { throw PlanFailure("文件超过 10 MB，请拆分计划。") }
            text = try String(contentsOf: url, encoding: .utf8); issue = ""
        } catch { issue = error.localizedDescription }
    }
}
