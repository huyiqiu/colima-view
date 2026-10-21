import SwiftUI
import ColimaCore

enum Palette {
    static let accent = Color(red: 0.17, green: 0.39, blue: 0.90)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let line = Color.primary.opacity(0.075)
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1))
    }
}

struct StatusBadge: View {
    let text: String
    var color: Color = .green
    var body: some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 6, height: 6); Text(text).font(.system(size: 11, weight: .medium)) }
            .padding(.horizontal, 8).padding(.vertical, 4).background(color.opacity(0.09), in: Capsule())
            .foregroundStyle(color)
    }
}

struct ResourceCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    var body: some View {
        Card {
            HStack { Text(title).foregroundStyle(.secondary); Spacer(); Image(systemName: icon).foregroundStyle(Palette.accent) }
            Text(value).font(.system(size: 29, weight: .semibold, design: .rounded)).monospacedDigit().padding(.top, 8)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct EmptyState: View {
    let title: String
    let description: String
    let icon: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(Palette.accent)
                .frame(width: 80, height: 80).background(Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
            Text(title).font(.title3.weight(.semibold))
            Text(description).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 390)
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(.borderedProminent).padding(.top, 6) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }
}

struct SectionHeading<Trailing: View>: View {
    let title: String
    let trailing: Trailing
    init(_ title: String, @ViewBuilder trailing: () -> Trailing) { self.title = title; self.trailing = trailing() }
    var body: some View { HStack { Text(title).font(.headline); Spacer(); trailing } }
}

struct SmallIconButton: View {
    let title: String
    let icon: String
    var role: ButtonRole? = nil
    let action: () -> Void
    var body: some View {
        Button(role: role, action: action) { Image(systemName: icon).frame(width: 23, height: 23).contentShape(Rectangle()) }
            .buttonStyle(.borderless).help(title).accessibilityLabel(title)
    }
}

func copyText(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

func chooseFile(extensions: [String]? = nil, directories: Bool = false) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = directories
    panel.canChooseFiles = !directories
    panel.allowsMultipleSelection = false
    if let extensions { panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) } }
    return panel.runModal() == .OK ? panel.url : nil
}

import UniformTypeIdentifiers

struct SheetHeader: View {
    let title: String
    let subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.title2.weight(.semibold)); Text(subtitle).font(.callout).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(24) }
}

struct CodeBlock: View {
    let text: String
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(text.isEmpty ? L("暂无输出") : text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading).padding(16)
        }.background(Color(nsColor: .textBackgroundColor))
    }
}
