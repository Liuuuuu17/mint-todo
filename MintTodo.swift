import AppKit
import SwiftUI

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo, pending, completed, cancelled

    var id: String { rawValue }
    var title: String {
        switch self {
        case .todo: return "待办"
        case .pending: return "进行中"
        case .completed: return "已完成"
        case .cancelled: return "已取消"
        }
    }
    var symbol: String {
        switch self {
        case .todo: return "circle"
        case .pending: return "clock"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }
}

enum RepeatRule: String, Codable, CaseIterable, Identifiable {
    case once, daily, weekdays, interval
    var id: String { rawValue }
    var title: String { switch self { case .once: return "一次性"; case .daily: return "每天"; case .weekdays: return "每个工作日"; case .interval: return "每几天" } }
    func next(after date: Date, interval: Int, calendar: Calendar = .current) -> Date {
        var next = calendar.date(byAdding: .day, value: self == .interval ? max(1, interval) : 1, to: date)!
        if self == .weekdays {
            while [1, 7].contains(calendar.component(.weekday, from: next)) { next = calendar.date(byAdding: .day, value: 1, to: next)! }
        }
        return next
    }
}

struct TodoSubtask: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var isCompleted = false
}

struct Todo: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var category: String
    var status: TaskStatus = .todo
    var createdAt: Date = Date()
    var dueAt: Date? = nil
    var scheduledStartAt: Date? = nil
    var dueDateOnly: Bool? = nil
    var goalTaskID: UUID? = nil
    var completedAt: Date? = nil
    var repeatRule: RepeatRule? = nil
    var repeatInterval: Int? = nil
    var occurrenceAt: Date? = nil
    var generatedFrom: UUID? = nil
    var recurrenceSpawnedAt: Date? = nil
    var subtasks: [TodoSubtask] = []

    func visibleInTodo() -> Bool {
        status == .todo || status == .pending
    }
}

extension Todo {
    private enum CodingKeys: String, CodingKey {
        case id, title, category, status, createdAt, dueAt, scheduledStartAt, dueDateOnly, goalTaskID, completedAt
        case repeatRule, repeatInterval, occurrenceAt, generatedFrom, recurrenceSpawnedAt, subtasks
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try values.decode(String.self, forKey: .title)
        category = try values.decode(String.self, forKey: .category)
        status = try values.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .todo
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        dueAt = try values.decodeIfPresent(Date.self, forKey: .dueAt)
        scheduledStartAt = try values.decodeIfPresent(Date.self, forKey: .scheduledStartAt)
        dueDateOnly = try values.decodeIfPresent(Bool.self, forKey: .dueDateOnly)
        goalTaskID = try values.decodeIfPresent(UUID.self, forKey: .goalTaskID)
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        repeatRule = try values.decodeIfPresent(RepeatRule.self, forKey: .repeatRule)
        repeatInterval = try values.decodeIfPresent(Int.self, forKey: .repeatInterval)
        occurrenceAt = try values.decodeIfPresent(Date.self, forKey: .occurrenceAt)
        generatedFrom = try values.decodeIfPresent(UUID.self, forKey: .generatedFrom)
        recurrenceSpawnedAt = try values.decodeIfPresent(Date.self, forKey: .recurrenceSpawnedAt)
        subtasks = try values.decodeIfPresent([TodoSubtask].self, forKey: .subtasks) ?? []
    }
}

struct SavedData: Codable {
    var categories: [String]
    var tasks: [Todo]
}

@MainActor final class TaskStore: ObservableObject {
    @Published private(set) var categories: [String] = ["工作", "生活", "内容", "学习"]
    @Published private(set) var tasks: [Todo] = []
    @Published var selectedStatus: TaskStatus = .todo
    var onChange: (() -> Void)?

    let fileURL: URL
    private var lastModified: Date?
    private var watchTimer: Timer?

