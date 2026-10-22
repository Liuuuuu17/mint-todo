import AppKit
import CoreText
import SwiftUI
import UniformTypeIdentifiers

struct ImportedFont: Codable, Identifiable, Hashable {
    let id: UUID
    let fileName: String
    let displayName: String
    let postScriptName: String
}

private struct FontManifest: Codable {
    var fonts: [ImportedFont]
    var appliedID: UUID?
}

@MainActor final class FontLibrary: ObservableObject {
    @Published private(set) var fonts: [ImportedFont] = []
    @Published var selectedID: UUID?
    @Published private(set) var appliedID: UUID?
    @Published var errorMessage: String?

    @Published var textSize: Double = 13.5 {
        didSet { UserDefaults.standard.set(textSize, forKey: "taskFontSize") }
    }

    private let folder: URL
    private let manifestURL: URL

    init() {
        let savedSize = UserDefaults.standard.double(forKey: "taskFontSize")
        textSize = savedSize > 0 ? min(max(savedSize, 10), 24) : 13.5
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OrbTodo", isDirectory: true)
        folder = base.appendingPathComponent("Fonts", isDirectory: true)
        manifestURL = base.appendingPathComponent("fonts.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: manifestURL),
           let saved = try? JSONDecoder().decode(FontManifest.self, from: data) {
            fonts = saved.fonts.filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.fileName).path) }
            appliedID = saved.appliedID
            selectedID = saved.appliedID ?? fonts.first?.id
            for font in fonts { register(folder.appendingPathComponent(font.fileName)) }
            if !fonts.contains(where: { $0.id == appliedID }) { appliedID = nil }
        }
    }

    private func register(_ url: URL) {
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(FontManifest(fonts: fonts, appliedID: appliedID)) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    func importFont(_ source: URL) {
        errorMessage = nil
        let ext = source.pathExtension.lowercased()
        guard source.isFileURL, ["ttf", "otf", "ttc"].contains(ext) else {
            errorMessage = "请选择 .ttf、.otf 或 .ttc 字体文件。"
            return
        }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let id = UUID()
        let destination = folder.appendingPathComponent("\(id.uuidString).\(ext)")
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(destination as CFURL) as? [CTFontDescriptor],
                  let descriptor = descriptors.first,
                  let postScriptName = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else {
                try? FileManager.default.removeItem(at: destination)
                errorMessage = "这个文件不是可用的字体。"
                return
            }
            let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String
            register(destination)
            let imported = ImportedFont(id: id, fileName: destination.lastPathComponent,
                                        displayName: family ?? source.deletingPathExtension().lastPathComponent,
                                        postScriptName: postScriptName)
            fonts.append(imported)
            selectedID = id
            save()
        } catch {
            errorMessage = "字体导入失败：\(error.localizedDescription)"
        }
    }

    func applySelected() {
        guard let selectedID, fonts.contains(where: { $0.id == selectedID }) else { return }
        appliedID = selectedID
        save()
    }

    func restoreSystemFont() {
        appliedID = nil
        save()
    }

    func removeSelected() {
        guard let selectedID, let font = fonts.first(where: { $0.id == selectedID }) else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(font.fileName))
        fonts.removeAll { $0.id == selectedID }
        if appliedID == selectedID { appliedID = nil }
        self.selectedID = fonts.first?.id
        save()
    }

    func font(_ size: CGFloat, weight: Font.Weight = .regular, monospaced: Bool = false) -> Font {
        let adjustedSize = size * CGFloat(textSize / 13.5)
        if let applied = fonts.first(where: { $0.id == appliedID }) {
            return .custom(applied.postScriptName, size: adjustedSize).weight(weight)
        }
        return .system(size: adjustedSize, weight: weight, design: monospaced ? .monospaced : .default)
    }

    func previewFont(_ size: CGFloat) -> Font {
        let size = size * CGFloat(textSize / 13.5)
        if let selected = fonts.first(where: { $0.id == selectedID }) {
            return .custom(selected.postScriptName, size: size)
        }
        return .system(size: size)
    }
}

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TaskStore
    @ObservedObject var fontLibrary: FontLibrary
    @ObservedObject var reminderSync: RemindersSync
    let onOpacity: (Double) -> Void
    let onResize: (CGSize) -> Void
    let onImport: () -> Void
    let onCategory: () -> Void
    let onArchive: () -> Void

    @AppStorage("widgetOpacity") private var opacity = 0.94
    @AppStorage("widgetWidth") private var widgetWidth = 405.0
    @AppStorage("widgetHeight") private var widgetHeight = 560.0
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("设置").font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("字体").font(.system(size: 14, weight: .semibold))
                HStack {
                    Text("字号").font(.system(size: 12))
                    Slider(value: $fontLibrary.textSize, in: 10...24, step: 0.5)
                    Text(String(format: "%.1f pt", fontLibrary.textSize))
                        .font(.system(size: 11).monospacedDigit()).frame(width: 54)
                    Button("重置") { fontLibrary.textSize = 13.5 }
                }
                VStack(spacing: 7) {
                    Image(systemName: "textformat").font(.system(size: 22)).foregroundStyle(.secondary)
                    Text("将字体文件拖到这里").font(.system(size: 13))
                    Text("可一次拖入多个 .ttf、.otf、.ttc 文件").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("选择多个字体文件…") { chooseFontFiles() }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 125)
                .background(RoundedRectangle(cornerRadius: 13).fill(dropTargeted ? Color.blue.opacity(0.11) : Color.gray.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(dropTargeted ? Color.blue.opacity(0.55) : Color.gray.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { providers in
                    guard !providers.isEmpty else { return false }
                    for provider in providers {
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                            let url: URL?
                            if let item = item as? URL { url = item }
                            else if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                            else if let path = item as? String { url = URL(fileURLWithPath: path) }
                            else { url = nil }
                            if let url { Task { @MainActor in fontLibrary.importFont(url) } }
                        }
                    }
                    return true
                }
                if let error = fontLibrary.errorMessage {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                }
                if !fontLibrary.fonts.isEmpty {
                    Text("已保存字体 · \(fontLibrary.fonts.count) 种")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(fontLibrary.fonts) { font in
                                Button { fontLibrary.selectedID = font.id } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(font.displayName).font(.system(size: 12, weight: .medium))
                                            Text("今天要完成的事 · Aa 123")
                                                .font(.custom(font.postScriptName, size: 13))
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        if font.id == fontLibrary.appliedID { Text("使用中").font(.system(size: 10)).foregroundStyle(.secondary) }
                                        if font.id == fontLibrary.selectedID { Image(systemName: "checkmark").font(.system(size: 11)) }
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(font.id == fontLibrary.selectedID ? Color.blue.opacity(0.1) : Color.clear))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: min(CGFloat(fontLibrary.fonts.count) * 53, 175))
                }
                Text("今天要完成的事 · Aa 123")
                    .font(fontLibrary.previewFont(19))
                    .frame(maxWidth: .infinity, minHeight: 65)
                    .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.68)))
                HStack {
                    Button("应用字体") { fontLibrary.applySelected() }
                        .disabled(fontLibrary.selectedID == nil)
                    Button("恢复系统字体") { fontLibrary.restoreSystemFont() }
                    Spacer()
                    if fontLibrary.selectedID != nil {
                        Button("移除字体", role: .destructive) { fontLibrary.removeSelected() }
                    }
                }
            }

            Divider()
            AppearanceSettings()
            Divider()
            RemindersSettings(sync: reminderSync)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("窗口大小").font(.system(size: 12, weight: .medium))
                HStack {
                    Text("宽度").frame(width: 52, alignment: .leading)
                    Slider(value: $widgetWidth, in: 320...900)
                        .onChange(of: widgetWidth) { value in onResize(CGSize(width: value, height: widgetHeight)) }
                    Text("\(Int(widgetWidth))").frame(width: 40, alignment: .trailing)
                }
                HStack {
                    Text("高度").frame(width: 52, alignment: .leading)
                    Slider(value: $widgetHeight, in: 380...900)
                        .onChange(of: widgetHeight) { value in onResize(CGSize(width: widgetWidth, height: value)) }
                    Text("\(Int(widgetHeight))").frame(width: 40, alignment: .trailing)
                }
                Text("也可以拖动主窗口右下角的 ↘ 来调整。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
            Divider()
            HStack {
                Text("整个窗口透明度").font(.system(size: 12))
                Slider(value: $opacity, in: 0.72...1)
                    .onChange(of: opacity) { value in onOpacity(value) }
            }
            HStack {
                Button("管理分组") { onCategory() }
                Button("查看归档") { onArchive() }
                Spacer()
            }
            HStack {
                Button("复制清单") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.textExport(), forType: .string)
                }
                Button("批量导入") { onImport() }
                Button("打开数据文件") { NSWorkspace.shared.activateFileViewerSelecting([store.fileURL]) }
                Spacer()
            }
            .font(.system(size: 11))
                }
            }
        }
        .padding(24)
        .frame(width: 440, height: 570)
    }

    private func chooseFontFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = "可一次选择多个 TrueType 或 OpenType 字体文件"
        if panel.runModal() == .OK {
            for url in panel.urls { fontLibrary.importFont(url) }
        }
    }
}
