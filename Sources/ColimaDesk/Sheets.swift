import SwiftUI
import ColimaCore

struct ProfileEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let profile: ColimaProfile?
    @State private var name: String
    @State private var cpus: Int
    @State private var memory: Double
    @State private var disk: Int
    @State private var proxy = ""
    @State private var confirmRestart = false
    init(profile: ColimaProfile?) {
        self.profile = profile
        _name = State(initialValue: profile?.name ?? "")
        _cpus = State(initialValue: profile?.cpus ?? 2)
        _memory = State(initialValue: profile?.memoryGiB ?? 2)
        _disk = State(initialValue: profile?.diskGiB ?? 20)
    }
    var valid: Bool { InputValidation.profileName(name) && (profile != nil || !store.profiles.contains { $0.name == name }) && (proxy.isEmpty || validProxy(proxy)) }
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: profile == nil ? L("新建 Colima 实例") : L("调整 \(name) 的资源"), subtitle: L("每个实例拥有独立的容器、镜像和数据盘。"))
            Form {
                Section(L("基本信息")) {
                    TextField(L("实例名称"), text: $name, prompt: Text(L("例如 dev"))).disabled(profile != nil)
                    if !name.isEmpty && !InputValidation.profileName(name) { Text(L("使用小写字母开头，最多 32 个小写字母、数字或连字符。")).font(.caption).foregroundStyle(.orange) }
                    if profile == nil && store.profiles.contains(where: { $0.name == name }) { Text(L("该名称已被使用。")).font(.caption).foregroundStyle(.orange) }
                    LabeledContent(L("运行时"), value: profile?.runtime ?? "Docker")
                    LabeledContent(L("虚拟化"), value: profile == nil ? "Apple Virtualization" : L("保持现有配置"))
                }
                Section(L("资源分配")) {
                    Stepper(L("CPU：\(cpus) 核"), value: $cpus, in: 1...max(cpus, ProcessInfo.processInfo.processorCount))
                    Stepper(L("内存：\(String(format: "%.1f", memory)) GiB"), value: $memory, in: 1...max(memory, max(2, Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 - 2)), step: 0.5)
                    Stepper(L("数据盘：\(disk) GiB"), value: $disk, in: max(5, profile?.diskGiB ?? 5)...max(2048, disk), step: 5)
                    Text(L("数据盘按需占用本机空间，创建后只能扩大。根文件系统另有独立磁盘。")).font(.caption).foregroundStyle(.secondary)
                }
                if profile == nil {
                    Section(L("网络代理（可选）")) {
                        TextField(L("HTTP 代理"), text: $proxy, prompt: Text("http://127.0.0.1:7890"))
                        Text(L("用于虚拟机内的网络请求。现有实例的代理配置会保留。")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if profile?.isRunning == true { Label(L("保存后会重启该实例，容器会短暂中断。"), systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
            }.formStyle(.grouped)
            Divider()
            HStack { Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(profile == nil ? L("创建并启动") : L("保存配置")) {
                if profile?.isRunning == true { confirmRestart = true } else { save() }
            }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!valid || store.isBusy) }.padding(20)
        }.frame(width: 560, height: profile == nil ? 600 : 540)
            .confirmationDialog(L("保存并重启 \(name)？"), isPresented: $confirmRestart, titleVisibility: .visible) { Button(L("保存并重启")) { save() }; Button(L("取消"), role: .cancel) {} } message: { Text(L("该实例中的运行容器会短暂中断。已存储的数据会保留。")) }
    }
    private func save() {
        var args = ["start", "--profile", name, "--cpus", String(cpus), "--memory", String(memory), "--disk", String(disk), "--activate=false"]
        if profile == nil {
            args += ["--vm-type", "vz", "--runtime", "docker"]
            if !proxy.isEmpty { args += ["--env", "http_proxy=\(proxy),https_proxy=\(proxy)"] }
        }
        var specs: [CommandSpec] = []
        if profile?.isRunning == true { specs.append(CommandSpec(.colima, ["stop", "--profile", name], timeout: 180)) }
        specs.append(CommandSpec(.colima, args, timeout: 1800))
        dismiss()
        store.execute(profile == nil ? L("创建实例 \(name)") : L("更新实例 \(name)"), specs: specs, selectAfter: name)
    }
}

func validProxy(_ value: String) -> Bool {
    guard let url = URL(string: value), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { return false }
    return !value.contains(",") && !value.contains(where: \.isWhitespace)
}

struct PullImageView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var reference = ""
    @State private var platform = ""
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: L("拉取镜像"), subtitle: L("镜像将下载到 \(store.selectedProfileName) 实例中。"))
            Form {
                TextField(L("镜像名称"), text: $reference, prompt: Text("nginx:alpine"))
                Picker(L("平台"), selection: $platform) { Text(L("自动选择（推荐）")).tag(""); Text("Linux / ARM64").tag("linux/arm64"); Text("Linux / AMD64").tag("linux/amd64") }
                Text(L("支持 Docker Hub 名称、私有仓库地址和 digest。下载进度可在活动记录中查看。")).font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped)
            Divider()
            HStack { Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(L("拉取镜像")) {
                let args = ["pull"] + (platform.isEmpty ? [] : ["--platform", platform]) + ["--", reference]
                dismiss(); store.dockerAction(L("拉取 \(reference)"), args: args, timeout: 1800)
            }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!InputValidation.imageReference(reference)) }.padding(20)
        }.frame(width: 540, height: 330)
    }
}

