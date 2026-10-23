import EventKit
import SwiftUI

struct ReminderList: Identifiable, Hashable {
    let id: String
    let title: String
    let account: String
    let isLocal: Bool
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
    @Published private(set) var canCreateLocalList = false
    @Published private(set) var status = "未连接提醒事项"

    private let eventStore: EKEventStore
    private let preferences: UserDefaults
    private let tasks: TaskStore
    private let linksURL: URL
    private var links: ReminderLinks
    private var timer: Timer?
    private var changeObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    private var fetchTimer: Timer?
    private var fetchRequest: Any?
    private var fetchToken: UUID?
    private let allowSystemAccess: Bool
    private var syncing = false
    private var pending = false

    init(tasks: TaskStore, allowSystemAccess: Bool = true, preferences: UserDefaults = .standard, eventStore: EKEventStore = EKEventStore()) {
        self.tasks = tasks
        self.preferences = preferences
        self.eventStore = eventStore
        self.allowSystemAccess = allowSystemAccess
        enabled = preferences.bool(forKey: "remindersSyncEnabled")
        selectedListID = preferences.string(forKey: "remindersListID") ?? ""
        linksURL = tasks.fileURL.deletingLastPathComponent().appendingPathComponent("reminder-links.json")
        if let data = try? Data(contentsOf: linksURL), let saved = try? JSONDecoder().decode(ReminderLinks.self, from: data) {
            links = saved
        } else {
            links = ReminderLinks()
        }
        guard allowSystemAccess else { enabled = false; return }
        refreshAccess()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshConnection() }
        }
        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshConnection() }
        }
        activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshConnection() }
        }
    }

    deinit {
        timer?.invalidate()
        fetchTimer?.invalidate()
        if let fetchRequest { eventStore.cancelFetchRequest(fetchRequest) }
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    func refreshConnection() {
        guard allowSystemAccess else { return }
        refreshAccess()
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
            cancelFetch()
            lists = []
            canCreateLocalList = false
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
            if !lists.isEmpty { status = "已连接。请选择一个列表，再打开双向同步。" }
        } else {
            status = error.map { "连接失败：\($0.localizedDescription)" } ?? "没有获得提醒事项权限。"
        }
    }

    func refreshLists() {
        guard hasAccess else { return }
        canCreateLocalList = eventStore.sources.contains { $0.sourceType == .local }
        lists = eventStore.calendars(for: .reminder)
            .filter { $0.allowsContentModifications }
            .map { ReminderList(id: $0.calendarIdentifier, title: $0.title,
                               account: $0.source.title, isLocal: $0.source.sourceType == .local) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        if !selectedListID.isEmpty && !lists.contains(where: { $0.id == selectedListID }) {
            cancelFetch()
            enabled = false
            preferences.set(false, forKey: "remindersSyncEnabled")
            status = "所选列表暂不可用。请刷新或重新选择；本机待办和同步记录均保留。"
        } else if lists.isEmpty {
            status = canCreateLocalList
                ? "还没有可写列表。可以创建本机列表，无需开启 iCloud。"
                : "系统未提供可写的提醒事项列表或本机存储。请先在苹果提醒事项中确认可用列表，再点刷新连接；Mint Todo 本身无需 iCloud。"
        }
    }

    func createLocalList() {
        guard hasAccess, let source = eventStore.sources.first(where: { $0.sourceType == .local }) else {
            status = "当前系统没有提供本机提醒事项存储。Mint Todo 不能绕过系统创建本机账户。"
            return
        }
        do {
            let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
            calendar.source = source
            calendar.title = "Mint Todo"
            try eventStore.saveCalendar(calendar, commit: true)
            refreshLists()
            chooseList(calendar.calendarIdentifier)
            status = "已创建本机列表 Mint Todo。打开双向同步后开始同步。"
        } catch { status = "无法创建本机列表：\(error.localizedDescription)" }
    }

    private func cancelFetch() {
        fetchToken = nil
        fetchTimer?.invalidate()
        fetchTimer = nil
        if let fetchRequest { eventStore.cancelFetchRequest(fetchRequest) }
        fetchRequest = nil
        syncing = false
        pending = false
    }

    func chooseList(_ id: String) {
        cancelFetch()
        selectedListID = id
        preferences.set(id, forKey: "remindersListID")
        if enabled { scheduleSync() }
    }

    func setEnabled(_ value: Bool) {
        guard !value || (hasAccess && !selectedListID.isEmpty) else { return }
        if !value { cancelFetch() }
        enabled = value
        preferences.set(value, forKey: "remindersSyncEnabled")
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
        // Capture the list and generation: an old callback must never reconcile a newly selected list.
        let listID = selectedListID
        let token = UUID()
        fetchToken = token
        syncing = true
        status = "正在双向同步…"
        fetchTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.fetchToken == token else { return }
                self.cancelFetch()
                self.status = "读取提醒事项超时，本机待办已保留。请点刷新连接后重试。"
            }
        }
        let predicate = eventStore.predicateForReminders(in: [calendar])
        fetchRequest = eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
            Task { @MainActor in
                guard let self, self.fetchToken == token else { return }
                self.fetchTimer?.invalidate()
                self.fetchTimer = nil
                self.fetchRequest = nil
                let authorization = EKEventStore.authorizationStatus(for: .reminder)
                let authorized: Bool
                if #available(macOS 14.0, *) { authorized = authorization == .fullAccess }
                else { authorized = authorization == .authorized }
                if authorized, self.enabled, self.selectedListID == listID,
                   self.eventStore.calendar(withIdentifier: listID)?.allowsContentModifications == true {
                    if let reminders { self.reconcile(reminders, calendar: calendar, listID: listID) }
                    else { self.status = "读取提醒事项失败，本机待办已保留。请刷新连接后重试。" }
                }
                self.fetchToken = nil
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

    private func reconcile(_ reminders: [EKReminder], calendar: EKCalendar, listID: String) {
        var remote: [String: EKReminder] = Dictionary(uniqueKeysWithValues: reminders.map { ($0.calendarItemIdentifier, $0) })
        var local = Dictionary(uniqueKeysWithValues: tasks.tasks.map { ($0.id, $0) })
        var nextLinks: [ReminderLink] = []
        var updates: [Todo] = []
        var deleted: Set<UUID> = []
        var failures = 0

        for link in links.byList[listID] ?? [] {
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

        guard tasks.applyReminderChanges(updates: updates, deletedIDs: deleted) else {
            status = "本机待办保存失败，同步记录未推进。请检查磁盘空间后重试。"
            return
        }
        links.byList[listID] = nextLinks
        do { try JSONEncoder().encode(links).write(to: linksURL, options: .atomic) }
        catch { status = "任务已同步，但同步记录保存失败：\(error.localizedDescription)"; return }
        status = failures == 0 ? "已同步 · \(nextLinks.count) 项" : "同步了 \(nextLinks.count) 项，\(failures) 项失败；稍后会重试。"
    }
}

struct RemindersSettings: View {
    @ObservedObject var sync: RemindersSync

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("苹果提醒事项").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("刷新连接") { sync.refreshConnection() }
            }
            if !sync.hasAccess {
                Button("连接提醒事项…") { sync.requestAccess() }
            } else {
                Picker("同步列表", selection: Binding(
                    get: { sync.selectedListID },
                    set: { sync.chooseList($0) }
                )) {
                    Text("选择一个列表").tag("")
                    ForEach(sync.lists) { list in Text("\(list.title) · \(list.isLocal ? "本机" : list.account)").tag(list.id) }
                }
                if sync.canCreateLocalList {
                    Button("创建本机 Mint Todo 列表") { sync.createLocalList() }
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
            Text("不强制使用 iCloud；可选择系统提供的本机或其他账户列表。只同步所选列表，新增、编辑、完成和删除会同步到两边。截止时间会同步，但通知由苹果提醒事项管理。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .onAppear { sync.refreshConnection() }
    }
}
