import SwiftUI
import WidgetKit
import CoreText

extension Color {
    fileprivate init(widgetHex: String) {
        let value = UInt64(widgetHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x71BDA3
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

private enum MintWidgetFonts {
    static let lock = NSLock()
    static var registered: Set<String> = []
    static func font(_ size: CGFloat, theme: MintWidgetTheme, weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        let scaled = size * min(max(theme.fontScale, 0.8), 1.18)
        if let name = theme.fontName, let file = theme.fontFile, file == URL(fileURLWithPath: file).lastPathComponent {
            lock.lock()
            if !registered.contains(file) {
                let url = MintWidgetFiles.defaultFolder.appendingPathComponent("Fonts/" + file)
                if CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) { registered.insert(file) }
            }
            lock.unlock()
            return .custom(name, size: scaled).weight(weight)
        }
        return .system(size: scaled, weight: weight, design: monospaced ? .monospaced : .default)
    }
}

struct MintWidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let theme: MintWidgetTheme
    var body: some View {
        let base = colorScheme == .dark && !theme.paperStyle ? Color(red: 0.12, green: 0.15, blue: 0.15) : Color(widgetHex: theme.background)
        LinearGradient(colors: [base, base.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topTrailing) {
                Circle().fill(Color(widgetHex: theme.accent).opacity(0.10)).frame(width: 140, height: 140).offset(x: 50, y: -55)
            }
    }
}

/// Both the native extension and the trial's preview window use these views.
struct MintWidgetCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let snapshot: MintWidgetSnapshot
    let size: MintWidgetSize
    var message: String? = nil
    var now = Date()
    var onComplete: ((MintWidgetCommand) -> Void)? = nil

    private var accent: Color { Color(widgetHex: snapshot.theme.accent) }
    private var today: [MintWidgetTask] { snapshot.todayTasks(now: now) }
    private var remaining: [MintWidgetTask] { today.filter { !$0.isCompleted } }
    private var done: Int { today.filter(\.isCompleted).count }
    private func font(_ size: CGFloat, weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        MintWidgetFonts.font(size, theme: snapshot.theme, weight: weight, monospaced: monospaced)
    }
    var body: some View {
        Group {
            if !snapshot.isReady {
                VStack(alignment: .leading, spacing: 10) {
                    wordmark
                    Spacer(minLength: 0)
                    Image(systemName: "leaf").font(.system(size: 25, weight: .light)).foregroundStyle(accent)
                    Text(message ?? "先打开试用版").font(font(12, weight: .medium))
                    Text("准备好数据后，小组件会自动显示。")
                        .font(font(10)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            } else {
                switch size {
                case .small: small
                case .medium: medium
                case .large: large
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, snapshot.theme.paperStyle ? .light : colorScheme)
    }

    private var wordmark: some View {
        HStack(spacing: 5) {
            Circle().fill(accent).frame(width: 5, height: 5)
            Text("MINT TODO").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.4)
        }.foregroundStyle(.secondary)
    }

    private var small: some View {
        let hasGoals = snapshot.goalTotal > 0
        let total = hasGoals ? snapshot.goalTotal : today.count
        let completed = hasGoals ? snapshot.goalCompleted : done
        let fraction = total == 0 ? 0 : Double(completed) / Double(total)
        return VStack(alignment: .leading, spacing: 7) {
            wordmark
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(accent.opacity(0.17), lineWidth: 7)
                    Circle().trim(from: 0, to: fraction)
                        .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(fraction * 100))%")
                        .font(font(17, weight: .semibold)).monospacedDigit().minimumScaleFactor(0.7)
                }.frame(width: 65, height: 65).padding(4)
                Spacer(minLength: 0)
            }
            Text(hasGoals ? "目标进度" : "今日进度").font(font(12, weight: .semibold))
            HStack(spacing: 3) {
                Text("\(completed)/\(total) 项").monospacedDigit()
                Spacer(minLength: 0)
                Text("待办 \(remaining.count)")
            }.font(font(9)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var medium: some View {
        let remaining = snapshot.allPendingTasks
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("全部待办").font(font(14, weight: .semibold))
                Spacer()
                Text("\(remaining.count) 项待完成").font(font(10)).foregroundStyle(.secondary)
            }
            if remaining.isEmpty {
                Spacer(minLength: 0)
                Label("全部待办完成啦", systemImage: "checkmark.circle")
                    .font(font(13)).foregroundStyle(accent)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(remaining.prefix(3))) { task in
                    HStack(spacing: 8) {
                        completionButton(id: task.id, isGoal: false, completed: false, title: task.title)
                        Text(task.title).font(font(12, monospaced: true)).lineLimit(1)
                        Spacer(minLength: 0)
                        if !task.subtasks.isEmpty {
                            Text("\(task.subtasks.filter(\.isCompleted).count)/\(task.subtasks.count)")
                                .font(font(9)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }.frame(minHeight: 18)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Text("今天已完成 \(done) 项").font(font(9)).foregroundStyle(.secondary)
                Spacer()
                Link(remaining.count > 3 ? "还有 \(remaining.count - 3) 项 →" : "查看全部 →", destination: URL(string: "minttodo-widgets-trial://all")!)
                    .font(font(9)).foregroundStyle(accent)
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    wordmark
                    Text("我的目标").font(font(17, weight: .semibold))
                }
                Spacer()
                Text("\(snapshot.activeGoals.count) 个进行中")
                    .font(font(10)).foregroundStyle(.secondary)
            }
            if snapshot.activeGoals.isEmpty {
                Spacer()
                Text("创建一个目标，从一件小事开始。")
                    .font(font(13)).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(snapshot.activeGoals.prefix(2))) { goal in
                    goalRow(goal)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Text("今日待办 \(remaining.count) 项").font(font(10)).foregroundStyle(.secondary)
                Spacer()
                Link(snapshot.activeGoals.count > 2 ? "更多目标 →" : "查看目标 →", destination: URL(string: "minttodo-widgets-trial://goals")!)
                    .font(font(10)).foregroundStyle(accent)
            }
        }
    }

    private func goalRow(_ goal: MintWidgetGoal) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Link(destination: URL(string: "minttodo-widgets-trial://goal/\(goal.id.uuidString)")!) {
                    Text(goal.title).font(font(13, weight: .semibold)).lineLimit(1)
                }.foregroundStyle(.primary)
                Spacer(minLength: 4)
                Text("\(goal.completed)/\(goal.tasks.count)")
                    .font(font(10)).foregroundStyle(.secondary).monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(widgetHex: goal.color).opacity(0.16))
                    Capsule().fill(Color(widgetHex: goal.color)).frame(width: geometry.size.width * goal.fraction)
                }
            }.frame(height: 4)
            if let phase = goal.currentPhase {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 9))
                    Text(phase.title).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(phase.completed)/\(phase.countedTasks.count)").monospacedDigit()
                }.font(font(9)).foregroundStyle(.secondary)
                if let task = phase.countedTasks.first(where: { !$0.isCompleted }) {
                    HStack(spacing: 7) {
                        completionButton(id: task.id, isGoal: true, completed: false, title: task.title)
                        Text(task.title).font(font(11, monospaced: true)).lineLimit(1)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(0.035)))
    }

    @ViewBuilder private func completionButton(id: UUID, isGoal: Bool, completed: Bool, title: String) -> some View {
        let command = MintWidgetCommand(target: isGoal ? .goal : .daily, taskID: id, completed: !completed)
        if let onComplete {
            Button { onComplete(command) } label: { completionSymbol(completed) }
                .buttonStyle(.plain).accessibilityLabel("完成：\(title)")
        } else {
            #if MINT_WIDGET_LOCAL_ACTIONS
            Link(destination: MintWidgetActionLink.url(target: isGoal ? .goal : .daily, taskID: id, completed: !completed)) {
                completionSymbol(completed)
            }.accessibilityLabel("完成：\(title)")
            #else
            Button(intent: CompleteMintTaskIntent(taskID: id, isGoal: isGoal, completed: !completed)) {
                completionSymbol(completed)
            }.buttonStyle(.plain).accessibilityLabel("完成：\(title)")
            #endif
        }
    }
    private func completionSymbol(_ completed: Bool) -> some View {
        Image(systemName: completed ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 15, weight: .light)).foregroundStyle(accent)
            .frame(width: 19, height: 19).contentShape(Rectangle())
    }
}
