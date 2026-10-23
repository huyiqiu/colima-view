import SwiftUI
import ColimaCore

enum Palette {
    static let accent = Color(red: 0.30, green: 0.34, blue: 0.91)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let line = Color.primary.opacity(0.075)
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.line, lineWidth: 1))
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
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(.deskPrimary).padding(.top, 6) }
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
        Button(role: role, action: action) { Image(systemName: icon) }
            .buttonStyle(.deskIcon).help(title).accessibilityLabel(title)
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

struct DeskButtonStyle: ButtonStyle {
    enum Appearance { case primary, secondary, quiet, icon }
    var appearance: Appearance = .secondary
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let prominent = appearance == .primary
        let circular = appearance == .icon
        let destructive = configuration.role == .destructive
        let tint = destructive ? Color.red : Palette.accent
        let shape = RoundedRectangle(cornerRadius: circular ? 18 : 10, style: .continuous)
        return configuration.label
            .font(.system(size: 12, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(prominent ? Color.white : destructive ? .red : Color.primary.opacity(0.85))
            .padding(.horizontal, circular ? 0 : 13)
            .frame(minWidth: circular ? 32 : nil, maxWidth: circular ? 32 : nil)
            .frame(height: 32)
            .background {
                shape.fill(prominent ? tint : hovered ? tint.opacity(0.10) : appearance == .quiet ? Color.clear : Color.primary.opacity(0.045))
            }
            .overlay(shape.stroke(prominent ? Color.white.opacity(0.12) : hovered ? tint.opacity(0.22) : Palette.line, lineWidth: appearance == .quiet && !hovered ? 0 : 1))
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
            .onHover { hovered = $0 && isEnabled }
    }
}

extension ButtonStyle where Self == DeskButtonStyle {
    static var deskPrimary: DeskButtonStyle { .init(appearance: .primary) }
    static var deskSecondary: DeskButtonStyle { .init(appearance: .secondary) }
    static var deskQuiet: DeskButtonStyle { .init(appearance: .quiet) }
    static var deskIcon: DeskButtonStyle { .init(appearance: .icon) }
}

struct ActionMenu<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var hovered = false
    var body: some View {
        Menu(content: content) {
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 32, height: 32)
        .background(hovered ? Palette.accent.opacity(0.10) : Color.primary.opacity(0.045), in: Circle())
        .overlay(Circle().stroke(Palette.line, lineWidth: 1)).contentShape(Circle())
        .onHover { hovered = $0 }.help(L("更多操作")).accessibilityLabel(L("更多操作"))
    }
}

struct DeskMenu<Content: View>: View {
    let title: String
    var icon: String? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    var body: some View {
        Menu(content: content) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon).symbolRenderingMode(.hierarchical) }
                Text(title)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .semibold))
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .padding(.horizontal, 12).frame(height: 32)
            .background(hovered ? Palette.accent.opacity(0.1) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1)).opacity(enabled ? 1 : 0.4)
            .onHover { hovered = $0 && enabled }
    }
}

struct DeskSearchField: View {
    let title: String
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(title, text: $text).textFieldStyle(.plain).focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help(L("清除搜索")).accessibilityLabel(L("清除搜索"))
            }
        }
        .font(.system(size: 12)).padding(.horizontal, 11).frame(height: 34)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(focused ? Palette.accent.opacity(0.6) : Palette.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

private struct HoverSurface: ViewModifier {
    @State private var hovered = false
    func body(content: Content) -> some View {
        content.background(hovered ? Palette.accent.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .onHover { hovered = $0 }
    }
}

extension View {
    func modernControls() -> some View { buttonStyle(.deskSecondary).toggleStyle(.switch) }
    func hoverSurface() -> some View { modifier(HoverSurface()) }
}
