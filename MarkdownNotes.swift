import AppKit
import SwiftUI

struct MarkdownBlock: Identifiable {
    enum Kind { case heading(Int), paragraph, bullet(String), checklist(Bool), code(String), divider }
    let id: Int
    let kind: Kind
    let text: String
}
enum MarkdownBlocks {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.components(separatedBy: .newlines)
        var result: [MarkdownBlock] = []; var i = 0
        while i < lines.count {
            let raw = lines[i]; let line = raw.trimmingCharacters(in: .whitespaces); let index = i
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)); i += 1; var code: [String] = []
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.append(lines[i]); i += 1 }
                result.append(MarkdownBlock(id: index, kind: .code(language), text: code.joined(separator: "\n")))
            } else if line.isEmpty { i += 1; continue }
            else if line == "---" || line == "***" { result.append(MarkdownBlock(id: index, kind: .divider, text: "")) }
            else if let range = line.range(of: #"^#{1,6} "#, options: .regularExpression) {
                result.append(MarkdownBlock(id: index, kind: .heading(range.upperBound.utf16Offset(in: line) - 1), text: String(line[range.upperBound...])))
            } else if line.range(of: #"^[-*+] \[[ xX]\] "#, options: .regularExpression) != nil {
                let checked = line.lowercased().hasPrefix("- [x]") || line.lowercased().hasPrefix("* [x]") || line.lowercased().hasPrefix("+ [x]")
                result.append(MarkdownBlock(id: index, kind: .checklist(checked), text: String(line.dropFirst(6))))
            } else if let range = line.range(of: #"^(?:[-*+] |\d+[.)] )"#, options: .regularExpression) {
                let prefix = String(line[..<range.upperBound]).trimmingCharacters(in: .whitespaces)
                result.append(MarkdownBlock(id: index, kind: .bullet(prefix == "-" || prefix == "*" || prefix == "+" ? "•" : prefix), text: String(line[range.upperBound...])))
            } else { result.append(MarkdownBlock(id: index, kind: .paragraph, text: raw)) }
            i += 1
        }
        return result
    }
    static func toggle(_ source: String, line: Int) -> String {
        var lines = source.components(separatedBy: .newlines)
        guard lines.indices.contains(line), let range = lines[line].range(of: #"\[[ xX]\]"#, options: .regularExpression) else { return source }
        let checked = lines[line][range].lowercased() == "[x]"
        lines[line].replaceSubrange(range, with: checked ? "[ ]" : "[x]")
        return lines.joined(separator: "\n")
    }
}
struct MarkdownNotes: View {
    let text: String
    var onToggle: ((Int) -> Void)?
    var onPromote: ((String) -> Void)?
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MarkdownBlocks.parse(text)) { block in
                switch block.kind {
                case .heading(let level):
                    Text(inline(block.text)).font(.system(size: level == 1 ? 24 : level == 2 ? 19 : 16, weight: .semibold)).padding(.top, 7)
                case .paragraph:
                    if let url = URL(string: block.text.trimmingCharacters(in: .whitespaces)),
                       ["http", "https"].contains(url.scheme ?? ""), !block.text.contains(" ") {
                        Link(block.text, destination: url).textSelection(.enabled)
                    } else {
                        Text(inline(block.text)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .bullet(let label):
                    HStack(alignment: .top, spacing: 8) { Text(label).foregroundStyle(.secondary); Text(inline(block.text)).textSelection(.enabled) }
                case .checklist(let checked):
                    HStack(alignment: .top, spacing: 8) {
                        Button { onToggle?(block.id) } label: { Image(systemName: checked ? "checkmark.square.fill" : "square") }
                            .buttonStyle(.plain).disabled(onToggle == nil)
                        Text(inline(block.text)).textSelection(.enabled)
                        Spacer(minLength: 0)
                        if let onPromote { Button { onPromote(block.text) } label: { Image(systemName: "arrow.up.right.square") }.buttonStyle(.plain).help("提升为正式子任务") }
                    }
                case .code(let language):
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(language.isEmpty ? "代码" : language).font(.caption).foregroundStyle(.secondary); Spacer(); Button("复制代码") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(block.text, forType: .string) }.font(.caption) }
                        ScrollView(.horizontal) { Text(block.text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: true, vertical: false) }
                    }.padding(12).background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.05)))
                case .divider: Divider()
                }
            }
        }
        .font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded })
    }
}