    init(folder override: URL? = nil, watch: Bool = true) {
        #if MINT_WIDGET_TRIAL
        let defaultFolder = MintWidgetFiles.defaultFolder
        #else
        let defaultFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OrbTodo", isDirectory: true)
        #endif
        let folder = override ?? ProcessInfo.processInfo.environment["MINTTODO_DATA_DIR"].map { URL(fileURLWithPath: $0) } ?? defaultFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("tasks.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = Self.decode(data) {
            categories = saved.categories.isEmpty ? ["收件箱"] : saved.categories
            tasks = saved.tasks
        }
        if !FileManager.default.fileExists(atPath: fileURL.path) { save() }
        lastModified = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        refreshRecurring()
        if watch { watchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadIfChanged(); self?.refreshRecurring() }
        } }
    }

    @discardableResult private func save() -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(SavedData(categories: categories, tasks: tasks)) else { return false }
        do { try data.write(to: fileURL, options: .atomic) } catch { return false }
        lastModified = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        onChange?()
        return true
    }

    private static func decode(_ data: Data) -> SavedData? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(SavedData.self, from: data))
            ?? (try? JSONDecoder().decode(SavedData.self, from: data))
    }

    private func reloadIfChanged() {
        guard let modified = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              modified != lastModified,
              let data = try? Data(contentsOf: fileURL),
              let saved = Self.decode(data) else { return }
        categories = saved.categories.isEmpty ? ["收件箱"] : saved.categories
        tasks = saved.tasks
        lastModified = modified
        onChange?()
    }

    @discardableResult func applyReminderChanges(updates: [Todo], deletedIDs: Set<UUID>) -> Bool {
        let previousTasks = tasks
        let previousCategories = categories
        var changed = false
        for var updated in updates {
            if updated.status == .completed && updated.completedAt == nil {
                updated.completedAt = tasks.first(where: { $0.id == updated.id })?.completedAt ?? Date()
            } else if updated.status != .completed { updated.completedAt = nil }
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                if tasks[index] != updated { tasks[index] = updated; changed = true }
            } else {
                tasks.append(updated)
                changed = true
            }
            if !categories.contains(updated.category) {
                categories.append(updated.category)
                changed = true
            }
        }
        if !deletedIDs.isEmpty {
            let oldCount = tasks.count
            tasks.removeAll { deletedIDs.contains($0.id) }
            if tasks.count != oldCount { changed = true }
        }
        if changed && !save() {
            tasks = previousTasks
            categories = previousCategories
            return false
        }
        return true
    }

    func ensureGoalTodo(_ task: GoalTask, existing: UUID?, today: Bool, category: String = "目标任务") -> UUID? {
        if let saved = tasks.first(where: { $0.goalTaskID == task.id }) { return saved.id }
        let oldTasks = tasks; let oldCategories = categories
        let id: UUID
        if let existing, let i = tasks.firstIndex(where: { $0.id == existing && $0.goalTaskID == nil }) {
            tasks[i].goalTaskID = task.id; tasks[i].category = category
            if !categories.contains(category) { categories.append(category) }; id = existing
        } else {
            if !categories.contains(category) { categories.append(category) }
            var todo = Todo(title: task.title, category: category, status: task.state.todoStatus ?? .todo,
                            dueAt: today ? Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: Date()) : PlanDate.localDeadline(task.dueDate))
            todo.goalTaskID = task.id; tasks.append(todo); id = todo.id
        }
        guard save() else { tasks = oldTasks; categories = oldCategories; return nil }
        return id
    }
    func unlinkGoalTask(_ id: UUID) {
        var changed = false
        for i in tasks.indices where tasks[i].goalTaskID == id { tasks[i].goalTaskID = nil; changed = true }
        if changed { save() }
    }

    func add(_ title: String, category: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let group = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = group.isEmpty ? "收件箱" : group
        if !categories.contains(chosen) { categories.append(chosen) }
        tasks.append(Todo(title: clean, category: chosen))
        save()
    }

    func addCategory(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !categories.contains(clean) else { return }
        categories.append(clean)
        save()
    }

    @discardableResult func saveEdited(_ source: Todo) -> Bool {
        var task = source
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.category = task.category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.title.isEmpty else { return false }
        if task.category.isEmpty { task.category = "收件箱" }
        let oldTasks = tasks; let oldCategories = categories
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i] = task } else { tasks.append(task) }
        if !categories.contains(task.category) { categories.append(task.category) }
        guard save() else { tasks = oldTasks; categories = oldCategories; return false }
        return true
    }
    func update(_ task: Todo, title: String, category: String, dueAt: Date?) {
        var edited = task; edited.title = title; edited.category = category; edited.dueAt = dueAt
        _ = saveEdited(edited)
    }
    func setStatus(_ task: Todo, _ status: TaskStatus, now: Date = Date()) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }), tasks[index].status != status else { return }
        let old = tasks
        tasks[index].status = status
        tasks[index].completedAt = status == .completed ? now : nil
        if !save() { tasks = old }
    }
    func setSubtaskCompleted(taskID: UUID, subtaskID: UUID, completed: Bool) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }),
              let subtaskIndex = tasks[taskIndex].subtasks.firstIndex(where: { $0.id == subtaskID }),
              tasks[taskIndex].subtasks[subtaskIndex].isCompleted != completed else { return }
        let old = tasks
        tasks[taskIndex].subtasks[subtaskIndex].isCompleted = completed
        if !save() { tasks = old }
    }
    // Generate one next occurrence only when its calendar day arrives. Missed days do not create a backlog.
    func refreshRecurring(now: Date = Date(), calendar: Calendar = .current) {
        let old = tasks
        for i in tasks.indices {
            guard tasks[i].status == .completed, let completed = tasks[i].completedAt,
                  let rule = tasks[i].repeatRule, rule != .once, tasks[i].recurrenceSpawnedAt == nil else { continue }
            let base = max(completed, tasks[i].occurrenceAt ?? tasks[i].dueAt ?? completed)
            let next = rule.next(after: base, interval: tasks[i].repeatInterval ?? 1, calendar: calendar)
            guard calendar.startOfDay(for: next) <= calendar.startOfDay(for: now) else { continue }
            var occurrence = calendar.startOfDay(for: now)
            if rule == .weekdays && [1, 7].contains(calendar.component(.weekday, from: occurrence)) { continue }
            if let due = tasks[i].dueAt {
                let time = calendar.dateComponents([.hour, .minute], from: due)
                occurrence = calendar.date(bySettingHour: time.hour ?? 23, minute: time.minute ?? 59, second: 0, of: occurrence) ?? occurrence
            }
            var nextTask = Todo(title: tasks[i].title, category: tasks[i].category, createdAt: now, dueAt: tasks[i].dueAt == nil ? nil : occurrence)
            nextTask.repeatRule = rule; nextTask.repeatInterval = tasks[i].repeatInterval
            nextTask.occurrenceAt = occurrence; nextTask.generatedFrom = tasks[i].id
            nextTask.subtasks = tasks[i].subtasks.map { TodoSubtask(title: $0.title) }
            nextTask.dueDateOnly = tasks[i].dueDateOnly
            if let start = tasks[i].scheduledStartAt, let due = tasks[i].dueAt, nextTask.dueAt != nil {
                nextTask.scheduledStartAt = occurrence.addingTimeInterval(start.timeIntervalSince(due))
            }
            tasks[i].recurrenceSpawnedAt = now
            tasks.append(nextTask)
        }
        if tasks != old && !save() { tasks = old }
    }
    func groupGoalTasks(_ ids: Set<UUID>, category: String) {
        let old = tasks; let oldCategories = categories
        if !categories.contains(category) { categories.append(category) }
        for i in tasks.indices where tasks[i].goalTaskID.map({ ids.contains($0) }) == true { tasks[i].category = category }
        if (old != tasks || oldCategories != categories) && !save() { tasks = old; categories = oldCategories }
    }

    func delete(_ task: Todo) {
        tasks.removeAll { $0.id == task.id }
        save()
    }

    func removeCategory(_ name: String) {
        guard categories.count > 1 else { return }
        categories.removeAll { $0 == name }
        let fallback = categories[0]
        for index in tasks.indices where tasks[index].category == name { tasks[index].category = fallback }
        save()
    }

    func textExport() -> String {
        var lines: [String] = []
        for status in TaskStatus.allCases {
            let matching = tasks.filter { $0.status == status }
            guard !matching.isEmpty else { continue }
            lines.append("## \(status.title)")
            for category in categories {
                let group = matching.filter { $0.category == category }
                guard !group.isEmpty else { continue }
                lines.append("# \(category)")
                for task in group {
                    lines.append("- \(task.title)")
                    lines += task.subtasks.map { "  - [\($0.isCompleted ? "x" : " ")] \($0.title)" }
                }
            }
            lines.append("")
        }
        return lines.isEmpty ? "待办清单为空" : lines.joined(separator: "\n")
    }

    @discardableResult func importText(_ text: String) -> Int {
        var category = categories.first ?? "收件箱"
        var status: TaskStatus = .todo
        var count = 0
        var parentIndex: Int?
        for raw in text.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let isIndented = raw.first == " " || raw.first == "\t"
            if isIndented, let parentIndex, line.hasPrefix("- ") {
                var completed = false
                if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                    line = String(line.dropFirst(6)); completed = true
                } else if line.hasPrefix("- [ ] ") {
                    line = String(line.dropFirst(6))
                } else {
                    line = String(line.dropFirst(2))
                }
                line = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { tasks[parentIndex].subtasks.append(TodoSubtask(title: line, isCompleted: completed)) }
                continue
            }
            if line.hasPrefix("## ") {
                let heading = String(line.dropFirst(3))
                status = TaskStatus.allCases.first { $0.title == heading } ?? .todo
                parentIndex = nil
                continue
            }
            if line.hasPrefix("# ") {
                category = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !categories.contains(category) { categories.append(category) }
                parentIndex = nil
                continue
            }
            var itemStatus = status
            if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                line = String(line.dropFirst(6))
                itemStatus = .completed
            } else if line.hasPrefix("- [ ] ") {
                line = String(line.dropFirst(6))
            } else if line.hasPrefix("- ") {
                line = String(line.dropFirst(2))
            }
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            tasks.append(Todo(title: line, category: category, status: itemStatus, completedAt: itemStatus == .completed ? Date() : nil))
            parentIndex = tasks.count - 1
            count += 1
        }
        if count > 0 { save() }
        return count
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct TaskEditorRequest: Identifiable {
    var task: Todo
    var isNew = false
    var focusSubtask = false
    var id: UUID { task.id }
}

