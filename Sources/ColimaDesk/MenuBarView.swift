import SwiftUI
import ColimaCore

@MainActor
private enum MenuBarImages {
    static let container = template("shippingbox")
    static let busy = template("arrow.triangle.2.circlepath")

    private static func template(_ symbol: String) -> NSImage {
        let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: "Colima View")
        let image = symbolImage?.withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
            ?? symbolImage ?? NSImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("barContainerCount") private var showCount = true
    @AppStorage("barCPU") private var showCPU = true
    @AppStorage("barMemory") private var showMemory = false
    private var summary: String {
        guard store.currentProfile?.isRunning == true else { return "" }
        var values: [String] = []
        if showCount { values.append("\(store.runningContainers.count)") }
        if showCPU { values.append(String(format: "%.0f%%", store.cpu)) }
        if showMemory { values.append(ByteSize.format(store.memory)) }
        return values.joined(separator: " ")
    }
    private var icon: some View {
        Image(nsImage: store.isBusy ? MenuBarImages.busy : MenuBarImages.container)
            .renderingMode(.template)
            .symbolRenderingMode(.monochrome)
    }
    var body: some View {
        Group {
            if summary.isEmpty {
                icon
            } else {
                Label { Text(summary).monospacedDigit() } icon: { icon }
                    .labelStyle(.titleAndIcon)
            }
        }.help(L("Colima View · \(store.selectedProfileName) · \(store.runningContainers.count) 个运行中容器 · CPU \(String(format: "%.1f", store.cpu))% · 内存 \(ByteSize.format(store.memory))"))
            .accessibilityLabel(L("Colima View，\(store.currentProfile?.isRunning == true ? L("运行中") : L("已停止"))，\(store.runningContainers.count) 个容器"))
    }
}

struct MenuBarView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill").foregroundStyle(.white).font(.title3).frame(width: 37, height: 37).background(Palette.accent.gradient, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) { Text("Colima View").font(.headline); Text(store.activeOperation ?? L("你的本地容器工作空间")).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help(L("刷新")).disabled(store.isBusy || store.isRefreshing)
            }
            HStack {
                Picker(L("实例"), selection: Binding(get: { store.selectedProfileName }, set: { store.selectProfile($0) })) {
                    if store.profiles.isEmpty { Text(L("暂无实例")).tag(store.selectedProfileName) }
                    ForEach(store.profiles) { Text($0.name).tag($0.name) }
                }.labelsHidden().frame(maxWidth: .infinity).disabled(store.isBusy)
                StatusBadge(text: store.currentProfile?.isRunning == true ? L("运行中") : L("已停止"), color: store.currentProfile?.isRunning == true ? .green : .secondary)
            }
            HStack(spacing: 10) {
                menuMetric(L("容器"), "\(store.runningContainers.count)", "shippingbox")
                menuMetric("CPU", String(format: "%.1f%%", store.cpu), "cpu")
                menuMetric(L("内存"), ByteSize.format(store.memory), "memorychip")
            }
            if store.connectionError != nil { Label(L("连接异常，请打开主窗口查看详情"), systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            if let profile = store.currentProfile {
                HStack(spacing: 10) {
                    Button { store.colimaAction(profile.isRunning ? "stop" : "start", profile: profile) } label: { Label(profile.isRunning ? L("停止实例") : L("启动实例"), systemImage: profile.isRunning ? "stop.fill" : "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                    Button { store.colimaAction("restart", profile: profile) } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.bordered).disabled(!profile.isRunning)
                }.disabled(store.isBusy)
            }
            Divider()
            HStack { Text(L("容器速览")).font(.caption.weight(.medium)).foregroundStyle(.secondary); Spacer(); Text(L("\(store.runningContainers.count) 运行中")).font(.caption2).foregroundStyle(.tertiary) }
            if store.containers.isEmpty {
                Text(L("暂无容器，打开主窗口运行你的第一个应用。")).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 14)
            } else {
                ForEach(Array(store.containers.sorted { $0.isRunning && !$1.isRunning }.prefix(5))) { container in
                    HStack(spacing: 8) {
                        Circle().fill(container.isRunning ? .green : .gray).frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 3) { Text(container.Names).font(.callout.weight(.medium)).lineLimit(1); Text(container.Image).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer()
                        Button { store.containerAction(container.isPaused ? "unpause" : container.isRunning ? "stop" : "start", container) } label: { Image(systemName: container.isRunning ? "stop.fill" : "play.fill").frame(width: 20, height: 22) }.buttonStyle(.plain).help(container.isRunning ? L("停止容器") : L("启动容器")).disabled(store.isBusy)
                    }
                }
            }
            Divider()
            HStack {
                Button { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) } label: { Label(L("打开主窗口"), systemImage: "macwindow") }.buttonStyle(.plain)
                Spacer()
                Button { openSettings(); NSApp.activate(ignoringOtherApps: true) } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help(L("设置"))
                Menu { Button(L("退出 Colima View")) { NSApp.terminate(nil) }; Text(L("退出客户端会保留运行中的虚拟机。")) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20).help(L("更多操作"))
            }.font(.callout)
        }.padding(20).frame(width: 365)
    }
    private func menuMetric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Label(title, systemImage: icon).font(.caption2).foregroundStyle(.secondary); Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
}
