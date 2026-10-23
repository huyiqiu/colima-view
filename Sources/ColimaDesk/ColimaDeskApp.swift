import SwiftUI
import ColimaCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
@MainActor
struct ColimaDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = AppStore()
    @AppStorage("appLanguage") private var appLanguage = "en"
    init() {
        UserDefaults.standard.register(defaults: ["refreshInterval": 10, "barContainerCount": true, "barCPU": true, "barMemory": false, "appLanguage": "en"])
        UserDefaults.standard.set([Localization.language], forKey: "AppleLanguages")
    }
    var body: some Scene {
        Window("Colima View", id: "main") {
            MainWindow().environmentObject(store).tint(Palette.accent).modernControls()
                .environment(\.locale, Locale(identifier: appLanguage)).id(appLanguage)
                .frame(minWidth: 1040, minHeight: 680)
                .task { store.startPolling() }
        }
        .defaultSize(width: 1220, height: 790)
        .windowToolbarStyle(.unified)
        .commands { DeskCommands(store: store) }
        MenuBarExtra {
            MenuBarView().environmentObject(store).tint(Palette.accent).modernControls()
                .environment(\.locale, Locale(identifier: appLanguage)).id(appLanguage).task { store.startPolling() }
        } label: { MenuBarLabel().environmentObject(store).id(appLanguage) }
        .menuBarExtraStyle(.window)
        Settings { AppSettingsView().environmentObject(store).tint(Palette.accent).modernControls().environment(\.locale, Locale(identifier: appLanguage)).id(appLanguage) }
    }
}

struct DeskCommands: Commands {
    @ObservedObject var store: AppStore
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("刷新状态")) { store.refresh() }.keyboardShortcut("r")
            Button(L("显示主窗口")) { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }.keyboardShortcut("0")
        }
    }
}