struct WidgetView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var fontLibrary: FontLibrary
    @ObservedObject var reminderSync: RemindersSync
    @ObservedObject var goalStore: GoalStore
    let onOpenGoal: (UUID) -> Void
    let onCollapse: () -> Void
    let onGoals: () -> Void
    let onPin: (Bool) -> Void
    let onOpacity: (Double) -> Void
    let onResize: (CGSize) -> Void

    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("noteStyle") private var noteStyle = "minimal"
    @State private var showingLongTerm = false
    @State private var input = ""
    @State private var chosenCategory = "工作"
    @State private var editing: TaskEditorRequest?
    @State private var showImport = false
    @State private var showCategory = false
    @State private var showArchive = false
    @State private var showSettings = false
    @AppStorage("widgetPinned") private var pinned = true
    @AppStorage("widgetWidth") private var widgetWidth = 405.0
    @AppStorage("widgetHeight") private var widgetHeight = 560.0
    @State private var collapsedGroups: Set<String> = []
    @State private var collapsedTasks: Set<UUID> = []
    @State private var importedCount: Int?

    @AppStorage("noteCornerStyle") private var cornerStyle = "square"
    private var frameShape: RoundedRectangle { NoteFrameAppearance.shape(for: cornerStyle) }

    private var headerTitle: String {
        #if MINT_WIDGET_TRIAL
        return "MINT / TRIAL"
        #else
        return noteStyle == "retro" ? "MINT / NOTES" : "MINT TODO"
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            statusBar
            Divider().opacity(0.36).padding(.horizontal, 21)
            if showingLongTerm {
                LongTermTasksView(store: goalStore, onOpenGoal: onOpenGoal, onOpenAll: onGoals)
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let visible = store.tasks.filter { store.selectedStatus == .todo ? $0.visibleInTodo() : $0.status == .completed }
                    if visible.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.categories, id: \.self) { category in
                            let groupTasks = visible.filter { $0.category == category }
                            if !groupTasks.isEmpty { group(category, tasks: groupTasks) }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 20)
            }
            bottomBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 320, minHeight: 380)
        .background {
            AppearanceBackground()
        }
        .environment(\.colorScheme, noteStyle == "retro" ? .light : systemColorScheme)
        .clipShape(frameShape)
        .overlay(frameShape.stroke(noteStyle == "retro" ? Color(red: 0.44, green: 0.35, blue: 0.25).opacity(0.38) : .black.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 10, x: 1, y: 5)
        .overlay { WindowResizeEdges() }
        .sheet(item: $editing) { request in EditTaskSheet(store: store, fontLibrary: fontLibrary, task: request.task, isNew: request.isNew, focusSubtask: request.focusSubtask) }
        .sheet(isPresented: $showImport) { ImportSheet(store: store, importedCount: $importedCount) }
        .sheet(isPresented: $showCategory) { CategorySheet(store: store, chosenCategory: $chosenCategory) }
        .sheet(isPresented: $showArchive) { ArchiveSheet(store: store, fontLibrary: fontLibrary) }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                store: store,
                fontLibrary: fontLibrary,
                reminderSync: reminderSync,
                onOpacity: onOpacity,
                onResize: onResize,
                onImport: { showSettings = false; DispatchQueue.main.async { showImport = true } },
                onCategory: { showSettings = false; DispatchQueue.main.async { showCategory = true } },
                onArchive: { showSettings = false; DispatchQueue.main.async { showArchive = true } }
            )
        }
        .alert("已导入 \(importedCount ?? 0) 项待办", isPresented: Binding(get: { importedCount != nil }, set: { if !$0 { importedCount = nil } })) {
            Button("好", role: .cancel) { importedCount = nil }
        }
        .onAppear { chosenCategory = store.categories.first ?? "收件箱" }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(headerTitle)
                .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(2)
                .lineLimit(1).fixedSize(horizontal: true, vertical: true)
                .overlay { WindowDragSurface(click: onGoals) }
                .help("拖动移动便签，点击打开目标规划")
            Spacer(minLength: 8).frame(maxHeight: .infinity).background { WindowDragSurface() }
            Button { pinned.toggle(); onPin(pinned) } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .rotationEffect(.degrees(35))
                    .frame(width: 40, height: 40).contentShape(Rectangle())
            }
            .help(pinned ? "取消置顶" : "置顶")
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 15))
                    .frame(width: 40, height: 40).contentShape(Rectangle())
            }
                .help("设置")
            Button(action: onCollapse) {
                Image(systemName: "minus").font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 40).contentShape(Rectangle())
            }
                .help("收起为小圆点")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    private var statusBar: some View {
        HStack(spacing: 3) {
            ForEach([TaskStatus.todo, .completed]) { status in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showingLongTerm = false; store.selectedStatus = status }
                } label: {
                    HStack(spacing: 4) {
                        Text(status.title)
                        let count = store.tasks.filter { status == .todo ? $0.status == .todo || $0.status == .pending : $0.status == .completed }.count
                        if count > 0 && status != .completed { Text("\(count)").font(.system(size: 10, weight: .bold)).opacity(0.65) }
                    }
                    .font(fontLibrary.font(12, weight: !showingLongTerm && store.selectedStatus == status ? .semibold : .medium))
                    .foregroundStyle(!showingLongTerm && store.selectedStatus == status ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if !showingLongTerm && store.selectedStatus == status {
                            RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.68))
                                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Button { withAnimation(.easeInOut(duration: 0.18)) { showingLongTerm = true } } label: {
                Text("长期任务")
                    .font(fontLibrary.font(12, weight: showingLongTerm ? .semibold : .medium))
                    .foregroundStyle(showingLongTerm ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background {
                        if showingLongTerm { RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.68)) }
                    }
            }.buttonStyle(.plain)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 13).fill(.black.opacity(0.045)))
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 11) {
            Image(systemName: store.selectedStatus == .todo ? "sparkle" : store.selectedStatus.symbol)
                .font(.system(size: 30, weight: .ultraLight))
                .foregroundStyle(Color(red: 0.48, green: 0.48, blue: 0.66))
            Text(store.selectedStatus == .todo ? "从一件小事开始" : "这里还没有事项")
                .font(fontLibrary.font(15, weight: .medium))
            Text(store.selectedStatus == .todo ? "在下方输入，按回车添加待办" : "任务状态改变后会出现在这里")
                .font(fontLibrary.font(12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 112)
    }

    private func group(_ name: String, tasks: [Todo]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                if collapsedGroups.contains(name) { collapsedGroups.remove(name) }
                else { collapsedGroups.insert(name) }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(collapsedGroups.contains(name) ? -90 : 0))
                    Text(name).font(fontLibrary.font(13, weight: .semibold))
                    Text("\(tasks.count)").font(fontLibrary.font(11)).foregroundStyle(.tertiary)
                    Spacer()
                }
                .foregroundStyle(.primary.opacity(0.83))
            }
            .buttonStyle(.plain)
            if !collapsedGroups.contains(name) {
                ForEach(tasks) { task in taskRow(task) }
            }
        }
    }

    private func taskRow(_ task: Todo) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    store.setStatus(task, task.status == .completed ? .todo : .completed)
                } label: {
                    Image(systemName: task.status == .completed ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(task.status == .completed ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.65))
                }
                .buttonStyle(.plain)
                .help(task.status == .completed ? "恢复为待办" : "标记完成")
                Button { editing = TaskEditorRequest(task: task) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(fontLibrary.font(13.5, monospaced: true))
                            .strikethrough(task.status == .completed || task.status == .cancelled)
                        if let dueAt = task.dueAt {
                            Label(NaturalTaskTime(start: task.scheduledStartAt, end: dueAt, dateOnly: task.dueDateOnly == true).label(), systemImage: "calendar")
                                .font(fontLibrary.font(10))
                                .foregroundStyle(dueAt < Date() && task.status != .completed ? Color.red.opacity(0.8) : Color.secondary)
                        }
                        if !task.subtasks.isEmpty {
                            Text("子任务 \(task.subtasks.filter(\.isCompleted).count)/\(task.subtasks.count)")
                                .font(fontLibrary.font(10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(task.status == .completed || task.status == .cancelled ? Color.secondary : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("编辑任务、子任务与截止时间")
                if !task.subtasks.isEmpty {
                    Button {
                        if collapsedTasks.contains(task.id) { collapsedTasks.remove(task.id) }
                        else { collapsedTasks.insert(task.id) }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(collapsedTasks.contains(task.id) ? -90 : 0))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(collapsedTasks.contains(task.id) ? "展开子任务" : "收起子任务")
                }
                Menu {
                    Button("编辑") { editing = TaskEditorRequest(task: task) }
                    Button("添加子任务") { editing = TaskEditorRequest(task: task, focusSubtask: true) }
                    Divider()
                    ForEach(TaskStatus.allCases) { status in
                        Button(status.title, systemImage: status.symbol) { store.setStatus(task, status) }
                    }
                    Divider()
                    Button("删除", role: .destructive) { store.delete(task) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .frame(width: 22, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 3)
            .padding(.vertical, 5)
            if !collapsedTasks.contains(task.id) {
                ForEach(task.subtasks) { subtask in
                    HStack(alignment: .top, spacing: 8) {
                        Button {
                            store.setSubtaskCompleted(taskID: task.id, subtaskID: subtask.id, completed: !subtask.isCompleted)
                        } label: {
                            Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 13, weight: .light))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(subtask.isCompleted ? "恢复子任务" : "完成子任务")
                        Button { editing = TaskEditorRequest(task: task) } label: {
                            Text(subtask.title)
                                .font(fontLibrary.font(12.5, monospaced: true))
                                .strikethrough(subtask.isCompleted)
                                .foregroundStyle(subtask.isCompleted ? Color.secondary : Color.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .help("编辑子任务")
                    }
                    .padding(.leading, 32)
                    .padding(.vertical, 3)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if noteStyle == "retro" {
                Rectangle().fill(Color(red: 0.40, green: 0.33, blue: 0.25).opacity(0.20))
                    .frame(height: 0.5).padding(.leading, 29)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(store.categories, id: \.self) { category in
                    Button(category) { chosenCategory = category }
                }
                Divider()
                Button("新建分组…") { showCategory = true }
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("选择分组：\(chosenCategory)")
            .fixedSize()
            TextField("添加新待办…", text: $input)
                .font(fontLibrary.font(13, monospaced: true))
                .textFieldStyle(.plain)
                .onSubmit(addInput)
        }
        .padding(.horizontal, 12)
        .frame(height: 43)
        .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.055)))
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 8)
    }

    private func addInput() {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        editing = TaskEditorRequest(task: Todo(title: clean, category: store.categories.contains(chosenCategory) ? chosenCategory : store.categories.first ?? "收件箱"), isNew: true)
        input = ""
        store.selectedStatus = .todo
    }
}

struct EditTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TaskStore
    @ObservedObject var fontLibrary: FontLibrary
    let task: Todo
    @State private var title: String
    @State private var category: String
    @State private var hasDueDate: Bool
    @State private var dueAt: Date
    @State private var scheduledStartAt: Date
    @State private var hasTimeRange: Bool
    @State private var dateOnly: Bool
    private let recognitionDate = Date()
    @State private var originalTimeInput: String?
    @State private var extractedTime: NaturalTaskTime?
    private var detectedTime: NaturalTaskTime? { NaturalTaskTime.parse(title, now: recognitionDate) }
    let isNew: Bool
    @State private var repeatRule: RepeatRule
    @State private var repeatInterval: Int
    @State private var saveError: String?
    @State private var subtasks: [TodoSubtask]
    @State private var subtaskInput = ""
    @FocusState private var subtaskInputFocused: Bool
    let focusSubtask: Bool

    init(store: TaskStore, fontLibrary: FontLibrary, task: Todo, isNew: Bool = false, focusSubtask: Bool = false) {
        self.store = store
        self.fontLibrary = fontLibrary
        self.task = task
        self.isNew = isNew
        self.focusSubtask = focusSubtask
        _repeatRule = State(initialValue: task.repeatRule ?? .once)
        _repeatInterval = State(initialValue: task.repeatInterval ?? 2)
        _title = State(initialValue: task.title)
        _category = State(initialValue: task.category)
        _hasDueDate = State(initialValue: task.dueAt != nil)
        _dueAt = State(initialValue: task.dueAt ?? Date().addingTimeInterval(3600))
        let extraction = isNew && task.dueAt == nil ? NaturalTaskTime.extract(task.title) : nil
        let detected = extraction?.time
        _originalTimeInput = State(initialValue: extraction == nil ? nil : task.title)
        _extractedTime = State(initialValue: detected)
        if let extraction { _title = State(initialValue: extraction.title) }
        if let detected {
            _hasDueDate = State(initialValue: true)
            _dueAt = State(initialValue: detected.end)
        }
        _scheduledStartAt = State(initialValue: task.scheduledStartAt ?? detected?.start ?? Date())
        _hasTimeRange = State(initialValue: task.scheduledStartAt != nil || detected?.start != nil)
        _dateOnly = State(initialValue: task.dueDateOnly ?? detected?.dateOnly ?? false)
        _subtasks = State(initialValue: task.subtasks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "新建待办" : "编辑待办").font(fontLibrary.font(20, weight: .bold))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("待办内容", text: $title)
                        .font(fontLibrary.font(14))
                    if let detected = detectedTime {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("识别到：" + detected.label(), systemImage: "calendar.badge.clock")
                                .font(.system(size: 12))
                            Button("提取时间并整理标题") {
                                if let extraction = NaturalTaskTime.extract(title, now: recognitionDate) {
                                    originalTimeInput = title
                                    title = extraction.title
                                    extractedTime = extraction.time
                                    hasDueDate = true
                                    dueAt = extraction.time.end
                                    dateOnly = extraction.time.dateOnly
                                    hasTimeRange = extraction.time.start != nil
                                    scheduledStartAt = extraction.time.start ?? extraction.time.end
                                }
                            }
                            .font(.system(size: 11))
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
                    }
                    if detectedTime == nil, extractedTime != nil, let originalTimeInput {
                        VStack(alignment: .leading, spacing: 6) {
                            if hasDueDate {
                                Label("已提取：" + NaturalTaskTime(start: !dateOnly && hasTimeRange ? scheduledStartAt : nil, end: dueAt, dateOnly: dateOnly).label(), systemImage: "calendar.badge.clock")
                            }
                            Button("还原标题") {
                                title = originalTimeInput
                                self.originalTimeInput = nil
                                extractedTime = nil
                            }
                        }
                        .font(.system(size: 12))
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
                    }
                    Text("输入“周三团建”或“明天下午2:30到4:30培训”，会提取时间并整理标题，日期与时间仍可修改。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "checklist")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            TextField("添加子任务", text: $subtaskInput)
                                .font(fontLibrary.font(13))
                                .focused($subtaskInputFocused)
                                .onSubmit(addSubtask)
                            Button(action: addSubtask) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 20, weight: .light))
                            }
                            .buttonStyle(.plain)
                            .help("添加子任务")
                            .disabled(subtaskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if !subtasks.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach($subtasks) { $subtask in
                                    let subtaskID = subtask.id
                                    HStack(spacing: 8) {
                                        Text("•").frame(width: 20)
                                        TextField("子任务内容", text: $subtask.title)
                                            .font(fontLibrary.font(13))
                                        Button { subtasks.removeAll { $0.id == subtaskID } } label: {
                                            Image(systemName: "minus.circle")
                                                .font(.system(size: 20, weight: .light))
                                        }
                                        .buttonStyle(.plain)
                                        .help("删除子任务")
                                    }
                                }
                            }
                            .padding(.leading, 28)
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(.secondary.opacity(0.45))
                                    .frame(width: 1)
                                    .padding(.leading, 10)
                            }
                        }
                    }
                    HStack {
                        Text("分组")
                        Picker("分组", selection: $category) {
                            ForEach(store.categories, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden()
                    }
                    Toggle("设置日期与时间", isOn: $hasDueDate)
                    if hasDueDate {
                        Toggle("仅日期", isOn: $dateOnly)
                        if dateOnly {
                            DatePicker("日期", selection: $dueAt, displayedComponents: [.date])
                                .datePickerStyle(.compact)
                        } else {
                            Toggle("时间段", isOn: $hasTimeRange)
                            if hasTimeRange {
                                DatePicker("开始时间", selection: $scheduledStartAt, displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.compact)
                            }
                            DatePicker(hasTimeRange ? "结束时间" : "时间", selection: $dueAt, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                            if hasTimeRange && scheduledStartAt >= dueAt {
                                Text("结束时间需要晚于开始时间。").font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                    Picker("重复", selection: $repeatRule) {
                        ForEach(RepeatRule.allCases) { Text($0.title).tag($0) }
                    }
                    if repeatRule == .interval { Stepper("每 \(repeatInterval) 天", value: $repeatInterval, in: 1...365) }
                    if repeatRule != .once { Text("完成后，下一次到期当天自动加入待办。工作日为周一至周五。")
                        .font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            }
            .frame(height: min(420 + CGFloat(subtasks.count) * 30 + (hasDueDate ? 90 : 0), 540))
            if let saveError { Text(saveError).foregroundStyle(.red).font(.caption) }
            HStack {
                if !isNew { Button("删除", role: .destructive) { store.delete(task); dismiss() } }
                Spacer()
                Button("取消") { dismiss() }
                Button(isNew ? "创建" : "保存") {
                    var edited = store.tasks.first(where: { $0.id == task.id }) ?? task
                    edited.title = title; edited.category = category; edited.dueAt = hasDueDate ? dueAt : nil
                    if hasDueDate && dateOnly {
                        edited.dueAt = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: dueAt)
                    }
                    edited.scheduledStartAt = hasDueDate && !dateOnly && hasTimeRange ? scheduledStartAt : nil
                    edited.dueDateOnly = hasDueDate ? dateOnly : nil
                    edited.repeatRule = repeatRule; edited.repeatInterval = repeatInterval
                    edited.occurrenceAt = hasDueDate ? dueAt : Date()
                    edited.subtasks = subtasks.compactMap { subtask in
                        let clean = subtask.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        return clean.isEmpty ? nil : TodoSubtask(id: subtask.id, title: clean, isCompleted: subtask.isCompleted)
                    }
                    let pending = subtaskInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !pending.isEmpty { edited.subtasks.append(TodoSubtask(title: pending)) }
                    if store.saveEdited(edited) { dismiss() } else { saveError = "保存失败，请检查磁盘空间后重试。" }
                }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .disabled(hasDueDate && !dateOnly && hasTimeRange && scheduledStartAt >= dueAt)
            }
        }
        .padding(24)
        .frame(width: 390)
        .onAppear { if focusSubtask { subtaskInputFocused = true } }
    }

    private func addSubtask() {
        let clean = subtaskInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        subtasks.append(TodoSubtask(title: clean))
        subtaskInput = ""
        subtaskInputFocused = true
    }
}

struct ArchiveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TaskStore
    @ObservedObject var fontLibrary: FontLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("归档任务").font(fontLibrary.font(20, weight: .bold))
                Spacer()
                Button("完成") { dismiss() }
            }
            Text("已完成或已取消的任务可在这里恢复。")
                .font(fontLibrary.font(12)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let archived = store.tasks.filter { $0.status == .completed || $0.status == .cancelled }
                    if archived.isEmpty {
                        Text("暂无归档任务").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 45)
                    }
                    ForEach(archived) { task in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.title).font(fontLibrary.font(13))
                                Text("\(task.category) · \(task.status.title)").font(fontLibrary.font(11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("恢复") { store.setStatus(task, .todo) }
                        }
                        Divider()
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 390, height: 330)
    }
}

