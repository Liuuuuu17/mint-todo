import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GoalsView: View {
    @ObservedObject var store: GoalStore
    @State private var selection: UUID?
    @State private var filter = "active"
    @State private var search = ""
    @State private var importPlan = false
    @State private var generate = false
    @State private var settings = false
    @State private var manual: Goal?
    @State private var restore = false
    private var visible: [Goal] {
        store.goals.filter { goal in
            let matches = filter == "archive" ? goal.state == .archived : filter == "history" ? [.completed, .cancelled].contains(goal.state) : ![.completed, .cancelled, .archived].contains(goal.state)
            return matches && (search.isEmpty || goal.title.localizedCaseInsensitiveContains(search) || goal.tags.localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 12) {
                HStack { Text("我的目标").font(.title2.bold()); Spacer(); Menu { createActions } label: { Image(systemName: "plus") } }.padding(.top, 10)
                Picker("目标分类", selection: $filter) { Text("进行中").tag("active"); Text("历史").tag("history"); Text("归档").tag("archive") }.pickerStyle(.segmented)
                TextField("搜索目标或标签", text: $search).textFieldStyle(.roundedBorder)
                List(selection: $selection) {
                    ForEach(visible) { goal in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(goal.title).font(.headline).lineLimit(2)
                            Text("\(goal.term.title) · \(goal.state.title)").font(.caption).foregroundStyle(.secondary)
                            ProgressView(value: goal.progress.fraction).tint(.mint)
                            Text(goal.progress.label).font(.caption2).foregroundStyle(.secondary)
                            if let due = goal.dueDate { Text("截止 \(due)").font(.caption2).foregroundStyle(.secondary) }
                            if let phase = goal.currentPhase { Text("当前：\(phase)").font(.caption2).lineLimit(1).foregroundStyle(.secondary) }
                        }.padding(.vertical, 7).tag(goal.id)
                    }
                }.listStyle(.sidebar)
                HStack { Button("复制 AI 提示词") { AISettings.copyPrompt() }; Spacer(); Button { settings = true } label: { Image(systemName: "gearshape") }.help("AI 设置") }.font(.caption)
                if store.recoveryRequired { Button("恢复最近备份…") { restore = true }.foregroundStyle(.red) }
            }.padding(14).navigationSplitViewColumnWidth(min: 240, ideal: 285, max: 360)
        } detail: {
            if let id = selection, let goal = store.goals.first(where: { $0.id == id }) { GoalDetailView(store: store, goal: goal) }
            else {
                VStack(spacing: 18) {
                    Image(systemName: "leaf").font(.system(size: 44, weight: .light)).foregroundStyle(.mint)
                    Text("从一个目标开始").font(.title2.bold())
                    Text("把计划拆成阶段，再把真正要做的任务放入日常待办。")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HStack { Button("AI 生成计划") { generate = true }; Button("导入已有计划") { importPlan = true }; Button("手动创建") { manual = Goal() } }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
            }
        }
        .frame(minWidth: 960, minHeight: 650)
        .tint(Color(red: 0.19, green: 0.55, blue: 0.43))
        .sheet(isPresented: $importPlan) { PlanImportView(store: store) }
        .sheet(isPresented: $generate) { AIPlanGeneratorView(store: store) }
        .sheet(isPresented: $settings) { AISettingsView() }
        .sheet(item: $manual) { goal in GoalEditorView(initial: goal, heading: "手动创建目标", store: store, isNew: true) }
        .alert("目标数据提示", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) { Button("好") { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
        .confirmationDialog("使用最近一次保存前的备份恢复目标？当前文件会另存一份。", isPresented: $restore) { Button("恢复备份") { store.restoreBackup() } }
    }
    @ViewBuilder private var createActions: some View {
        Button("AI 生成计划") { generate = true }
        Button("导入已有计划") { importPlan = true }
        Button("手动创建") { manual = Goal() }
    }
}
struct GoalDetailView: View {
    @ObservedObject var store: GoalStore
    let goal: Goal
    @State private var collapsed: Set<UUID> = []
    @State private var editor = false
    @State private var selectedTask: GoalTask?
    @State private var deleteConfirmation = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                HStack {
                    ProgressView(value: goal.progress.fraction).tint(.mint)
                    Text(goal.progress.label).font(.callout).monospacedDigit()
                }
                Text("完成率按正式任务计数，取消与归档任务不计入分母；说明中的操作步骤不计入。")
                    .font(.caption).foregroundStyle(.secondary)
                if !goal.summary.isEmpty { Text(goal.summary).textSelection(.enabled) }
                if !goal.notes.isEmpty { MarkdownNotes(text: goal.notes) }
                if goal.phases.isEmpty { Text("还没有阶段。点击“编辑计划”来添加阶段和任务。").foregroundStyle(.secondary) }
                ForEach(Array(goal.phases.enumerated()), id: \.element.id) { index, phase in
                    phaseCard(phase, index: index)
                }
            }.padding(28)
        }
        .sheet(isPresented: $editor) { GoalEditorView(initial: goal, heading: "编辑计划", store: store, isNew: false) }
        .sheet(item: $selectedTask) { task in GoalTaskDetailView(store: store, taskID: task.id, goalTitle: goal.title) }
        .confirmationDialog("删除目标及其规划数据？已加入的日常待办将保留并解除关联。", isPresented: $deleteConfirmation) { Button("删除目标", role: .destructive) { store.delete(goal) } }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(goal.title).font(.system(size: 26, weight: .semibold)).textSelection(.enabled)
                Spacer()
                Menu {
                    Button("编辑计划") { editor = true }
                    Button("导出 JSON…") { export() }
                    Button("复制 JSON") { copyJSON() }
                    Divider()
                    ForEach(PlanState.allCases) { state in Button("标为\(state.title)") { var edited = goal; edited.state = state; _ = store.save(edited) } }
                    Divider(); Button("删除目标", role: .destructive) { deleteConfirmation = true }
                } label: { Image(systemName: "ellipsis.circle").font(.title2) }
            }
            HStack { Text(goal.term.title); Text(goal.state.title); Text(PlanDate.range(goal.startDate, goal.dueDate)); Text(goal.dateOrigin.title) }
                .font(.caption).foregroundStyle(.secondary)
            if !goal.tags.isEmpty { Text(goal.tags).font(.caption).foregroundStyle(.secondary) }
            HStack { Button("编辑计划") { editor = true }; Button("导出 JSON…") { export() } }
        }
    }
    private func phaseCard(_ phase: GoalPhase, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                if collapsed.contains(phase.id) { collapsed.remove(phase.id) } else { collapsed.insert(phase.id) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(String(format: "%02d", index + 1)).font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(width: 35, height: 35).background(Circle().fill(.mint.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(phase.title).font(.headline)
                        Text("\(PlanDate.range(phase.startDate, phase.dueDate)) · \(phase.dateOrigin.title) · \(phase.state.title)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(); Image(systemName: collapsed.contains(phase.id) ? "chevron.right" : "chevron.down")
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            HStack { ProgressView(value: phase.progress.fraction).tint(.mint); Text(phase.progress.label).font(.caption).foregroundStyle(.secondary) }
            if !collapsed.contains(phase.id) {
                if !phase.summary.isEmpty { Text(phase.summary).font(.callout).foregroundStyle(.secondary) }
                if !phase.milestone.isEmpty { Label("\(phase.milestone) · \(phase.milestoneDate ?? "日期待定")", systemImage: "flag").font(.callout) }
                ForEach(phase.tasks) { task in
                    HStack(alignment: .top, spacing: 10) {
                        Button { _ = store.updateTask(task.id) { $0.state = task.state == .completed ? .notStarted : .completed } } label: { Image(systemName: task.state == .completed ? "checkmark.circle.fill" : "circle").font(.title3) }.buttonStyle(.plain).help("切换任务完成状态")
                        Button { selectedTask = task } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title).strikethrough(task.state == .completed)
                                Text("\(task.state.title)\(task.dueDate.map { " · 截止 \($0)" } ?? "")\(task.linkedTodoID == nil ? "" : " · 已关联待办")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
                if phase.tasks.isEmpty { Text("此阶段还没有任务。").font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(18).background(RoundedRectangle(cornerRadius: 16).fill(.primary.opacity(0.035)))
    }
    private func copyJSON() { do { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(try PlanCodec.export(goal), forType: .string) } catch { store.errorMessage = error.localizedDescription } }
    private func export() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Mint-Plan.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Data(PlanCodec.export(goal).utf8).write(to: url, options: .atomic) } catch { store.errorMessage = error.localizedDescription }
    }
}
struct GoalTaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: GoalStore
    let taskID: UUID
    let goalTitle: String
    @State private var editing = false
    @State private var draftNotes = ""
    @State private var fullEditor = false
    @State private var refine = false
    @State private var outcome = ""
    @State private var linkChoice = false
    @State private var pendingToday = false
    private var task: GoalTask? { store.task(taskID) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let task {
                HStack { Text(task.title).font(.title2.bold()); Spacer(); Button("完成") { dismiss() } }
                HStack { Text(goalTitle).lineLimit(1); Text(task.state.title); if let minutes = task.estimatedMinutes { Text("约 \(minutes) 分钟") }; if let due = task.dueDate { Text("截止 \(due)") } }.font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("编辑任务") { fullEditor = true }
                    Button("AI 细化执行步骤") { refine = true }
                    if task.linkedTodoID == nil {
                        Menu("加入日常待办") { Button("加入待办列表") { attach(today: false) }; Button("加入今日待办") { attach(today: true) } }
                    } else { Label("已关联待办", systemImage: "link").font(.caption) }
                    Spacer()
                    Button(task.state == .completed ? "重新开始" : "标记完成") { _ = store.updateTask(taskID) { $0.state = task.state == .completed ? .notStarted : .completed } }
                }
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !task.summary.isEmpty { Text(task.summary).foregroundStyle(.secondary) }
                        HStack {
                            Text("执行说明").font(.headline); Spacer()
                            if editing { Button("放弃编辑") { editing = false }; Button("保存说明") { if store.updateTask(taskID, { $0.notes = draftNotes }) { editing = false } } }
                            else { Button("编辑 Markdown") { draftNotes = task.notes; editing = true } }
                        }
                        if editing { TextEditor(text: $draftNotes).font(.system(size: 13, design: .monospaced)).frame(minHeight: 280).border(.secondary.opacity(0.15)) }
                        else if task.notes.isEmpty { Text("暂无执行说明，可点击编辑补充。").foregroundStyle(.secondary) }
                        else { MarkdownNotes(text: task.notes, onToggle: { line in _ = store.updateTask(taskID) { $0.notes = MarkdownBlocks.toggle($0.notes, line: line) } }, onPromote: { title in promote(title, from: task) }) }
                        if !task.completionCriteria.isEmpty { detail("完成标准", task.completionCriteria) }
                        if !task.expectedOutput.isEmpty { detail("预期产出", task.expectedOutput) }
                        if !task.references.isEmpty { detail("参考资料", task.references) }
                        if !task.dependencies.isEmpty {
                            detail("依赖任务", task.dependencies.map { "- " + (store.task($0)?.title ?? "未知任务") }.joined(separator: "\n"))
                        }
                        Divider(); Text("成果与完成记录").font(.headline)
                        if let completed = task.completedAt { Text("完成于 \(completed.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                        ForEach(task.outcomes) { record in VStack(alignment: .leading) { Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary); MarkdownNotes(text: record.text) } }
                        TextEditor(text: $outcome).frame(height: 90).border(.secondary.opacity(0.15))
                        HStack { Text("可记录结果、文件路径、提交链接、问题与后续事项。").font(.caption).foregroundStyle(.secondary); Spacer(); Button("保存成果记录") { if store.updateTask(taskID, { $0.outcomes.append(OutcomeRecord(text: outcome)) }) { outcome = "" } }.disabled(outcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                    }.padding(.trailing, 8)
                }
            } else { Text("任务已删除。"); Button("关闭") { dismiss() } }
        }.padding(24).frame(width: 820, height: 710)
        .sheet(isPresented: $fullEditor) { if let task { GoalTaskEditor(initial: task) { edited in _ = store.updateTask(taskID) { $0 = edited } } } }
        .sheet(isPresented: $refine) { if let task { TaskRefinementView(task: task, goalTitle: goalTitle) { notes, append in _ = store.updateTask(taskID) { $0.notes = append ? $0.notes + "\n\n" + notes : notes } } } }
        .confirmationDialog("日常待办已有同名任务", isPresented: $linkChoice) {
            Button("关联已有待办") {
                if let task, let existing = store.daily.tasks.first(where: { $0.title == task.title && $0.goalTaskID == nil }) { store.attach(taskID, existing: existing.id) }
            }
            Button("仍创建新的待办") { store.attach(taskID, today: pendingToday) }
        } message: { Text("关联后以日常待办的完成状态为准，不会重复创建。") }
    }
    private func detail(_ title: String, _ text: String) -> some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline); MarkdownNotes(text: text) } }
    private func attach(today: Bool) {
        pendingToday = today
        if let task, store.daily.tasks.contains(where: { $0.title == task.title && $0.goalTaskID == nil }) { linkChoice = true }
        else { store.attach(taskID, today: today) }
    }
    private func promote(_ title: String, from task: GoalTask) {
        guard var goal = store.goals.first(where: { $0.id == task.goalID }), let p = goal.phases.firstIndex(where: { $0.id == task.phaseID }) else { return }
        goal.phases[p].tasks.append(GoalTask(goalID: goal.id, phaseID: task.phaseID, title: title))
        _ = store.save(goal)
    }
}