struct RunContainerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var image: String
    @State private var name = ""
    @State private var ports = ""
    @State private var environment = ""
    @State private var mounts = ""
    @State private var command = ""
    @State private var network = ""
    @State private var restart = "no"
    @State private var showAdvanced = false
    init(initialImage: String) { _image = State(initialValue: initialImage) }
    private func lines(_ text: String) -> [String] { text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    var validation: String? {
        if !InputValidation.imageReference(image) { return L("请输入有效的镜像名称。") }
        if !name.isEmpty && !InputValidation.resourceName(name) { return L("容器名称只能包含字母、数字、点、下划线和连字符。") }
        if !lines(ports).allSatisfy(InputValidation.port) { return L("端口格式为 8080:80，可添加 127.0.0.1: 前缀或 /udp 后缀。") }
        if !lines(environment).allSatisfy(InputValidation.environment) { return L("环境变量格式为 KEY=value，每行一个。") }
        if !lines(mounts).allSatisfy({ value in
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            return (2...3).contains(parts.count) && !parts[0].isEmpty && parts[1].hasPrefix("/") && (parts.count == 2 || ["ro", "rw"].contains(String(parts[2])))
        }) { return L("挂载格式为 本机路径或卷名:/容器路径，可追加 :ro。") }
        return nil
    }
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: L("运行新容器"), subtitle: L("配置应用需要的端口、数据和环境变量。"))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    applicationSettings
                    Card {
                        multilineField(L("端口映射"), text: $ports, prompt: "8080:80", hint: L("每行一条，格式为本机端口:容器端口。填写 127.0.0.1:8080:80 可仅允许本机访问。"))
                    }
                    DisclosureGroup(isExpanded: $showAdvanced) {
                        advancedSettings.padding(.top, 12)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("更多配置")).font(.headline)
                            Text(L("环境变量、数据挂载、网络与启动命令")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(20)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1))
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
            .frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: 16) {
                Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Text(validation ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Button(L("运行容器"), systemImage: "play.fill") { run() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(validation != nil || store.isBusy).fixedSize()
            }.padding(20)
        }.frame(width: 660, height: 650)
    }
    private var applicationSettings: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("应用")).font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("镜像")).font(.callout.weight(.medium))
                    HStack(spacing: 10) {
                        TextField(L("镜像"), text: $image, prompt: Text("nginx:alpine")).labelsHidden().textFieldStyle(.roundedBorder)
                        Menu(L("本地镜像")) {
                            ForEach(store.images.filter { $0.Repository != "<none>" }) { local in
                                Button(local.reference) { image = local.reference }
                            }
                        }.fixedSize().disabled(store.images.allSatisfy { $0.Repository == "<none>" })
                    }
                }
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("名称（可选）")).font(.callout.weight(.medium))
                        TextField(L("名称（可选）"), text: $name, prompt: Text(L("自动生成名称"))).labelsHidden().textFieldStyle(.roundedBorder)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("重启策略")).font(.callout.weight(.medium))
                        Picker(L("重启策略"), selection: $restart) {
                            Text(L("不自动重启")).tag("no"); Text(L("除非手动停止")).tag("unless-stopped")
                            Text(L("始终重启")).tag("always"); Text(L("失败时重启")).tag("on-failure")
                        }.labelsHidden().frame(maxWidth: .infinity)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            multilineField(L("环境变量"), text: $environment, prompt: "KEY=value", hint: L("每行一个环境变量，例如 TZ=Asia/Shanghai。"))
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                multilineField(L("数据挂载"), text: $mounts, prompt: L("本机路径或卷名:/容器路径"), hint: L("每行一条，可在末尾添加 :ro 设为只读。"))
                Button(L("选择本机文件夹…"), systemImage: "folder") {
                    if let url = chooseFile(directories: true) { mounts += (mounts.isEmpty ? "" : "\n") + url.path + ":/data" }
                }
                Text(L("选择后默认挂载到 /data，可在上方修改。")).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(L("网络")).font(.callout.weight(.medium))
                Picker(L("网络"), selection: $network) {
                    Text(L("默认 bridge")).tag("")
                    ForEach(store.snapshot?.networks ?? []) { item in Text(item.Name).tag(item.Name) }
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            multilineField(L("启动命令（可选）"), text: $command, prompt: L("可执行文件\n参数"), hint: L("每行一个参数，留空使用镜像的默认命令。"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func multilineField(_ title: String, text: Binding<String>, prompt: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.callout.weight(.medium))
            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(4)
                    .accessibilityLabel(title)
                if text.wrappedValue.isEmpty {
                    Text(prompt).font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary).padding(.horizontal, 9).padding(.vertical, 8)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .frame(height: 76)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15), lineWidth: 1))
            Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func run() {
        var args = ["run", "--detach", "--restart", restart]
        if !name.isEmpty { args += ["--name", name] }
        if !network.isEmpty { args += ["--network", network] }
        args += lines(ports).flatMap { ["--publish", $0] }
        args += lines(environment).flatMap { ["--env", $0] }
        args += lines(mounts).flatMap { ["--volume", $0] }
        args += ["--", image] + lines(command)
        dismiss(); store.dockerAction(L("运行 \(name.isEmpty ? image : name)"), args: args, timeout: 1800)
    }
}