struct CategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TaskStore
    @Binding var chosenCategory: String
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("管理分组").font(.title3.bold())
            ForEach(store.categories, id: \.self) { category in
                HStack {
                    Text(category)
                    Spacer()
                    Button { 
                        store.removeCategory(category)
                        chosenCategory = store.categories.first ?? "收件箱"
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .disabled(store.categories.count <= 1)
                }
            }
            Divider()
            HStack {
                TextField("新分组名称", text: $name).onSubmit(add)
                Button("添加", action: add).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24)
        .frame(width: 320)
    }

    private func add() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        store.addCategory(clean)
        if store.categories.contains(clean) { chosenCategory = clean }
        name = ""
    }
}

struct ImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TaskStore
    @Binding var importedCount: Int?
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("批量导入待办").font(.title3.bold())
            Text("每行一项；用「# 分组名」指定分组。也支持 - [ ] 和 - [x] 清单格式。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .frame(height: 180)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.25)))
            HStack {
                Button("从剪贴板粘贴") { text = NSPasteboard.general.string(forType: .string) ?? "" }
                Spacer()
                Button("取消") { dismiss() }
                Button("导入") { importedCount = store.importText(text); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 430)
    }
}

enum WindowPolicy {
    static func apply(to panel: NSPanel, pinned: Bool) {
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.level = pinned ? .statusBar : .normal
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if #available(macOS 13.0, *) { behavior.insert(.canJoinAllApplications) }
        panel.collectionBehavior = behavior
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor final class AppController: NSObject, NSApplicationDelegate {
    private let store = TaskStore()
    private let fontLibrary = FontLibrary()
    private var reminders: RemindersSync!
    private lazy var goals = GoalStore(daily: store)
    private var goalsWindow: NSWindow?
    private var widget: FloatingPanel!
    private var orb: FloatingPanel!
    private var statusItem: NSStatusItem!
    #if MINT_WIDGET_TRIAL
    private var widgetTrial: MintWidgetTrialCoordinator?
    private var widgetPreviewWindow: NSWindow?
    private var receivedWidgetAction = false
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        #if MINT_WIDGET_TRIAL
        reminders = RemindersSync(tasks: store, allowSystemAccess: false)
        #else
        reminders = RemindersSync(tasks: store, allowSystemAccess: ProcessInfo.processInfo.environment["MINTTODO_TEST_MODE"] != "1")
        #endif
        _ = goals
        store.onChange = { [weak self] in
            self?.reminders.scheduleSync()
            self?.goals.reconcileTodos()
            #if MINT_WIDGET_TRIAL
            self?.widgetTrial?.refresh()
            #endif
        }
        goals.reconcileTodos()
        #if MINT_WIDGET_TRIAL
        goals.onChange = { [weak self] in self?.widgetTrial?.refresh() }
        widgetTrial = MintWidgetTrialCoordinator(daily: store, goals: goals)
        #endif
        makeWindows()
        makeMenuBar()
        #if MINT_WIDGET_TRIAL
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !self.receivedWidgetAction else { return }
            self.showWidget(); self.showWidgetPreview()
        }
        #else
        showWidget()
        #endif
        AppUpdater.shared.start()
    }

