import AppKit
import SwiftUI

/// The compact widget's third tab shares the existing goal store and import pipeline.
struct LongTermTasksView: View {
    @ObservedObject var store: GoalStore
    let onOpenGoal: (UUID) -> Void
    let onOpenAll: () -> Void
    private struct ImportRequest: Identifiable {
        let id = UUID()
        let text: String
        let parse: Bool
    }
    @State private var importRequest: ImportRequest?
    @State private var revision: Goal?
    @State private var generate = false
    @State private var settings = false
    @State private var manual: Goal?
    @State private var filter = "active"
    @State private var notice = ""

    private var visible: [Goal] {
        store.goals.filter { filter == "all" || ![.completed, .cancelled, .archived].contains($0.state) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("把目标变成可以执行的计划").font(.system(size: 14, weight: .semibold))
                Text("复制提示词给 AI → 复制它返回的计划 → 在这里粘贴解析。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("复制 AI 提示词") { AISettings.copyPrompt(); notice = "提示词已复制。交给 AI 后，把返回的完整 JSON 复制回来解析。" }
                    Spacer(minLength: 4)
                    Button("AI 生成") { generate = true }
                }
                HStack {
                    Button("粘贴并解析") {
                        importRequest = ImportRequest(text: NSPasteboard.general.string(forType: .string) ?? "", parse: true)
                    }.buttonStyle(.plain).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.black))
                    Button("导入 JSON…") { importRequest = ImportRequest(text: "", parse: false) }
                    Spacer(minLength: 0)
                    Menu {
                        Button("手动创建计划") { manual = Goal() }
                        Button("AI 设置与模型") { settings = true }
                        Button("打开完整规划窗口") { onOpenAll() }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                    .help("创建计划、AI 设置及完整规划窗口")
                }
                if !notice.isEmpty { Text(notice).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.font(.system(size: 11)).buttonStyle(.bordered)
            HStack {
                Text("我的计划").font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker("显示计划", selection: $filter) { Text("进行中").tag("active"); Text("全部").tag("all") }
                    .labelsHidden().frame(width: 100).controlSize(.small)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if visible.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "list.bullet.rectangle").font(.system(size: 25, weight: .light))
                            Text("还没有长期任务").font(.system(size: 13, weight: .medium))
                            Text("导入后会显示阶段和进度。点击计划可编辑内容、细化任务，或加入日常待办。")
                                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                    ForEach(visible) { goal in
                        Button { onOpenGoal(goal.id) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(alignment: .top) {
                                    Text(goal.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                                    Spacer(minLength: 6)
                                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Text("\(goal.term.title) · \(goal.state.title)").font(.system(size: 10)).foregroundStyle(.secondary)
                                ProgressView(value: goal.progress.fraction).tint(.primary)
                                HStack {
                                    Text(goal.progress.label)
                                    Spacer()
                                    if let due = goal.dueDate { Text(due) }
                                }.font(.system(size: 10)).foregroundStyle(.secondary)
                                if let phase = goal.currentPhase { Text("当前：\(phase)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                                Text("查看阶段 · 编辑计划 · AI 细化任务").font(.system(size: 10)).foregroundStyle(.secondary)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(0.035)))
                        }.buttonStyle(.plain)
                        Button("AI 修改这个计划") { revision = goal }.font(.system(size: 11))
                    }
                }
            }
            if store.recoveryRequired { Button("打开规划窗口恢复备份") { onOpenAll() }.font(.caption) }
        }.padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $importRequest) { request in PlanImportView(store: store, initialText: request.text, parseImmediately: request.parse) }
        .sheet(item: $revision) { goal in PlanRevisionView(store: store, original: goal) }
        .sheet(isPresented: $generate) { AIPlanGeneratorView(store: store) }
        .sheet(isPresented: $settings) { AISettingsView() }
        .sheet(item: $manual) { goal in GoalEditorView(initial: goal, heading: "创建长期任务", store: store, isNew: true) }
        .alert("计划保存提示", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}