struct ContainerDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let container: DockerContainer
    @State private var tab = 1
    @State private var follow = true
    @State private var text = ""
    @State private var error: String?
    @State private var filter = ""
    var live: DockerContainer { store.containers.first { $0.ID == container.ID } ?? container }
    var displayed: String { filter.isEmpty ? text : text.split(whereSeparator: \.isNewline).filter { $0.localizedCaseInsensitiveContains(filter) }.joined(separator: "\n") }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill").font(.title2).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 6) { Text(container.Names).font(.title2.weight(.semibold)); Text(container.Image).font(.caption).foregroundStyle(.secondary) }
                Spacer(); StatusBadge(text: live.isRunning ? L("运行中") : live.isPaused ? L("已暂停") : L("已停止"), color: live.isRunning ? .green : .secondary)
                Button(L("完成")) { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            HStack {
                Picker(L("详情"), selection: $tab) { Text(L("概览")).tag(0); Text(L("日志")).tag(1); Text("Inspect").tag(2) }.pickerStyle(.segmented).frame(width: 250)
                Spacer()
                if tab == 1 { TextField(L("过滤日志…"), text: $filter).textFieldStyle(.roundedBorder).frame(width: 160); Toggle(L("自动刷新"), isOn: $follow).toggleStyle(.checkbox) }
                if tab != 0 { Button { copyText(displayed) } label: { Image(systemName: "doc.on.doc") }.help(L("复制内容")); Button { export() } label: { Image(systemName: "square.and.arrow.up") }.help(L("导出内容")) }
            }.padding(.horizontal, 24).padding(.bottom, 16)
            Divider()
            if let error { Text(error).font(.caption).foregroundStyle(.orange).padding(10) }
            if tab == 0 {
                Form {
                    LabeledContent(L("容器名称"), value: live.Names)
                    LabeledContent(L("镜像"), value: live.Image)
                    LabeledContent(L("容器 ID")) { Text(live.ID).font(.caption.monospaced()).textSelection(.enabled) }
                    LabeledContent(L("状态"), value: live.Status)
                    LabeledContent(L("端口"), value: live.Ports.isEmpty ? L("未发布端口") : live.Ports)
                    if let project = live.project { LabeledContent(L("Compose 项目"), value: project) }
                    HStack {
                        Button(live.isRunning ? L("停止容器") : live.isPaused ? L("恢复容器") : L("启动容器")) { store.containerAction(live.isPaused ? "unpause" : live.isRunning ? "stop" : "start", live) }
                        Button(L("重启容器")) { store.containerAction("restart", live) }
                        ForEach(live.webPorts.prefix(2), id: \.self) { port in Link(L("打开 :\(port)"), destination: URL(string: "http://127.0.0.1:\(port)")!) }
                    }.disabled(store.isBusy)
                }.formStyle(.grouped)
            } else {
                ScrollViewReader { reader in
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(displayed.isEmpty ? L("暂无输出") : displayed).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            Color.clear.frame(height: 1).id("end")
                        }.padding(16)
                    }.background(Color(nsColor: .textBackgroundColor))
                        .onChange(of: text) { _, _ in if tab == 1 && follow { reader.scrollTo("end", anchor: .bottom) } }
                }
            }
        }.frame(width: 860, height: 610)
            .task(id: "\(tab)-\(follow)") {
                guard tab != 0 else { return }
                text = ""; error = nil
                repeat {
                    guard !Task.isCancelled, let profile = store.currentProfile else { return }
                    do {
                        let output = tab == 1 ? try await store.service.logs(profile, container: container.ID) : try await store.service.inspect(profile, kind: "container", id: container.ID)
                        if !Task.isCancelled { text = output; error = nil }
                    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                    if !follow || tab != 1 { return }
                    try? await Task.sleep(for: .seconds(3))
                } while !Task.isCancelled
            }
    }
    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(container.Names).\(tab == 1 ? "log" : "json")"
        if panel.runModal() == .OK, let url = panel.url {
            do { try displayed.write(to: url, atomically: true, encoding: .utf8) }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct InspectView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let request: InspectRequest
    @State private var text = L("正在读取…")
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(request.title).font(.headline).lineLimit(1); Spacer(); Button(L("复制")) { copyText(text) }; Button(L("完成")) { dismiss() }.keyboardShortcut(.cancelAction) }.padding(20)
            Divider(); CodeBlock(text: text)
        }.frame(width: 800, height: 570)
            .task { guard let profile = store.currentProfile else { return }; do { text = try await store.service.inspect(profile, kind: request.kind, id: request.identifier) } catch { text = error.localizedDescription } }
    }
}

