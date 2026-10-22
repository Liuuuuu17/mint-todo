import EventKit
import SwiftUI

struct ReminderList: Identifiable, Hashable {
    let id: String
    let title: String
}

private struct ReminderLink: Codable {
    var localID: UUID
    var remoteID: String
    var localSignature: String
    var remoteSignature: String
}

private struct ReminderLinks: Codable {
    var byList: [String: [ReminderLink]] = [:]
}

@MainActor final class RemindersSync: ObservableObject {
    @Published private(set) var lists: [ReminderList] = []
    @Published private(set) var hasAccess = false
    @Published private(set) var enabled: Bool
    @Published private(set) var selectedListID: String
    @Published private(set) var status = "未连接提醒事项"

    private let eventStore = EKEventStore()
    private let tasks: TaskStore
    private let linksURL: URL
    private var links: ReminderLinks
    private var timer: Timer?
    private var changeObserver: NSObjectProtocol?
    private var syncing = false
    private var pending = false

    init(tasks: TaskStore) {
        self.tasks = tasks
        enabled = UserDefaults.standard.bool(forKey: "remindersSyncEnabled")
        selectedListID = UserDefaults.standard.string(forKey: "remindersListID") ?? ""
        linksURL = tasks.fileURL.deletingLastPathComponent().appendingPathComponent("reminder-links.json")
        if let data = try? Data(contentsOf: linksURL), let saved = try? JSONDecoder().decode(ReminderLinks.self, from: data) {
            links = saved
        } else {
            links = ReminderLinks()
        }
        refreshAccess()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scheduleSync() }
        }
        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleSync() }
        }
    }

    deinit {
        timer?.invalidate()
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    private func refreshAccess() {
        let authorization = EKEventStore.authorizationStatus(for: .reminder)
        if #available(macOS 14.0, *) {
            hasAccess = authorization == .fullAccess
        } else {
            hasAccess = authorization == .authorized
        }
        if hasAccess {
            refreshLists()
            if enabled { scheduleSync() }
        } else {
            status = authorization == .denied ? "提醒事项权限已关闭，请在系统设置中允许。" : "连接后选择要同步的提醒事项列表。"
        }
    }

    func requestAccess() {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToReminders { [weak self] granted, error in
                Task { @MainActor in self?.accessFinished(granted: granted, error: error) }
            }
        } else {
            eventStore.requestAccess(to: .reminder) { [weak self] granted, error in
                Task { @MainActor in self?.accessFinished(granted: granted, error: error) }
            }
        }
    }

    private func accessFinished(granted: Bool, error: Error?) {
        hasAccess = granted
        if granted {
            refreshLists()
            status = "已连接。请选择一个列表，再打开双向同步。"
        } else {
            status = error.map { "连接失败：\($0.localizedDescription)" } ?? "没有获得提醒事项权限。"
        }
    }

    func refreshLists() {
        guard hasAccess else { return }
        lists = eventStore.calendars(for: .reminder)
            .map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        if !selectedListID.isEmpty && !lists.contains(where: { $0.id == selectedListID }) {
            selectedListID = ""
            enabled = false
            UserDefaults.standard.set(false, forKey: "remindersSyncEnabled")
            status = "原来的提醒事项列表已不可用，请重新选择。"
        }
    }

    func chooseList(_ id: String) {
        selectedListID = id
        UserDefaults.standard.set(id, forKey: "remindersListID")
        if enabled { scheduleSync() }
    }

    func setEnabled(_ value: Bool) {
        guard !value || (hasAccess && !selectedListID.isEmpty) else { return }
        enabled = value
        UserDefaults.standard.set(value, forKey: "remindersSyncEnabled")
        status = value ? "正在双向同步…" : "同步已暂停，本机任务和提醒事项都保留。"
        if value { scheduleSync() }
    }

    func scheduleSync() {
        guard enabled, hasAccess, !selectedListID.isEmpty else { return }
        if syncing { pending = true; return }
        guard let calendar = eventStore.calendar(withIdentifier: selectedListID), calendar.allowsContentModifications else {
            status = "所选列表不可写，请换一个提醒事项列表。"
            return
        }
        syncing = true
        let predicate = eventStore.predicateForReminders(in: [calendar])
        eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
            Task { @MainActor in
                guard let self else { return }
                if let reminders {
                    self.reconcile(reminders, calendar: calendar)
                } else {
                    self.status = "读取提醒事项失败，请稍后重试。"
                }
                self.syncing = false
                if self.pending {
                    self.pending = false
                    self.scheduleSync()
                }
            }
        }
    }

    private func localSignature(_ task: Todo) -> String {
        "\(task.title)\u{1F}\(task.status.rawValue)\u{1F}\(task.dueAt?.timeIntervalSince1970 ?? -1)"
    }

    private func dueDate(_ reminder: EKReminder) -> Date? {
        reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
    }

    private func remoteSignature(_ reminder: EKReminder) -> String {
        "\(reminder.title ?? "")\u{1F}\(reminder.isCompleted)\u{1F}\(dueDate(reminder)?.timeIntervalSince1970 ?? -1)"
    }

    private func sameContent(_ task: Todo, _ reminder: EKReminder) -> Bool {
        let sameDate: Bool
        if let localDate = task.dueAt, let remoteDate = dueDate(reminder) {
            sameDate = abs(localDate.timeIntervalSince(remoteDate)) < 60
        } else {
            sameDate = task.dueAt == nil && dueDate(reminder) == nil
        }
        return task.title == (reminder.title ?? "") && sameDate
            && (task.status == .completed || task.status == .cancelled) == reminder.isCompleted
    }

    private func copy(_ task: Todo, to reminder: EKReminder) throws {
        reminder.title = task.title
        reminder.isCompleted = task.status == .completed || task.status == .cancelled
        reminder.dueDateComponents = task.dueAt.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
        try eventStore.save(reminder, commit: true)
    }

    private func copy(_ reminder: EKReminder, to task: Todo) -> Todo {
        var updated = task
        updated.title = reminder.title ?? task.title
        updated.dueAt = dueDate(reminder)
        updated.status = reminder.isCompleted ? .completed : (task.status == .pending ? .pending : .todo)
        return updated
    }

    private func reconcile(_ reminders: [EKReminder], calendar: EKCalendar) {
        var remote: [String: EKReminder] = Dictionary(uniqueKeysWithValues: reminders.map { ($0.calendarItemIdentifier, $0) })
        var local = Dictionary(uniqueKeysWithValues: tasks.tasks.map { ($0.id, $0) })
        var nextLinks: [ReminderLink] = []
        var updates: [Todo] = []
        var deleted: Set<UUID> = []
        var failures = 0

        for link in links.byList[selectedListID] ?? [] {
            let task = local.removeValue(forKey: link.localID)
            let reminder = remote.removeValue(forKey: link.remoteID)
            switch (task, reminder) {
            case let (task?, reminder?):
                let localChanged = localSignature(task) != link.localSignature
                let remoteChanged = remoteSignature(reminder) != link.remoteSignature
                var result = task
                if localChanged && !remoteChanged {
                    do { try copy(task, to: reminder) }
                    catch { failures += 1; nextLinks.append(link); continue }
                } else if remoteChanged {
                    result = copy(reminder, to: task)
                    if result != task { updates.append(result) }
                }
                nextLinks.append(ReminderLink(localID: task.id, remoteID: reminder.calendarItemIdentifier,
                                              localSignature: localSignature(result), remoteSignature: remoteSignature(reminder)))
            case let (nil, reminder?):
                do { try eventStore.remove(reminder, commit: true) }
                catch { failures += 1; nextLinks.append(link) }
            case let (task?, nil):
                deleted.insert(task.id)
            case (nil, nil):
                break
            }
        }

        for reminder in remote.values {
            let remoteID = reminder.calendarItemIdentifier
            if let matching = local.values.first(where: { sameContent($0, reminder) }) {
                local.removeValue(forKey: matching.id)
                nextLinks.append(ReminderLink(localID: matching.id, remoteID: remoteID,
                                              localSignature: localSignature(matching), remoteSignature: remoteSignature(reminder)))
            } else {
                let task = Todo(title: reminder.title ?? "未命名提醒", category: "提醒事项",
                                status: reminder.isCompleted ? .completed : .todo, dueAt: dueDate(reminder))
                updates.append(task)
                nextLinks.append(ReminderLink(localID: task.id, remoteID: remoteID,
                                              localSignature: localSignature(task), remoteSignature: remoteSignature(reminder)))
            }
        }

        for task in local.values where !deleted.contains(task.id) {
            let reminder = EKReminder(eventStore: eventStore)
            reminder.calendar = calendar
            do {
                try copy(task, to: reminder)
                let remoteID = reminder.calendarItemIdentifier
                if !remoteID.isEmpty {
                    nextLinks.append(ReminderLink(localID: task.id, remoteID: remoteID,
                                                  localSignature: localSignature(task), remoteSignature: remoteSignature(reminder)))
                }
            } catch { failures += 1 }
        }

        tasks.applyReminderChanges(updates: updates, deletedIDs: deleted)
        links.byList[selectedListID] = nextLinks
        if let data = try? JSONEncoder().encode(links) { try? data.write(to: linksURL, options: .atomic) }
        status = failures == 0 ? "已同步 · \(nextLinks.count) 项" : "同步了 \(nextLinks.count) 项，\(failures) 项失败；稍后会重试。"
    }
}

struct RemindersSettings: View {
    @ObservedObject var sync: RemindersSync

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("苹果提醒事项").font(.system(size: 14, weight: .semibold))
            if !sync.hasAccess {
                Button("连接提醒事项…") { sync.requestAccess() }
            } else {
                Picker("同步列表", selection: Binding(
                    get: { sync.selectedListID },
                    set: { sync.chooseList($0) }
                )) {
                    Text("选择一个列表").tag("")
                    ForEach(sync.lists) { list in Text(list.title).tag(list.id) }
                }
                HStack {
                    Toggle("双向同步", isOn: Binding(get: { sync.enabled }, set: { sync.setEnabled($0) }))
                        .disabled(sync.selectedListID.isEmpty)
                    Spacer()
                    Button("立即同步") { sync.scheduleSync() }
                        .disabled(!sync.enabled)
                }
            }
            Text(sync.status).font(.system(size: 11)).foregroundStyle(.secondary)
            Text("只同步你选择的列表；新增、编辑、完成和删除会同步到两边。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
