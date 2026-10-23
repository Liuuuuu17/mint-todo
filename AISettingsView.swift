import AppKit
import SwiftUI

enum AISettings {
    static var configuration: AIConfiguration { AIConfiguration(baseURL: UserDefaults.standard.string(forKey: "aiBaseURL") ?? "", model: UserDefaults.standard.string(forKey: "aiModel") ?? "") }
    static var prompt: String { UserDefaults.standard.string(forKey: "aiPlanPrompt") ?? PlanPrompt.standard }
    static func copyPrompt() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(prompt + "\n\n" + PlanPrompt.contract, forType: .string) }
}
struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var base = AISettings.configuration.baseURL
    @State private var model = AISettings.configuration.model
    @State private var key = ""
    @State private var models: [String] = []
    @State private var prompt = AISettings.prompt
    @State private var status = ""
    @State private var operation: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("AI 设置").font(.title2.bold()); Spacer(); Button("完成") { dismiss() } }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("填写你使用的 Chat Completions 兼容服务。只有点击拉取模型、生成、细化或测试连接时才会发送请求。")
                        .font(.callout).foregroundStyle(.secondary)
                    TextField("API Base URL（HTTPS）", text: $base).disabled(operation != nil)
                    Text( (try? AIConfiguration.endpoint(base).absoluteString) ?? "示例路径：服务根地址 → /v1/chat/completions；/v1 → /v1/chat/completions")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    SecureField("新的 API Key（留空保留已保存的密钥）", text: $key).disabled(operation != nil)
                    HStack {
                        Button("拉取模型") { fetchModels() }.disabled(operation != nil || base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if operation != nil { ProgressView().controlSize(.small) }
                        Text("填写 URL 和 Key 后获取可选模型").font(.caption).foregroundStyle(.secondary)
                    }
                    if !models.isEmpty {
                        Picker("选择模型", selection: $model) {
                            if !models.contains(model) { Text(model.isEmpty ? "请选择模型" : "\(model)（手动输入）").tag(model) }
                            ForEach(models, id: \.self) { Text($0).tag($0) }
                        }.disabled(operation != nil)
                    }
                    TextField("模型名称（也可手动填写）", text: $model).disabled(operation != nil)
                    Text("拉取结果可能包含非聊天模型；选好后可测试连接。服务不支持列表时可手动填写。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("保存设置与密钥") { save() }.disabled(operation != nil)
                        Button("测试连接") { test() }.disabled(operation != nil)
                        Button("清除密钥", role: .destructive) { do { try AIKeychain().clear(); key = ""; status = "密钥已从钥匙串清除。" } catch { status = error.localizedDescription } }.disabled(operation != nil)
                        if operation != nil { Button("取消") { operation?.cancel() } }
                    }
                    Text(status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    Divider()
                    HStack { Text("计划提示词").font(.headline); Spacer(); Button("复制") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(prompt + "\n\n" + PlanPrompt.contract, forType: .string) }; Button("保存提示词") { UserDefaults.standard.set(prompt, forKey: "aiPlanPrompt"); status = "提示词已保存。" }; Button("恢复默认") { prompt = PlanPrompt.standard } }
                    TextEditor(text: $prompt).font(.system(size: 12, design: .monospaced)).frame(height: 230).border(.secondary.opacity(0.15))
                    Text("自定义提示词不会修改导入协议；API Key 只保存在 macOS 钥匙串。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(24).frame(width: 660, height: 600)
        .onDisappear { operation?.cancel() }
        .onChange(of: base) { _ in models = [] }
        .onChange(of: key) { _ in models = [] }
    }
    private func fetchModels() {
        let requestBase = base
        let requestKey: String?
        do {
            _ = try AIConfiguration.modelsEndpoint(requestBase)
            if !key.isEmpty { requestKey = key }
            else {
                guard try AIConfiguration.endpoint(requestBase) == AIConfiguration.endpoint(AISettings.configuration.baseURL) else {
                    throw PlanFailure("服务地址已更改，请填写该地址对应的 API Key 后再拉取。")
                }
                requestKey = try AIKeychain().read()
            }
        } catch { status = error.localizedDescription; return }
        models = []
        status = "正在拉取模型…"
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                models = try await AIClient().models(baseURL: requestBase, key: requestKey)
                if model.isEmpty { model = models[0] }
                status = "已获取 \(models.count) 个模型。选择后点“保存设置与密钥”。"
            } catch is CancellationError { status = "已取消拉取，输入内容已保留。" }
            catch { status = error.localizedDescription }
        }
    }
    @discardableResult private func save() -> Bool {
        do {
            _ = try AIConfiguration.endpoint(base)
            guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PlanFailure("请填写模型名称。") }
            if !key.isEmpty { try AIKeychain().save(key); key = "" }
            UserDefaults.standard.set(base, forKey: "aiBaseURL"); UserDefaults.standard.set(model, forKey: "aiModel")
            UserDefaults.standard.set(prompt, forKey: "aiPlanPrompt")
            status = "设置已保存，密钥保留在系统钥匙串。"; return true
        } catch { status = error.localizedDescription; return false }
    }
    private func test() {
        guard save() else { return }
        status = "正在测试（只发送一条简短测试消息）…"
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                _ = try await AIClient().complete(config: AISettings.configuration, key: AIKeychain().read(), system: "Reply with OK.", user: "Connection test.")
                status = "连接成功。"
            } catch is CancellationError { status = "已取消。" }
            catch { status = error.localizedDescription }
        }
    }
}
struct AIPlanGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: GoalStore
    @State private var title = ""
    @State private var details = ""
    @State private var start = ""
    @State private var due = ""
    @State private var hours = ""
    @State private var experience = ""
    @State private var constraints = ""
    @State private var detailLevel = "详细"
    @State private var status = ""
    @State private var output: Goal?
    @State private var operation: Task<Void, Never>?
    @State private var settings = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("AI 生成计划").font(.title2.bold()); Spacer(); Button("AI 设置") { settings = true }; Button("关闭") { dismiss() } }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("总目标", text: $title)
                    Text("背景与目标描述").font(.headline)
                    TextEditor(text: $details).frame(height: 100).border(.secondary.opacity(0.15))
                    HStack { TextField("开始日期 YYYY-MM-DD（可空）", text: $start); TextField("截止日期（可空）", text: $due) }
                    TextField("每周可用时间（可空，例如 6 小时）", text: $hours)
                    TextField("当前经验或基础（可空）", text: $experience)
                    TextField("特殊限制（可空）", text: $constraints)
                    Picker("说明详略", selection: $detailLevel) { Text("详细").tag("详细"); Text("简洁").tag("简洁") }.pickerStyle(.segmented)
                    Text("点击生成后，上述输入会发送到你配置的服务。返回计划会先进入可编辑预览，确认后才保存。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("生成计划") { generate() }.disabled(operation != nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if operation != nil { ProgressView().controlSize(.small); Button("取消生成") { operation?.cancel() } }
                        Button("复制 AI 提示词") { AISettings.copyPrompt() }
                    }
                    Text(status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }.padding(24).frame(width: 680, height: 650)
        .sheet(isPresented: $settings) { AISettingsView() }
        .sheet(item: $output) { goal in GoalEditorView(initial: goal, heading: "AI 计划预览", store: store, isNew: true, onSaved: { dismiss() }) }
        .onDisappear { operation?.cancel() }
    }
    private func generate() {
        for value in [start, due] where !value.isEmpty && PlanDate.parse(value) == nil { status = "日期应为 YYYY-MM-DD，未确定可留空。"; return }
        if !start.isEmpty && !due.isEmpty && start > due { status = "开始日期不能晚于截止日期。"; return }
        status = "正在生成，请稍候…"
        let input = "目标：\(title)\n背景：\(details)\n开始：\(start.isEmpty ? "未知" : start)\n截止：\(due.isEmpty ? "未知" : due)\n每周时间：\(hours)\n经验：\(experience)\n限制：\(constraints)\n详略：\(detailLevel)"
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                let text = try await AIClient().complete(config: AISettings.configuration, key: AIKeychain().read(), system: AISettings.prompt + "\n" + PlanPrompt.contract, user: input)
                var proposed = try PlanCodec.parse(text).goal
                proposed.dateOrigin = start.isEmpty && due.isEmpty ? .suggested : .personal
                for p in proposed.phases.indices {
                    proposed.phases[p].dateOrigin = .suggested
                    for t in proposed.phases[p].tasks.indices { proposed.phases[p].tasks[t].dateOrigin = .suggested }
                }
                output = proposed; status = "已生成，等待预览确认。AI 日期均为建议，可在预览里修改。"
            } catch is CancellationError { status = "已取消，输入内容已保留。" }
            catch { status = error.localizedDescription }
        }
    }
}
struct TaskRefinementView: View {
    @Environment(\.dismiss) private var dismiss
    let task: GoalTask
    let goalTitle: String
    let onApply: (String, Bool) -> Void
    @State private var instruction = "请细化具体操作步骤、完成标准和预期产出；保留已有的重要说明。"
    @State private var output = ""
    @State private var status = ""
    @State private var operation: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("AI 细化执行步骤").font(.title2.bold()); Spacer(); Button("取消") { dismiss() } }
            Text(task.title).font(.headline)
            TextField("这次希望怎样细化", text: $instruction)
            Text("只发送当前任务的标题、说明和所属目标名称，不发送其他任务或本地数据库。")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Button("生成执行指南") { generate() }.disabled(operation != nil); if operation != nil { ProgressView().controlSize(.small); Button("停止") { operation?.cancel() } } }
            Text(status).font(.caption).foregroundStyle(.secondary)
            ScrollView { MarkdownNotes(text: output.isEmpty ? "生成结果将在这里预览。" : output) }.padding(12).background(.primary.opacity(0.03))
            HStack { Spacer(); Button("追加到说明") { onApply(output, true); dismiss() }.disabled(output.isEmpty); Button("替换原说明") { onApply(output, false); dismiss() }.disabled(output.isEmpty) }
        }.padding(24).frame(width: 720, height: 650).onDisappear { operation?.cancel() }
    }
    private func generate() {
        status = "正在细化…"
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                output = try await AIClient().complete(config: AISettings.configuration, key: AIKeychain().read(),
                    system: "你帮助用户完善一项任务的 Markdown 执行指南。只返回 Markdown。包含任务目的、具体操作、完成标准、预期产出、注意事项；不虚构资料、正式期限或研究结果。不要生成整个计划或修改完成状态。",
                    user: "所属目标：\(goalTitle)\n任务：\(task.title)\n任务简介：\(task.summary)\n现有说明：\(task.notes)\n本次要求：\(instruction)")
                status = "请阅读后选择追加、替换或取消。"
            } catch is CancellationError { status = "已取消。" }
            catch { status = error.localizedDescription }
        }
    }
}
