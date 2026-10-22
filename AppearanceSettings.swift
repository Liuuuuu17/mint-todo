import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AppearanceColor {
    static func color(from hex: String) -> Color {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let number = Int(value, radix: 16) else { return Color(red: 0.94, green: 0.94, blue: 0.98) }
        return Color(red: Double((number >> 16) & 0xff) / 255,
                     green: Double((number >> 8) & 0xff) / 255,
                     blue: Double(number & 0xff) / 255)
    }

    static func hex(from color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return "#F0F0FA" }
        return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }
}

struct AppearanceBackground: View {
    @AppStorage("appearanceMode") private var mode = "glass"
    @AppStorage("appearanceColor") private var colorHex = "#F0F0FA"
    @AppStorage("appearanceOpacity") private var opacity = 0.92
    @AppStorage("backgroundPhotoPath") private var photoPath = ""
    @AppStorage("backgroundPhotoZoom") private var photoZoom = 1.0

    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        ZStack {
            switch mode {
            case "solid":
                shape.fill(AppearanceColor.color(from: colorHex).opacity(opacity))
            case "transparent":
                shape.fill(AppearanceColor.color(from: colorHex).opacity(opacity * 0.17))
            case "photo":
                if let photo = NSImage(contentsOfFile: photoPath) {
                    GeometryReader { geometry in
                        Image(nsImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(photoZoom)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                    .opacity(opacity)
                } else {
                    shape.fill(AppearanceColor.color(from: colorHex).opacity(opacity))
                }
            default:
                if #available(macOS 26.0, *) {
                    Color.clear
                        .glassEffect(.regular.tint(AppearanceColor.color(from: colorHex)), in: shape)
                        .opacity(opacity)
                } else {
                    VisualEffect().opacity(opacity)
                    shape.fill(AppearanceColor.color(from: colorHex).opacity(0.12 * opacity))
                }
            }
        }
        .clipShape(shape)
    }
}

struct AppearanceSettings: View {
    @AppStorage("appearanceMode") private var mode = "glass"
    @AppStorage("appearanceColor") private var colorHex = "#F0F0FA"
    @AppStorage("appearanceOpacity") private var opacity = 0.92
    @AppStorage("backgroundPhotoPath") private var photoPath = ""
    @AppStorage("backgroundPhotoZoom") private var photoZoom = 1.0
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("外观").font(.system(size: 14, weight: .semibold))
            Picker("背景效果", selection: $mode) {
                Text("玻璃").tag("glass")
                Text("实色").tag("solid")
                Text("透明").tag("transparent")
                Text("照片").tag("photo")
            }
            .pickerStyle(.segmented)
            ColorPicker("底色 / 玻璃色调", selection: Binding(
                get: { AppearanceColor.color(from: colorHex) },
                set: { colorHex = AppearanceColor.hex(from: $0) }
            ))
            HStack {
                Text("背景强度").frame(width: 74, alignment: .leading)
                Slider(value: $opacity, in: 0.05...1)
                Text("\(Int(opacity * 100))%").frame(width: 38, alignment: .trailing)
            }
            .font(.system(size: 11))
            if mode == "photo" {
                HStack {
                    Button(photoPath.isEmpty ? "选择背景照片…" : "更换背景照片…") { choosePhoto() }
                    if !photoPath.isEmpty { Text(URL(fileURLWithPath: photoPath).lastPathComponent).lineLimit(1).foregroundStyle(.secondary) }
                    Spacer()
                }
                HStack {
                    Text("照片缩放").frame(width: 74, alignment: .leading)
                    Slider(value: $photoZoom, in: 1...2.5)
                    Text(String(format: "%.1f×", photoZoom)).frame(width: 38, alignment: .trailing)
                }
                .font(.system(size: 11))
            }
            if let errorMessage { Text(errorMessage).font(.system(size: 11)).foregroundStyle(.red) }
            Text("玻璃效果在 macOS 26 使用系统 Liquid Glass；旧版 macOS 使用磨砂材质。照片只保存在本机。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.message = "选择背景照片"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OrbTodo/Backgrounds", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent("\(UUID().uuidString).\(source.pathExtension.lowercased())")
            try FileManager.default.copyItem(at: source, to: target)
            photoPath = target.path
            errorMessage = nil
        } catch {
            errorMessage = "照片导入失败：\(error.localizedDescription)"
        }
    }
}