struct ComposeDeployView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var url: URL?
    @State private var preview = ""
    @State private var name = ""
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: L("部署 Compose 项目"), subtitle: L("选择本机的 compose.yaml 或 docker-compose.yml。"))
            HStack { Button(L("选择 Compose 文件…"), systemImage: "folder") {
                if let chosen = chooseFile(extensions: ["yaml", "yml"]) {
                    do { preview = try String(contentsOf: chosen, encoding: .utf8); url = chosen; error = nil }
                    catch { self.error = error.localizedDescription }
                }
            }; Text(url?.path ?? L("尚未选择文件")).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }.padding(.horizontal, 24)
            TextField(L("项目名称（可选）"), text: $name, prompt: Text(L("默认使用所在文件夹名称"))).textFieldStyle(.roundedBorder).padding(.horizontal, 24).padding(.vertical, 16)
            Divider(); CodeBlock(text: preview.isEmpty ? L("选择文件后，可以在这里预览配置。") : preview)
            if let error { Text(error).font(.caption).foregroundStyle(.orange).padding(10) }
            Divider()
            HStack { Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Text(L("会拉取所需镜像并在后台启动服务")).font(.caption).foregroundStyle(.secondary); Button(L("部署项目")) {
                guard let url else { return }
                var args = ["compose", "--file", url.path]
                if !name.isEmpty { args += ["--project-name", name] }
                args += ["up", "--detach"]
                dismiss(); store.dockerAction(L("部署 Compose 项目"), args: args, timeout: 1800)
            }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(url == nil || (!name.isEmpty && !InputValidation.resourceName(name))) }.padding(20)
        }.frame(width: 740, height: 590)
    }
}

struct CreateResourceView: View {
    enum Kind { case volume, network }
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let kind: Kind
    @State private var name = ""
    @State private var internalNetwork = false
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: kind == .volume ? L("新建存储卷") : L("新建网络"), subtitle: kind == .volume ? L("使用本地驱动保存持久化数据。") : L("创建一个隔离的 bridge 网络。"))
            Form {
                TextField(L("名称"), text: $name)
                if kind == .network { Toggle(L("仅内部通信"), isOn: $internalNetwork); Text(L("启用后，此网络内的容器无法直接访问外部网络。")).font(.caption).foregroundStyle(.secondary) }
            }.formStyle(.grouped)
            Divider()
            HStack { Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(L("创建")) {
                let args = kind == .volume ? ["volume", "create", "--", name] : ["network", "create", "--driver", "bridge"] + (internalNetwork ? ["--internal"] : []) + ["--", name]
                dismiss(); store.dockerAction(L("创建\(kind == .volume ? L("存储卷") : L("网络")) \(name)"), args: args)
            }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!InputValidation.resourceName(name)) }.padding(20)
        }.frame(width: 500, height: kind == .volume ? 260 : 330)
    }
}

struct ProgressDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack { if store.isBusy { ProgressView().controlSize(.small) }; Text(store.activity.first?.title ?? L("操作详情")).font(.headline); Spacer(); Button(L("复制输出")) { copyText(store.activeLog) }; Button(L("关闭")) { dismiss() }.keyboardShortcut(.cancelAction) }.padding(20)
            Divider(); CodeBlock(text: store.activeLog)
            HStack { Text(store.isBusy ? L("操作会在后台继续，你可以关闭此窗口。") : L("操作已结束。详细输出也保留在活动记录中。")).font(.caption).foregroundStyle(.secondary); Spacer() }.padding(14)
        }.frame(width: 800, height: 520)
    }
}
