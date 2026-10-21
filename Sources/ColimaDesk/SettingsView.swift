import SwiftUI
import ServiceManagement
import ColimaCore

struct AppSettingsView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("appLanguage") private var appLanguage = "en"
    @AppStorage("refreshInterval") private var refreshInterval = 10
    @AppStorage("barContainerCount") private var showCount = true
    @AppStorage("barCPU") private var showCPU = true
    @AppStorage("barMemory") private var showMemory = false
    @AppStorage("colimaPath") private var colimaPath = ""
    @AppStorage("dockerPath") private var dockerPath = ""
    @AppStorage("downloadProxy") private var downloadProxy = ""
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var message: String?
    @State private var vmProxy = ""
    @State private var applyProxy = false
    var body: some View {
        TabView {
            Form {
                Section(L("语言")) {
                    Picker(L("语言"), selection: $appLanguage) {
                        Text("English").tag("en")
                        Text(verbatim: "简体中文").tag("zh-Hans")
                    }.onChange(of: appLanguage) { _, value in UserDefaults.standard.set([value], forKey: "AppleLanguages") }
                    Text(L("默认使用英文，可随时切换语言。")).font(.caption).foregroundStyle(.secondary)
                }
                Section(L("菜单栏")) {
                    Toggle(L("显示运行中容器数量"), isOn: $showCount)
                    Toggle(L("显示容器 CPU 用量"), isOn: $showCPU)
                    Toggle(L("显示容器内存用量"), isOn: $showMemory)
                    LabeledContent(L("预览")) { MenuBarLabel().environmentObject(store).padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 6)) }
                }
                Section(L("刷新与启动")) {
                    Picker(L("自动刷新间隔"), selection: $refreshInterval) { ForEach([5,10,15,30,60], id: \.self) { Text(L("\($0) 秒")).tag($0) } }
                    Toggle(L("登录时打开 Colima View"), isOn: $loginEnabled).onChange(of: loginEnabled) { _, enabled in
                        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { message = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
                    }
                    if SMAppService.mainApp.status == .requiresApproval { Button(L("前往系统设置允许登录项")) { SMAppService.openSystemSettingsLoginItems() } }
                    Text(L("关闭主窗口后，菜单栏仍会运行。退出客户端不会停止 Colima 或容器。")).font(.caption).foregroundStyle(.secondary)
                }
                if let message { Text(message).font(.caption).foregroundStyle(.orange) }
            }.formStyle(.grouped).tabItem { Label(L("通用"), systemImage: "slider.horizontal.3") }
            Form {
                Section(L("本机依赖")) {
                    executableRow("Colima", value: store.service.tools.colima, key: "colimaPath")
                    executableRow("Docker", value: store.service.tools.docker, key: "dockerPath")
                    Button(L("重新检测并连接")) { store.refresh() }
                    Text(L("客户端直接复用已安装的工具，不创建额外的虚拟机。Docker 操作始终指向当前选择的实例。")).font(.caption).foregroundStyle(.secondary)
                }
                Section(L("Colima 下载代理")) {
                    TextField(L("HTTP / HTTPS 代理"), text: $downloadProxy, prompt: Text("http://127.0.0.1:7890"))
                    Text(L("可留空。仅用于客户端启动 Colima 时的宿主机网络请求，不修改系统代理。")).font(.caption).foregroundStyle(.secondary)
                    if !downloadProxy.isEmpty && !validProxy(downloadProxy) { Text(L("请输入 http:// 或 https:// 代理地址。")).font(.caption).foregroundStyle(.orange) }
                }
                Section(L("当前实例的网络代理")) {
                    TextField(L("虚拟机代理"), text: $vmProxy, prompt: Text(L("留空以禁用")))
                    Text(L("本机代理可填写 http://host.lima.internal:端口。应用后会重启当前实例。")).font(.caption).foregroundStyle(.secondary)
                    Button(L("应用到 \(store.selectedProfileName)…")) { applyProxy = true }.disabled(store.currentProfile == nil || store.isBusy || (!vmProxy.isEmpty && !validProxy(vmProxy)))
                }
                if let message { Text(message).font(.caption).foregroundStyle(.orange) }
            }.formStyle(.grouped).tabItem { Label(L("连接"), systemImage: "network") }
            VStack(spacing: 16) {
                Image(systemName: "shippingbox.fill").font(.system(size: 56)).foregroundStyle(Palette.accent)
                Text("Colima View").font(.largeTitle.weight(.semibold))
                Text(L("原生 macOS 容器工作空间")).foregroundStyle(.secondary)
                Text(L("版本 1.0.0 · macOS 14+")).font(.caption).foregroundStyle(.secondary)
                Divider().frame(width: 200)
                Text(L("本地运行，无账户、无遥测。\n基于 Colima、Docker CLI 和 SwiftUI。\n本项目是独立客户端，与 Docker 和 Colima 官方无隶属关系。"))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Link(L("Colima 项目"), destination: URL(string: "https://github.com/abiosoft/colima")!)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).tabItem { Label(L("关于"), systemImage: "info.circle") }
        }.frame(width: 620, height: 590)
            .onAppear { vmProxy = store.snapshot?.info.HTTPProxy ?? "" }
            .confirmationDialog(L("应用代理配置？"), isPresented: $applyProxy, titleVisibility: .visible) {
                Button(L("保存并重启实例")) { saveProxy() }; Button(L("取消"), role: .cancel) {}
            } message: { Text(L("当前实例中的运行容器会短暂中断，数据会保留。")) }
    }
    private func executableRow(_ title: String, value: String?, key: String) -> some View {
        LabeledContent(title) {
            HStack { Text(value ?? L("未找到")).font(.caption.monospaced()).foregroundStyle(value == nil ? Color.orange : .secondary).lineLimit(1).truncationMode(.middle); Button(L("选择…")) {
                if let url = chooseFile() {
                    guard FileManager.default.isExecutableFile(atPath: url.path) else { message = L("所选文件不可执行。"); return }
                    UserDefaults.standard.set(url.path, forKey: key)
                    if key == "colimaPath" { colimaPath = url.path } else { dockerPath = url.path }
                    store.refresh()
                }
            } }
        }
    }
    private func saveProxy() {
        guard let profile = store.currentProfile else { return }
        var specs: [CommandSpec] = []
        if profile.isRunning { specs.append(CommandSpec(.colima, ["stop", "--profile", profile.name], timeout: 180)) }
        specs.append(CommandSpec(.colima, ["start", "--profile", profile.name, "--activate=false", "--env", "http_proxy=\(vmProxy),https_proxy=\(vmProxy)"], timeout: 1800))
        store.execute(L("更新 \(profile.name) 的网络代理"), specs: specs)
        message = L("正在应用配置，进度可在主窗口查看。")
    }
}
