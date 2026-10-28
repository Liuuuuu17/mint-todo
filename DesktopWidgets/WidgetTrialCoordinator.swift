import AppKit
import SwiftUI
import WidgetKit

@MainActor final class MintWidgetTrialCoordinator: ObservableObject {
    @Published private(set) var snapshot = MintWidgetSnapshot()
    @Published private(set) var notice: String?
    @Published private(set) var status = "试用数据 · 与主 App 同步"
    let files: MintWidgetFiles
    private let daily: TaskStore
    private let goals: GoalStore
    private let themeProvider: @MainActor (URL) -> MintWidgetTheme
    private var timer: Timer?
    private var processing = false
    private var lastPublished: MintWidgetSnapshot?

    init(daily: TaskStore, goals: GoalStore, watch: Bool = true, seedDemo: Bool = true,
         themeProvider: @escaping @MainActor (URL) -> MintWidgetTheme = MintWidgetTrialCoordinator.currentTheme) {
        self.daily = daily; self.goals = goals
        files = MintWidgetFiles(folder: daily.fileURL.deletingLastPathComponent())
        self.themeProvider = themeProvider
        if seedDemo { prepareDemo() }
        refresh()
        if watch {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    func submit(_ command: MintWidgetCommand) {
        do { try files.enqueue(command); refresh() }
        catch { notice = "操作未保存：\(error.localizedDescription)" }
    }

    func refresh() {
        guard !processing else { return }
        processing = true; defer { processing = false }
        do {
            var acknowledged: [MintWidgetCommand] = []
            for command in try files.commands() {
                switch command.target {
                case .daily:
                    if let task = daily.tasks.first(where: { $0.id == command.taskID }) {
                        if task.status == .cancelled { acknowledged.append(command); continue }
                        let wanted: TaskStatus = command.completed ? .completed : .todo
                        daily.setStatus(task, wanted, now: command.createdAt)
                        if daily.tasks.first(where: { $0.id == task.id })?.status == wanted { acknowledged.append(command) }
                    } else { acknowledged.append(command) }
                case .goal:
                    if let task = goals.task(command.taskID) {
                        if [.cancelled, .archived].contains(task.state) { acknowledged.append(command); continue }
                        let wanted: PlanState = command.completed ? .completed : .notStarted
                        if task.state == wanted || goals.updateTask(task.id, { $0.state = wanted }) {
                            goals.reconcileTodos()
                            if goals.task(task.id)?.state == wanted { acknowledged.append(command) }
                        }
                    } else { acknowledged.append(command) }
                }
            }
            goals.reconcileTodos()
            // Publish the durable app state before acknowledging commands. A crash
            // before acknowledgment simply replays the same desired state.
            try publish()
            for command in acknowledged { try files.acknowledge(command) }
            if !acknowledged.isEmpty { status = "已同步桌面操作 · \(Date().formatted(date: .omitted, time: .shortened))" }
            let waiting = try files.commands()
            snapshot = (lastPublished ?? snapshot).applying(waiting)
            notice = waiting.isEmpty ? nil : "还有 \(waiting.count) 项操作待保存，将自动重试。"
        } catch { notice = "小组件同步失败：\(error.localizedDescription)" }
    }

    private func publish() throws {
        var value = MintWidgetSnapshot(tasks: daily.tasks.map { task in
            MintWidgetTask(id: task.id, title: task.title, category: task.category, status: task.status.rawValue,
                           dueAt: task.dueAt, completedAt: task.completedAt, goalTaskID: task.goalTaskID,
                           subtasks: task.subtasks.map { MintWidgetSubtask(id: $0.id, title: $0.title, isCompleted: $0.isCompleted) })
        }, goals: goals.goals.map { goal in
            MintWidgetGoal(id: goal.id, title: goal.title, state: goal.state.rawValue, color: goal.color,
                           phases: goal.phases.filter { $0.state.counted }.map { phase in
                MintWidgetPhase(id: phase.id, title: phase.title, tasks: phase.tasks.map {
                    MintWidgetPlanTask(id: $0.id, title: $0.title, state: $0.state.rawValue, linkedTodoID: $0.linkedTodoID)
                })
            })
        }, theme: themeProvider(files.folder), isReady: true)
        value.generatedAt = lastPublished?.generatedAt ?? Date()
        guard value != lastPublished else { return }
        value.generatedAt = Date()
        try files.writeSnapshot(value)
        lastPublished = value; snapshot = value
        WidgetCenter.shared.reloadTimelines(ofKind: MintWidgetFiles.kind)
    }

    static func currentTheme(folder: URL) -> MintWidgetTheme {
        let defaults = UserDefaults.standard
        var theme = MintWidgetTheme()
        theme.background = defaults.string(forKey: "appearanceColor") ?? "#F0F0FA"
        theme.paperStyle = defaults.string(forKey: "noteStyle") == "retro"
        if theme.paperStyle {
            theme.background = ["cream": "#F3E9D2", "retro": "#E9D8B4", "blue": "#DAE6E9", "gray": "#ECECE6"][defaults.string(forKey: "notePaper") ?? "cream"] ?? "#F3E9D2"
        }
        let scale = defaults.double(forKey: "taskFontSize")
        theme.fontScale = scale > 0 ? scale / 13.5 : 1
        if let data = try? Data(contentsOf: folder.appendingPathComponent("fonts.json")),
           let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let applied = manifest["appliedID"] as? String,
           let fonts = manifest["fonts"] as? [[String: Any]],
           let selected = fonts.first(where: { ($0["id"] as? String) == applied }) {
            theme.fontName = selected["postScriptName"] as? String
            theme.fontFile = selected["fileName"] as? String
        }
        return theme
    }

    private func prepareDemo() {
        let marker = files.folder.appendingPathComponent("trial-initialized")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        if daily.tasks.isEmpty && goals.goals.isEmpty {
            var project = Goal(title: "完成个人作品", state: .inProgress)
            var preparation = GoalPhase(title: "准备与整理", state: .inProgress)
            var reference = GoalTask(goalID: project.id, phaseID: preparation.id, title: "收集参考资料", state: .completed)
            reference.completedAt = Date()
            preparation.tasks = [reference, GoalTask(goalID: project.id, phaseID: preparation.id, title: "整理第一版大纲")]
            var draft = GoalPhase(title: "完成初稿")
            draft.tasks = [GoalTask(goalID: project.id, phaseID: draft.id, title: "写出初稿")]
            project.phases = [preparation, draft]
            if let id = goals.insert(project), let saved = goals.goals.first(where: { $0.id == id }) {
                goals.attach(saved.phases[0].tasks[1].id, today: true)
            }
            var reading = Goal(title: "建立阅读习惯", state: .inProgress, color: "#8B9BC8")
            var phase = GoalPhase(title: "本周阅读", state: .inProgress)
            var choose = GoalTask(goalID: reading.id, phaseID: phase.id, title: "选择一本书", state: .completed)
            choose.completedAt = Date()
            phase.tasks = [choose, GoalTask(goalID: reading.id, phaseID: phase.id, title: "完成第一章")]
            reading.phases = [phase]
            _ = goals.insert(reading)
            var walk = Todo(title: "散步 20 分钟", category: "生活")
            walk.subtasks = [TodoSubtask(title: "带上水杯"), TodoSubtask(title: "出门走一走")]
            _ = daily.saveEdited(walk)
            _ = daily.saveEdited(Todo(title: "读完今天的章节", category: "学习"))
            _ = daily.saveEdited(Todo(title: "整理工作台", category: "生活", status: .completed, completedAt: Date()))
        }
        if !daily.tasks.isEmpty || !goals.goals.isEmpty {
            try? Data("Widget trial initialized".utf8).write(to: marker, options: .atomic)
        }
    }
}

struct MintWidgetTrialPreview: View {
    @ObservedObject var coordinator: MintWidgetTrialCoordinator
    let showApp: () -> Void
    let showGoals: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Mint Todo · 桌面小组件试用版").font(.system(size: 22, weight: .semibold))
                    Text("在这里测试三种尺寸，勾选后可到主 App 核对状态。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("显示主 App", action: showApp)
                Button("查看目标", action: showGoals)
                Button("退出试用") { NSApp.terminate(nil) }
            }
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("SMALL · 进度").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                    card(.small, width: 170, height: 170)
                    Text("MEDIUM · 全部待办").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                    card(.medium, width: 360, height: 180)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("LARGE · 目标 → 阶段 → 任务").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                    card(.large, width: 360, height: 390)
                }
            }
            HStack(spacing: 7) {
                Circle().fill(coordinator.notice == nil ? Color.green : Color.orange).frame(width: 6, height: 6)
                Text(coordinator.notice ?? coordinator.status).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Divider()
            Text("添加到桌面：桌面右键 → 编辑小组件 → 搜索「Mint Todo · 试用」")
                .font(.system(size: 12, weight: .medium))
            #if MINT_WIDGET_LOCAL_ACTIONS
            Text("本机版：小组件勾选会唤起试用 App 并同步。中号显示全部未完成待办，包含未来日期的任务。试用数据独立保存。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            #else
            Text("中号显示全部未完成待办，包含未来日期的任务。试用数据独立保存；主 App 关闭时，桌面操作会保留，重新打开后同步。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            #endif
        }
        .padding(24)
        .frame(width: 788)
    }
    private func card(_ size: MintWidgetSize, width: CGFloat, height: CGFloat) -> some View {
        MintWidgetCard(snapshot: coordinator.snapshot, size: size, onComplete: coordinator.submit)
            .padding(16).frame(width: width, height: height)
            .background { MintWidgetBackground(theme: coordinator.snapshot.theme) }
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.primary.opacity(0.07), lineWidth: 0.5))
    }
}
