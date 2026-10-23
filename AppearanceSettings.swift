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

    @AppStorage("noteStyle") private var noteStyle = "minimal"
    @AppStorage("notePaper") private var paper = "cream"
    private let shape = Rectangle()

    var body: some View {
        ZStack {
            if noteStyle == "retro" {
                RetroPaperBackground(paper: paper)
            } else {
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
        }
        .clipShape(shape)
    }
}

struct RetroPaperBackground: View {
    let paper: String
    var ruled = true
    private var paperColor: Color {
        AppearanceColor.color(from: paper == "newsprint" ? "#E8D4AD" : paper == "blue" ? "#B6CAD1" : paper == "chalk" ? "#F3F3EE" : "#F8F3E3")
    }
    var body: some View {
        ZStack {
            paperColor
            Canvas { context, size in
                let ink = paper == "blue" ? Color(red: 0.23, green: 0.34, blue: 0.39) : Color(red: 0.37, green: 0.30, blue: 0.22)
                if paper == "newsprint" {
                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: 16))
                        for i in 0..<38 {
                            let x = CGFloat((i * 61 + 13) % 101) / 101 * size.width
                            let y = CGFloat((i * 47 + 29) % 103) / 103 * size.height
                            layer.fill(Path(ellipseIn: CGRect(x: x - 35, y: y - 30, width: 85, height: 65)), with: .color(ink.opacity(0.035)))
                        }
                    }
                }
                if ruled {
                for row in stride(from: 132.0, to: size.height, by: 30.0) {
                    var line = Path(); line.move(to: CGPoint(x: 0, y: row)); line.addLine(to: CGPoint(x: size.width, y: row))
                    context.stroke(line, with: .color(ink.opacity(paper == "blue" ? 0.22 : 0.15)), lineWidth: 0.6)
                }
                var margin = Path(); margin.move(to: CGPoint(x: 15, y: 104)); margin.addLine(to: CGPoint(x: 15, y: size.height))
                context.stroke(margin, with: .color(Color(red: 0.65, green: 0.33, blue: 0.24).opacity(paper == "blue" ? 0.28 : 0.23)), lineWidth: 0.7)
                }
                // Stable, faint paper fibres; no external texture or changing random noise.
                var seed: UInt64 = 827341
                func sample() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 32) / CGFloat(UInt32.max) }
                for _ in 0..<2200 {
                    let x = sample() * size.width
                    let y = sample() * size.height
                    context.fill(Path(CGRect(x: x, y: y, width: sample() > 0.66 ? 1.5 : 0.6, height: 0.55)), with: .color(ink.opacity(paper == "newsprint" ? 0.085 : 0.045)))
                }
            }.allowsHitTesting(false)
            if ruled { VStack(spacing: 0) {
                Rectangle().fill(Color(red: 0.55, green: 0.37, blue: 0.25).opacity(0.13)).frame(height: 5)
                Spacer()
                Rectangle().fill(.black.opacity(0.025)).frame(height: 3)
            }.allowsHitTesting(false) }
        }
    }
}

struct CollapsedOrbView: View {
    static let hitSize: CGFloat = 52
    let expand: () -> Void
    @AppStorage("noteStyle") private var noteStyle = "minimal"
    @AppStorage("collapsedDotDiameter") private var diameter = 32.0
    @AppStorage("notePaper") private var paper = "cream"
    @AppStorage("appearanceColor") private var colorHex = "#F0F0FA"
    private var visibleSize: CGFloat { CGFloat(min(40, max(26, diameter))) }
    var body: some View {
        ZStack {
                Color.white.opacity(0.001)
                Group {
                    if noteStyle == "retro" { RetroPaperBackground(paper: paper, ruled: false) }
                    else { AppearanceColor.color(from: colorHex) }
                }
                    .clipShape(Circle())
                    .overlay(Circle().stroke(noteStyle == "retro" ? Color.brown.opacity(0.48) : Color.white.opacity(0.85), lineWidth: 1))
                    .background(Circle().fill(.white.opacity(0.18)))
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
                    .frame(width: visibleSize, height: visibleSize)
            }.frame(width: Self.hitSize, height: Self.hitSize).contentShape(Rectangle())
            .overlay { WindowDragSurface(click: expand) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("展开 Mint Todo")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { expand() }
            .help("点击展开，拖动移动圆点")
    }
}

struct AppearanceSettings: View {
    @AppStorage("noteStyle") private var noteStyle = "minimal"
    @AppStorage("notePaper") private var paper = "cream"
    @AppStorage("appearanceMode") private var mode = "glass"
    @AppStorage("appearanceColor") private var colorHex = "#F0F0FA"
    @AppStorage("appearanceOpacity") private var opacity = 0.92
    @AppStorage("backgroundPhotoPath") private var photoPath = ""
    @AppStorage("backgroundPhotoZoom") private var photoZoom = 1.0
    @AppStorage("collapsedDotDiameter") private var dotDiameter = 32.0
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("便签外观").font(.system(size: 14, weight: .semibold))
            Picker("样式设计", selection: $noteStyle) {
                Text("简约便签").tag("minimal")
                Text("复古纸签").tag("retro")
            }.pickerStyle(.segmented)
            Text("外框为直角，分类栏、输入框和内部卡片保留圆角。").font(.system(size: 10)).foregroundStyle(.secondary)
            if noteStyle == "retro" {
                Picker("纸张色调", selection: $paper) {
                    Text("奶油横线").tag("cream")
                    Text("复古旧纸").tag("newsprint")
                    Text("蓝灰纸").tag("blue")
                    Text("灰白纸").tag("chalk")
                }.pickerStyle(.segmented)
                RetroPaperBackground(paper: paper)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("MINT / NOTES").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2)
                            Text("把今天写在纸上").font(.system(size: 19, weight: .medium, design: .serif))
                            Text("暖纸色 · 细横线 · 轻纸纹").font(.system(size: 11)).foregroundStyle(.secondary)
                        }.padding(18).foregroundStyle(Color(red: 0.24, green: 0.20, blue: 0.16))
                    }.frame(height: 110).overlay(Rectangle().stroke(.black.opacity(0.15), lineWidth: 1))
            } else {
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
            Divider()
            HStack {
                Text("收起圆点大小").font(.system(size: 11))
                Slider(value: $dotDiameter, in: 26...40, step: 2)
                Text("\(Int(dotDiameter)) pt").font(.system(size: 10).monospacedDigit()).frame(width: 40)
                CollapsedOrbView(expand: {}).allowsHitTesting(false)
            }
            Text("收起到距离窗口最近的屏幕角落，可拖动；点击区域为 52 × 52 pt；跟随主体色调，使用纯色或细纸纹纯色。")
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