    #if MINT_WIDGET_TRIAL
    @objc private func showWidgetPreview() {
        guard let widgetTrial else { return }
        if widgetPreviewWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 788, height: 650),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Mint Todo · 桌面小组件试用版"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MintWidgetTrialPreview(coordinator: widgetTrial,
                showApp: { [weak self] in self?.showWidget() }, showGoals: { [weak self] in self?.openGoals(selected: nil) }))
            window.center(); widgetPreviewWindow = window
        }
        widgetPreviewWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first, url.scheme == "minttodo-widgets-trial" else { return }
        if url.host == "complete" {
            receivedWidgetAction = true
            guard let command = MintWidgetActionLink.command(from: url) else { return }
            if let widgetTrial { widgetTrial.submit(command) }
            else { try? MintWidgetFiles().enqueue(command) }
            return
        }
        widgetTrial?.refresh()
        switch url.host {
        case "today": showWidget()
        case "goals": openGoals(selected: nil)
        case "goal": openGoals(selected: UUID(uuidString: url.lastPathComponent))
        default: showWidgetPreview()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWidgetPreview()
        return true
    }
    #endif

    private func makeWindows() {
        let savedWidth = UserDefaults.standard.double(forKey: "widgetWidth")
        let savedHeight = UserDefaults.standard.double(forKey: "widgetHeight")
        let initialWidth = savedWidth > 0 ? max(320, savedWidth) : 405
        let initialHeight = savedHeight > 0 ? max(380, savedHeight) : 560
        widget = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        widget.minSize = NSSize(width: 320, height: 380)
        widget.isOpaque = false
        widget.backgroundColor = .clear
        widget.hasShadow = false
        widget.isMovableByWindowBackground = true
        WindowPolicy.apply(to: widget, pinned: UserDefaults.standard.object(forKey: "widgetPinned") as? Bool != false)
        widget.contentView = NSHostingView(rootView: WidgetView(
            store: store,
            fontLibrary: fontLibrary,
            reminderSync: reminders,
            goalStore: goals,
            onOpenGoal: { [weak self] id in self?.openGoals(selected: id) },
            onCollapse: { [weak self] in self?.showOrb() },
            onGoals: { [weak self] in self?.showGoals() },
            onPin: { [weak self] value in self?.setPinned(value) },
            onOpacity: { [weak self] value in self?.widget.alphaValue = value
                UserDefaults.standard.set(value, forKey: "widgetOpacity") },
            onResize: { [weak self] size in self?.resizeWidget(to: size) }
        ))
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        if let saved = UserDefaults.standard.string(forKey: "widgetTopLeft") {
            widget.setFrameTopLeftPoint(NSPointFromString(saved))
        } else {
            widget.setFrameTopLeftPoint(NSPoint(x: screen.maxX - 440, y: screen.maxY - 40))
        }
        widget.alphaValue = UserDefaults.standard.object(forKey: "widgetOpacity") as? Double ?? 0.94
        NotificationCenter.default.addObserver(self, selector: #selector(windowMoved), name: NSWindow.didMoveNotification, object: widget)
        NotificationCenter.default.addObserver(self, selector: #selector(windowResized), name: NSWindow.didResizeNotification, object: widget)

        orb = FloatingPanel(contentRect: NSRect(x: screen.maxX - 64, y: screen.minY + 12, width: CollapsedOrbView.hitSize, height: CollapsedOrbView.hitSize), styleMask: [.borderless], backing: .buffered, defer: false)
        orb.isOpaque = false
        orb.backgroundColor = .clear
        orb.hasShadow = false
        WindowPolicy.apply(to: orb, pinned: true)
        orb.contentView = NSHostingView(rootView: CollapsedOrbView { [weak self] in self?.showWidget() })
    }

    @objc private func windowMoved() {
        let point = NSPoint(x: widget.frame.minX, y: widget.frame.maxY)
        UserDefaults.standard.set(NSStringFromPoint(point), forKey: "widgetTopLeft")
    }

    @objc private func windowResized() {
        UserDefaults.standard.set(widget.frame.width, forKey: "widgetWidth")
        UserDefaults.standard.set(widget.frame.height, forKey: "widgetHeight")
    }

    private func resizeWidget(to requested: CGSize) {
        let screen = widget.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let width = min(max(320, requested.width), min(900, screen.width - 20))
        let height = min(max(380, requested.height), min(900, screen.height - 20))
        let top = min(widget.frame.maxY, screen.maxY)
        let origin = NSPoint(x: min(widget.frame.minX, screen.maxX - width), y: max(screen.minY, top - height))
        widget.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    }

    private func makeMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Mint Todo")
        let menu = NSMenu()
        #if MINT_WIDGET_TRIAL
        menu.addItem(withTitle: "桌面小组件试用与预览", action: #selector(showWidgetPreview), keyEquivalent: "p").target = self
        #endif
        menu.addItem(withTitle: "显示待办", action: #selector(showWidgetAction), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "收起为小圆点", action: #selector(showOrbAction), keyEquivalent: "h").target = self
        menu.addItem(withTitle: "我的目标", action: #selector(showGoals), keyEquivalent: "g").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "复制清单文本", action: #selector(copyList), keyEquivalent: "c").target = self
        menu.addItem(withTitle: "打开数据文件", action: #selector(openDataFile), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(withTitle: "退出 Mint Todo", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc private func showGoals() { openGoals(selected: nil) }

    private func openGoals(selected: UUID?) {
        if goalsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Mint Todo · 我的目标"
            window.minSize = NSSize(width: 960, height: 650)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: GoalsView(store: goals))
            window.setFrameAutosaveName("MintGoalsWindow")
            window.center()
            goalsWindow = window
        }
        if let selected { goalsWindow?.contentView = NSHostingView(rootView: GoalsView(store: goals, selectedGoal: selected)) }
        goalsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setPinned(_ pinned: Bool) {
        UserDefaults.standard.set(pinned, forKey: "widgetPinned")
        WindowPolicy.apply(to: widget, pinned: pinned)
        if widget.isVisible { widget.orderFrontRegardless() }
    }

    private func showWidget() {
        if orb.isVisible {
            let screen = orb.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? widget.frame
            widget.setFrame(WindowDockGeometry.expanded(from: orb.frame, size: widget.frame.size, screen: screen), display: true)
        }
        orb.orderOut(nil)
        setPinned(UserDefaults.standard.object(forKey: "widgetPinned") as? Bool != false)
        widget.makeKeyAndOrderFront(nil)
        widget.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
    private func showOrb() {
        let screen = widget.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? widget.frame
        let point = WindowDockGeometry.collapsed(from: widget.frame, screen: screen, size: CollapsedOrbView.hitSize)
        orb.setFrameOrigin(point)
        widget.orderOut(nil)
        orb.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showWidgetAction() { showWidget() }
    @objc private func showOrbAction() { showOrb() }
    @objc private func copyList() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.textExport(), forType: .string)
    }
    @objc private func openDataFile() { NSWorkspace.shared.activateFileViewerSelecting([store.fileURL]) }
    @objc private func checkForUpdates() { AppUpdater.shared.check() }
    @objc private func quit() { NSApp.terminate(nil) }
}

@main struct MintTodoMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let controller = AppController()
        app.delegate = controller
        app.run()
    }
}
