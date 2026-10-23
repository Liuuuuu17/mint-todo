import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    let controller: SPUStandardUpdaterController
    @Published private(set) var canCheck = false
    private var observations: [NSKeyValueObservation] = []
    private var started = false

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        observations.append(controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async { self?.canCheck = updater.canCheckForUpdates }
        })
        observations.append(controller.updater.observe(\.lastUpdateCheckDate, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        })
    }
    func start() {
        guard !started else { return }
        if ProcessInfo.processInfo.environment["MINTTODO_TEST_MODE"] == "1" && ProcessInfo.processInfo.environment["MINTTODO_TEST_UPDATES"] != "1" { return }
        started = true
        controller.startUpdater()
        if controller.updater.automaticallyChecksForUpdates { controller.updater.checkForUpdatesInBackground() }
    }
    func check() { guard canCheck else { return }; controller.checkForUpdates(nil) }
    var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { objectWillChange.send(); controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var installsAutomatically: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { objectWillChange.send(); controller.updater.automaticallyDownloadsUpdates = newValue }
    }
    var lastCheck: Date? { controller.updater.lastUpdateCheckDate }
}

struct UpdateSettings: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var updater = AppUpdater.shared
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("软件更新").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("Mint Todo \(version)").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("检查更新…") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { updater.check() }
                }.disabled(!updater.canCheck)
            }
            Toggle("自动检查更新", isOn: Binding(get: { updater.checksAutomatically }, set: { updater.checksAutomatically = $0 }))
            Toggle("自动下载并在退出后安装", isOn: Binding(get: { updater.installsAutomatically }, set: { updater.installsAutomatically = $0 }))
                .disabled(!updater.checksAutomatically)
            Text("从 Mint Todo 官方 GitHub 发布下载，验证签名后更新；任务和设置保留。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            if let date = updater.lastCheck {
                Text("上次检查：\(date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Link("查看版本与下载", destination: URL(string: "https://github.com/Liuuuuu17/mint-todo/releases/latest")!)
                .font(.system(size: 11))
        }.font(.system(size: 12))
    }
}