struct MainWindow: View {
    @EnvironmentObject var store: AppStore
    @State private var columns: NavigationSplitViewVisibility = .all
    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 11) {
                    Image(systemName: "shippingbox.fill").font(.system(size: 23, weight: .medium)).foregroundStyle(.white)
                        .frame(width: 43, height: 43).background(Palette.accent.gradient, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Colima View").font(.system(size: 17, weight: .semibold))
                        Text("LOCAL CONTAINERS").font(.system(size: 9, weight: .medium, design: .rounded)).tracking(1.8).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 25)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("工作空间")).font(.caption).foregroundStyle(.secondary)
                    Picker(L("当前实例"), selection: Binding(get: { store.selectedProfileName }, set: { store.selectProfile($0) })) {
                        if store.profiles.isEmpty { Text(L("暂无实例")).tag(store.selectedProfileName) }
                        ForEach(store.profiles) { profile in
                            Text("\(profile.isRunning ? "●" : "○")  \(profile.name)").tag(profile.name)
                        }
                    }.labelsHidden().frame(maxWidth: .infinity).disabled(store.isBusy)
                }.padding(.horizontal, 20).padding(.bottom, 20)
                List(AppSection.allCases, selection: $store.section) { section in
                    Label { HStack { Text(section.title); Spacer(); if let count = count(section) { Text("\(count)").font(.caption).foregroundStyle(.tertiary) } } }
                    icon: { Image(systemName: section.icon).frame(width: 20) }
                        .padding(.vertical, 5).tag(section)
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                    HStack {
                        Circle().fill(store.currentProfile?.isRunning == true ? Color.green : .gray).frame(width: 7, height: 7)
                        Text(store.currentProfile?.isRunning == true ? L("Colima 正在运行") : L("Colima 已停止")).font(.caption)
                        Spacer()
                        SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.deskIcon).help(L("设置")).accessibilityLabel(L("设置"))
                    }
                    if let version = store.snapshot?.info.ServerVersion { Text("Docker Engine \(version)").font(.caption2).foregroundStyle(.secondary) }
                }.padding(20)
            }.navigationSplitViewColumnWidth(min: 210, ideal: 225, max: 250)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.section.title).font(.system(size: 27, weight: .semibold))
                        Text(store.section.subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if ![.overview, .storage, .activity].contains(store.section) {
                        DeskSearchField(title: L("搜索\(store.section.title)…"), text: $store.search).frame(width: 240)
                    }
                }.padding(.horizontal, 28).padding(.top, 25).padding(.bottom, 22)
                if let error = store.connectionError {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(error).font(.caption).textSelection(.enabled).lineLimit(3)
                        Spacer()
                        Button(L("重试")) { store.refresh() }.buttonStyle(.deskQuiet)
                    }.padding(12).background(Color.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 28).padding(.bottom, 12)
                }
                Group {
                    switch store.section {
                    case .overview: DashboardView()
                    case .profiles: ProfilesView()
                    case .containers: ContainersView()
                    case .images: ImagesView()
                    case .compose: ComposeView()
                    case .storage: StorageView()
                    case .volumes: VolumesView()
                    case .networks: NetworksView()
                    case .activity: ActivityView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack(spacing: 8) {
                    if store.isBusy {
                        ProgressView().controlSize(.small)
                        Text(store.activeOperation ?? L("正在处理…")).font(.caption)
                        Spacer()
                        Button(L("查看进度")) { store.showProgress = true }.font(.caption).buttonStyle(.deskQuiet)
                    } else {
                        Image(systemName: "checkmark.circle").foregroundStyle(store.connectionError == nil ? Color.secondary : .orange)
                        Text(store.isRefreshing ? L("正在刷新…") : L("本地连接 · \(store.selectedProfileName)")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if let date = store.lastRefresh { Text(L("更新于 \(date.formatted(date: .omitted, time: .standard))")).font(.caption).foregroundStyle(.tertiary) }
                    }
                }.padding(.horizontal, 24).frame(height: 37)
            }.background(Palette.canvas)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    SmallIconButton(title: L("切换侧边栏"), icon: "sidebar.left") { columns = columns == .detailOnly ? .all : .detailOnly }
                        .keyboardShortcut("s", modifiers: [.command, .control])
                }
                ToolbarItem(placement: .principal) { Text("\(store.selectedProfileName) / \(store.section.title)").font(.caption).foregroundStyle(.secondary) }
                ToolbarItem(placement: .primaryAction) {
                    SmallIconButton(title: L("刷新状态 ⌘R"), icon: "arrow.clockwise") { store.refresh() }
                        .disabled(store.isRefreshing || store.isBusy)
                }
            }
        }
        .onChange(of: store.section) { _, _ in store.search = "" }
        .alert(item: $store.notice) { notice in Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text(L("知道了")))) }
        .confirmationDialog(store.confirmation?.title ?? L("确认操作"), isPresented: Binding(get: { store.confirmation != nil }, set: { if !$0 { store.confirmation = nil } }), titleVisibility: .visible, presenting: store.confirmation) { confirmation in
            Button(confirmation.button, role: .destructive) { confirmation.action(); store.confirmation = nil }
            Button(L("取消"), role: .cancel) { store.confirmation = nil }
        } message: { confirmation in Text(confirmation.message) }
        .sheet(isPresented: $store.showProgress) { ProgressDetailView() }
    }
    private func count(_ section: AppSection) -> Int? {
        switch section { case .containers: return store.containers.count; case .images: return store.images.count; case .compose: return store.snapshot?.projects.count; default: return nil }
    }
}

struct EngineUnavailableView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        if let profile = store.currentProfile, profile.runtime != "docker" {
            EmptyState(title: L("此实例使用 \(profile.runtime) 运行时"), description: L("容器管理界面需要 Docker 运行时。你可以切换或创建一个 Docker 实例。"), icon: "desktopcomputer", actionTitle: L("管理实例")) { store.section = .profiles }
        } else {
            EmptyState(title: store.currentProfile?.isRunning == true ? L("引擎尚未就绪") : L("先启动你的工作空间"), description: L("启动 Colima 后，就可以在这里管理容器和镜像。"), icon: "power", actionTitle: store.currentProfile?.isRunning == true ? L("刷新连接") : L("启动 Colima")) {
            if let profile = store.currentProfile, !profile.isRunning { store.colimaAction("start", profile: profile) }
            else if store.currentProfile == nil { store.section = .profiles }
            else { store.refresh() }
            }.disabled(store.isBusy)
        }
    }
}
