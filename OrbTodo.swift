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

struct Todo: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var category: String
    var status: TaskStatus = .todo
    var createdAt: Date = Date()
    var dueAt: Date? = nil
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

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OrbTodo", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("tasks.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = Self.decode(data) {
            categories = saved.categories.isEmpty ? ["收件箱"] : saved.categories
            tasks = saved.tasks
        }
        if !FileManager.default.fileExists(atPath: fileURL.path) { save() }
        lastModified = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        watchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadIfChanged() }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(SavedData(categories: categories, tasks: tasks)) else { return }
        try? data.write(to: fileURL, options: .atomic)
        lastModified = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        onChange?()
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

    func applyReminderChanges(updates: [Todo], deletedIDs: Set<UUID>) {
        var changed = false
        for updated in updates {
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

    func update(_ task: Todo, title: String, category: String, dueAt: Date?) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let group = category.trimmingCharacters(in: .whitespacesAndNewlines)
        if !categories.contains(group) { categories.append(group) }
        tasks[index].title = clean
        tasks[index].category = group
        tasks[index].dueAt = dueAt
        save()
    }

    func setStatus(_ task: Todo, _ status: TaskStatus) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].status = status
        save()
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
                lines += group.map { "- \($0.title)" }
            }
            lines.append("")
        }
        return lines.isEmpty ? "待办清单为空" : lines.joined(separator: "\n")
    }

    @discardableResult func importText(_ text: String) -> Int {
        var category = categories.first ?? "收件箱"
        var status: TaskStatus = .todo
        var count = 0
        for raw in text.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("## ") {
                let heading = String(line.dropFirst(3))
                status = TaskStatus.allCases.first { $0.title == heading } ?? .todo
                continue
            }
            if line.hasPrefix("# ") {
                category = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !categories.contains(category) { categories.append(category) }
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
            tasks.append(Todo(title: line, category: category, status: itemStatus))
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

struct WidgetView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var fontLibrary: FontLibrary
    @ObservedObject var reminderSync: RemindersSync
    let onCollapse: () -> Void
    let onPin: (Bool) -> Void
    let onOpacity: (Double) -> Void
    let onResize: (CGSize) -> Void

    @State private var input = ""
    @State private var chosenCategory = "工作"
    @State private var editing: Todo?
    @State private var showImport = false
    @State private var showCategory = false
    @State private var showArchive = false
    @State private var showSettings = false
    @AppStorage("widgetPinned") private var pinned = true
    @AppStorage("widgetWidth") private var widgetWidth = 405.0
    @AppStorage("widgetHeight") private var widgetHeight = 560.0
    @State private var collapsedGroups: Set<String> = []
    @State private var importedCount: Int?
    @State private var resizeOrigin: CGSize?

    var body: some View {
        VStack(spacing: 0) {
            header
            statusBar
            Divider().opacity(0.36).padding(.horizontal, 21)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let visible = store.tasks.filter { $0.status == store.selectedStatus }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 320, minHeight: 380)
        .background {
            AppearanceBackground()
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.7), lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 25, y: 14)
        .sheet(item: $editing) { task in EditTaskSheet(store: store, fontLibrary: fontLibrary, task: task) }
        .sheet(isPresented: $showImport) { ImportSheet(store: store, importedCount: $importedCount) }
        .sheet(isPresented: $showCategory) { CategorySheet(store: store, chosenCategory: $chosenCategory) }
        .sheet(isPresented: $showArchive) { ArchiveSheet(store: store, fontLibrary: fontLibrary) }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                store: store,
                fontLibrary: fontLibrary,
                reminderSync: reminderSync,
                onOpacity: onOpacity,
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
        HStack(spacing: 10) {
            Spacer()
            Button { pinned.toggle(); onPin(pinned) } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .rotationEffect(.degrees(35))
            }
            .help(pinned ? "取消置顶" : "置顶")
            Button { showSettings = true } label: { Image(systemName: "gearshape").font(.system(size: 15)) }
                .help("设置")
            Button(action: onCollapse) { Image(systemName: "minus").font(.system(size: 16, weight: .semibold)) }
                .help("收起为小圆点")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 23)
        .frame(height: 48)
    }

    private var resizeHandle: some View {
        Text("↘")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color(red: 0.38, green: 0.41, blue: 0.55))
            .frame(width: 24, height: 24)
            .background(Circle().fill(.white.opacity(0.8)))
            .contentShape(Rectangle())
            .help("拖动调整窗口大小")
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if resizeOrigin == nil {
                        resizeOrigin = CGSize(width: widgetWidth, height: widgetHeight)
                    }
                    guard let origin = resizeOrigin else { return }
                    onResize(CGSize(width: origin.width + value.translation.width,
                                    height: origin.height + value.translation.height))
                }
                .onEnded { _ in resizeOrigin = nil })
    }

    private var statusBar: some View {
        HStack(spacing: 3) {
            ForEach([TaskStatus.todo, .pending]) { status in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { store.selectedStatus = status }
                } label: {
                    HStack(spacing: 4) {
                        Text(status.title)
                        let count = store.tasks.filter { $0.status == status }.count
                        if count > 0 { Text("\(count)").font(.system(size: 10, weight: .bold)).opacity(0.65) }
                    }
                    .font(fontLibrary.font(12, weight: store.selectedStatus == status ? .semibold : .medium))
                    .foregroundStyle(store.selectedStatus == status ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if store.selectedStatus == status {
                            RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.68))
                                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
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
        HStack(alignment: .top, spacing: 10) {
            Button {
                store.setStatus(task, task.status == .completed ? .todo : .completed)
            } label: {
                Image(systemName: task.status == .completed ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(task.status == .completed ? Color(red: 0.43, green: 0.5, blue: 0.83) : Color.secondary.opacity(0.65))
            }
            .buttonStyle(.plain)
            .help(task.status == .completed ? "恢复为待办" : "标记完成")
            Button { editing = task } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(fontLibrary.font(13.5, monospaced: true))
                        .strikethrough(task.status == .completed || task.status == .cancelled)
                    if let dueAt = task.dueAt {
                        Label(dueAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                            .font(fontLibrary.font(10))
                            .foregroundStyle(dueAt < Date() && task.status != .completed ? Color.red.opacity(0.8) : Color.secondary)
                    }
                }
                .foregroundStyle(task.status == .completed || task.status == .cancelled ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("编辑任务与截止时间")
            Menu {
                Button("编辑") { editing = task }
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
            .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 3)
        .padding(.vertical, 3)
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
                HStack(spacing: 4) {
                    Text(chosenCategory).lineLimit(1)
                    Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold))
                }
                .font(fontLibrary.font(11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 72)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            TextField("添加新待办…", text: $input)
                .font(fontLibrary.font(13, monospaced: true))
                .textFieldStyle(.plain)
                .onSubmit(addInput)
            Button(action: addInput) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(red: 0.37, green: 0.43, blue: 0.77))
            .help("添加待办")
        }
        .padding(.horizontal, 12)
        .frame(height: 43)
        .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.055)))
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 8)
        .overlay(alignment: .bottomTrailing) {
            resizeHandle
                .padding(.trailing, 7)
                .padding(.bottom, 4)
        }
    }

    private func addInput() {
        store.add(input, category: chosenCategory)
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

    init(store: TaskStore, fontLibrary: FontLibrary, task: Todo) {
        self.store = store
        self.fontLibrary = fontLibrary
        self.task = task
        _title = State(initialValue: task.title)
        _category = State(initialValue: task.category)
        _hasDueDate = State(initialValue: task.dueAt != nil)
        _dueAt = State(initialValue: task.dueAt ?? Date().addingTimeInterval(3600))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑待办").font(fontLibrary.font(20, weight: .bold))
            TextField("待办内容", text: $title)
                .font(fontLibrary.font(14))
            HStack {
                Text("分组")
                Picker("分组", selection: $category) {
                    ForEach(store.categories, id: \.self) { Text($0).tag($0) }
                }.labelsHidden()
            }
            Toggle("设置截止时间", isOn: $hasDueDate)
            if hasDueDate {
                DatePicker("截止时间", selection: $dueAt, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
            }
            HStack {
                Button("删除", role: .destructive) { store.delete(task); dismiss() }
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { store.update(task, title: title, category: category, dueAt: hasDueDate ? dueAt : nil); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 365)
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

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor final class AppController: NSObject, NSApplicationDelegate {
    private let store = TaskStore()
    private let fontLibrary = FontLibrary()
    private var reminders: RemindersSync!
    private var widget: FloatingPanel!
    private var orb: FloatingPanel!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        reminders = RemindersSync(tasks: store)
        store.onChange = { [weak self] in self?.reminders.scheduleSync() }
        makeWindows()
        makeMenuBar()
        showWidget()
    }

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
        widget.level = UserDefaults.standard.object(forKey: "widgetPinned") as? Bool == false ? .normal : .floating
        widget.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        widget.contentView = NSHostingView(rootView: WidgetView(
            store: store,
            fontLibrary: fontLibrary,
            reminderSync: reminders,
            onCollapse: { [weak self] in self?.showOrb() },
            onPin: { [weak self] value in self?.widget.level = value ? .floating : .normal },
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

        orb = FloatingPanel(contentRect: NSRect(x: screen.maxX - 42, y: screen.maxY - 42, width: 26, height: 26), styleMask: [.borderless], backing: .buffered, defer: false)
        orb.isOpaque = false
        orb.backgroundColor = .clear
        orb.hasShadow = false
        orb.level = .floating
        orb.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        orb.contentView = NSHostingView(rootView: Button { [weak self] in self?.showWidget() } label: {
            Circle()
                .fill(Color(red: 0.46, green: 0.48, blue: 0.64).opacity(0.48))
                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                .frame(width: 15, height: 15)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help("展开 Orb Todo"))
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
        statusItem.button?.image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Orb Todo")
        let menu = NSMenu()
        menu.addItem(withTitle: "显示待办", action: #selector(showWidgetAction), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "收起为小圆点", action: #selector(showOrbAction), keyEquivalent: "h").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "复制清单文本", action: #selector(copyList), keyEquivalent: "c").target = self
        menu.addItem(withTitle: "打开数据文件", action: #selector(openDataFile), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Orb Todo", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    private func showWidget() {
        orb.orderOut(nil)
        widget.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func showOrb() {
        let screen = widget.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? widget.frame
        let point = NSPoint(x: min(max(widget.frame.maxX - 28, screen.minX), screen.maxX - 26),
                            y: min(max(widget.frame.maxY - 28, screen.minY), screen.maxY - 26))
        orb.setFrameOrigin(point)
        widget.orderOut(nil)
        orb.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showWidgetAction() { showWidget() }
    @objc private func showOrbAction() { showOrb() }
    @objc private func copyList() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.textExport(), forType: .string)
    }
    @objc private func openDataFile() { NSWorkspace.shared.activateFileViewerSelecting([store.fileURL]) }
    @objc private func quit() { NSApp.terminate(nil) }
}

@main struct OrbTodoMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let controller = AppController()
        app.delegate = controller
        app.run()
    }
}
