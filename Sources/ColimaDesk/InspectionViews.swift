import SwiftUI
import ColimaCore

struct DetailRow: View {
    let title: String
    let value: String?
    var monospaced = false
    var copyable = false
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Text(title).foregroundStyle(.secondary).frame(width: 138, alignment: .leading)
            Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? "—")
                .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 12))
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if copyable, let value, !value.isEmpty { CopyButton(text: value) }
        }.font(.system(size: 12)).padding(.vertical, 6)
    }
}

struct CopyButton: View {
    let text: String
    @State private var copied = false
    var body: some View {
        SmallIconButton(title: copied ? L("已复制") : L("复制内容"), icon: copied ? "checkmark" : "doc.on.doc") {
            copyText(text); copied = true
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { copied = false }
        }
    }
}

struct DetailCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        Card {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical).foregroundStyle(Palette.accent).padding(.bottom, 8)
            content()
        }
    }
}

struct InspectionSummary: View {
    let kind: String
    let document: DockerInspection
    private var root: InspectionValue { document.root }
    var body: some View {
        switch kind {
        case "container": containerSummary
        case "image": imageSummary
        case "volume": volumeSummary
        case "network": networkSummary
        default: EmptyState(title: L("暂无详情"), description: L("可以在原始 JSON 标签页查看完整数据。"), icon: "doc.text")
        }
    }
    private var containerSummary: some View {
        VStack(spacing: 16) {
            DetailCard(title: L("基本信息"), icon: "shippingbox") {
                DetailRow(title: L("容器名称"), value: document.string("Name")?.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                DetailRow(title: L("容器 ID"), value: document.string("Id"), monospaced: true, copyable: true)
                DetailRow(title: L("镜像引用"), value: document.string("Config", "Image"), copyable: true)
                DetailRow(title: L("创建时间"), value: dateText(document.string("Created")))
                DetailRow(title: L("状态"), value: document.string("State", "Status"))
                DetailRow(title: "PID", value: document.string("State", "Pid"))
                DetailRow(title: L("健康状态"), value: document.string("State", "Health", "Status") ?? L("未配置健康检查"))
                if let error = document.string("State", "Error"), !error.isEmpty { DetailRow(title: L("错误信息"), value: error) }
                if root["State"]["ExitCode"].number != nil && root["State"]["Running"].bool != true {
                    DetailRow(title: L("退出代码"), value: document.string("State", "ExitCode"))
                }
                DetailRow(title: L("重启次数"), value: document.string("RestartCount"))
            }
            ports
            mounts
            connections
        }
    }
    private var imageSummary: some View {
        VStack(spacing: 16) {
            DetailCard(title: L("镜像信息"), icon: "square.stack.3d.up") {
                DetailRow(title: L("镜像 ID"), value: document.string("Id"), monospaced: true, copyable: true)
                DetailRow(title: L("创建时间"), value: dateText(document.string("Created")))
                DetailRow(title: L("大小"), value: root["Size"].number.map(ByteSize.format))
                DetailRow(title: L("平台"), value: [document.string("Os"), document.string("Architecture"), document.string("Variant")].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " / "))
                DetailRow(title: L("文件系统层数"), value: String(root["RootFS"]["Layers"].array.count))
                DetailRow(title: L("镜像标签"), value: root["RepoTags"].strings.joined(separator: "\n"), monospaced: true)
                DetailRow(title: L("镜像摘要"), value: root["RepoDigests"].strings.joined(separator: "\n"), monospaced: true)
            }
            DetailCard(title: L("公开端口"), icon: "point.3.connected.trianglepath.dotted") {
                if root["Config"]["ExposedPorts"].entries.isEmpty { detailEmpty(L("镜像未声明公开端口。")) }
                ForEach(root["Config"]["ExposedPorts"].entries) { port in
                    DetailRow(title: port.key, value: L("未发布到主机"), monospaced: true)
                }
            }
        }
    }
    private var volumeSummary: some View {
        VStack(spacing: 16) {
            DetailCard(title: L("存储卷信息"), icon: "externaldrive") {
                DetailRow(title: L("名称"), value: document.string("Name"), copyable: true)
                DetailRow(title: L("驱动"), value: document.string("Driver"))
                DetailRow(title: L("作用域"), value: document.string("Scope"))
                DetailRow(title: L("创建时间"), value: dateText(document.string("CreatedAt")))
                DetailRow(title: L("虚拟机内的挂载路径"), value: document.string("Mountpoint"), monospaced: true, copyable: true)
            }
            DictionaryDetailCard(title: L("驱动选项"), icon: "slider.horizontal.3", value: root["Options"])
            DictionaryDetailCard(title: L("标签"), icon: "tag", value: root["Labels"])
        }
    }
    private var networkSummary: some View {
        VStack(spacing: 16) {
            DetailCard(title: L("网络信息"), icon: "point.3.connected.trianglepath.dotted") {
                DetailRow(title: L("名称"), value: document.string("Name"))
                DetailRow(title: L("网络 ID"), value: document.string("Id"), monospaced: true, copyable: true)
                DetailRow(title: L("驱动"), value: document.string("Driver"))
                DetailRow(title: L("作用域"), value: document.string("Scope"))
                DetailRow(title: L("创建时间"), value: dateText(document.string("Created")))
                DetailRow(title: L("仅内部通信"), value: boolText(root["Internal"].bool))
                DetailRow(title: "IPv6", value: boolText(root["EnableIPv6"].bool))
                DetailRow(title: L("可手动连接"), value: boolText(root["Attachable"].bool))
            }
            DetailCard(title: L("地址分配"), icon: "network") {
                DetailRow(title: L("驱动"), value: document.string("IPAM", "Driver"))
                ForEach(Array(root["IPAM"]["Config"].array.enumerated()), id: \.offset) { _, subnet in
                    Divider()
                    DetailRow(title: L("子网"), value: subnet["Subnet"].string, monospaced: true)
                    DetailRow(title: L("网关"), value: subnet["Gateway"].string, monospaced: true)
                    if let range = subnet["IPRange"].string, !range.isEmpty { DetailRow(title: L("地址范围"), value: range, monospaced: true) }
                }
            }
            DetailCard(title: L("已连接的容器"), icon: "shippingbox") {
                if root["Containers"].entries.isEmpty { detailEmpty(L("暂无容器连接到此网络。")) }
                ForEach(root["Containers"].entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.value["Name"].string ?? String(entry.key.prefix(12))).font(.callout.weight(.medium))
                        DetailRow(title: "IPv4", value: entry.value["IPv4Address"].string, monospaced: true)
                        DetailRow(title: "IPv6", value: entry.value["IPv6Address"].string, monospaced: true)
                    }.padding(.vertical, 5)
                }
            }
            DictionaryDetailCard(title: L("驱动选项"), icon: "slider.horizontal.3", value: root["Options"])
            DictionaryDetailCard(title: L("标签"), icon: "tag", value: root["Labels"])
        }
    }
    private var ports: some View {
        DetailCard(title: L("端口映射"), icon: "arrow.left.arrow.right") {
            if document.ports.isEmpty { detailEmpty(L("未发布端口")) }
            ForEach(document.ports) { port in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(port.hostPort.map { "\(port.hostIP.isEmpty ? "0.0.0.0" : port.hostIP):\($0)" } ?? L("未发布到主机"))
                            .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        Text(L("主机地址")).font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(port.containerPort).font(.system(size: 12, design: .monospaced))
                        Text(L("容器端口")).font(.caption2).foregroundStyle(.secondary)
                    }.frame(width: 150, alignment: .leading)
                    if let url = port.browserURL {
                        SmallIconButton(title: L("在浏览器中打开"), icon: "arrow.up.right") { NSWorkspace.shared.open(url) }
                    } else { Color.clear.frame(width: 32, height: 32).accessibilityHidden(true) }
                }.padding(12).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    private var mounts: some View {
        DetailCard(title: L("数据挂载"), icon: "externaldrive") {
            if root["Mounts"].array.isEmpty { detailEmpty(L("未配置数据挂载。")) }
            ForEach(Array(root["Mounts"].array.enumerated()), id: \.offset) { _, mount in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(mount["Destination"].string ?? "—").font(.callout.monospaced().weight(.medium)).textSelection(.enabled)
                        Spacer()
                        StatusBadge(text: mount["RW"].bool == false ? L("只读") : L("可读写"), color: mount["RW"].bool == false ? .orange : Palette.accent)
                    }
                    DetailRow(title: L("来源"), value: mount["Source"].string, monospaced: true, copyable: true)
                    DetailRow(title: L("类型"), value: mount["Type"].string)
                    if let name = mount["Name"].string { DetailRow(title: L("卷名称"), value: name, monospaced: true) }
                }.padding(14).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    private var connections: some View {
        DetailCard(title: L("网络连接"), icon: "network") {
            if root["NetworkSettings"]["Networks"].entries.isEmpty { detailEmpty(L("没有网络连接信息。")) }
            ForEach(root["NetworkSettings"]["Networks"].entries) { network in
                VStack(alignment: .leading, spacing: 4) {
                    Text(network.key).font(.callout.weight(.semibold)).padding(.bottom, 4)
                    DetailRow(title: "IPv4", value: network.value["IPAddress"].string, monospaced: true, copyable: true)
                    DetailRow(title: "IPv6", value: network.value["GlobalIPv6Address"].string, monospaced: true)
                    DetailRow(title: L("网关"), value: network.value["Gateway"].string, monospaced: true)
                    DetailRow(title: L("网络别名"), value: network.value["Aliases"].strings.joined(separator: ", "), monospaced: true)
                }.padding(14).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct InspectionConfiguration: View {
    let kind: String
    let document: DockerInspection
    @State private var revealEnvironment = false
    private var root: InspectionValue { document.root }
    var body: some View {
        VStack(spacing: 16) {
            DetailCard(title: L("启动配置"), icon: "terminal") {
                DetailRow(title: L("入口程序"), value: root["Config"]["Entrypoint"].strings.joined(separator: "\n"), monospaced: true)
                DetailRow(title: L("默认命令"), value: root["Config"]["Cmd"].strings.joined(separator: "\n"), monospaced: true)
                DetailRow(title: L("工作目录"), value: document.string("Config", "WorkingDir"), monospaced: true)
                DetailRow(title: L("运行用户"), value: document.string("Config", "User").flatMap { $0.isEmpty ? nil : $0 } ?? L("镜像默认用户"))
                if kind == "container" {
                    DetailRow(title: L("重启策略"), value: document.string("HostConfig", "RestartPolicy", "Name"))
                    DetailRow(title: L("网络模式"), value: document.string("HostConfig", "NetworkMode"))
                    DetailRow(title: L("特权模式"), value: boolText(root["HostConfig"]["Privileged"].bool))
                    DetailRow(title: L("只读根文件系统"), value: boolText(root["HostConfig"]["ReadonlyRootfs"].bool))
                    DetailRow(title: L("内存限制"), value: memoryLimit)
                    DetailRow(title: L("CPU 限制"), value: cpuLimit)
                }
            }
            Card {
                HStack {
                    Label(L("环境变量"), systemImage: "text.alignleft").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.accent)
                    Spacer()
                    Toggle(L("显示变量值"), isOn: $revealEnvironment).toggleStyle(.switch).controlSize(.small)
                        .disabled(document.environment.isEmpty)
                }.padding(.bottom, 8)
                if document.environment.isEmpty { detailEmpty(L("未配置环境变量。")) }
                ForEach(document.environment) { variable in
                    HStack(alignment: .top, spacing: 16) {
                        Text(variable.key).font(.system(size: 12, weight: .medium, design: .monospaced)).frame(width: 200, alignment: .leading).textSelection(.enabled)
                        Text(revealEnvironment ? (variable.value.isEmpty ? L("空值") : variable.value) : "••••••••")
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if revealEnvironment { CopyButton(text: variable.value) }
                    }.padding(.vertical, 7)
                    if variable.id != document.environment.last?.id { Divider() }
                }
            }
            DictionaryDetailCard(title: L("标签"), icon: "tag", value: root["Config"]["Labels"])
        }
    }
    private var memoryLimit: String {
        guard let bytes = root["HostConfig"]["Memory"].number, bytes > 0 else { return L("不限制") }
        return ByteSize.format(bytes)
    }
    private var cpuLimit: String {
        let host = root["HostConfig"]
        if let nano = host["NanoCpus"].number, nano > 0 { return String(format: "%.2f", nano / 1_000_000_000) }
        if let quota = host["CpuQuota"].number, quota > 0, let period = host["CpuPeriod"].number, period > 0 {
            return String(format: "%.2f", quota / period)
        }
        return L("不限制")
    }
}

struct DictionaryDetailCard: View {
    let title: String
    let icon: String
    let value: InspectionValue
    var body: some View {
        DetailCard(title: title, icon: icon) {
            if value.entries.isEmpty { detailEmpty(L("未配置")) }
            ForEach(value.entries) { entry in
                let text = entry.value.scalar ?? entry.value.strings.joined(separator: "\n")
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(entry.key).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(text.isEmpty ? L("空值") : text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    CopyButton(text: "\(entry.key)=\(text)")
                }.padding(12).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct InspectionContent: View {
    let kind: String
    let identifier: String
    let tab: Int
    @EnvironmentObject var store: AppStore
    @State private var raw = ""
    @State private var document: DockerInspection?
    @State private var error: String?
    @State private var loading = true
    @State private var revision = 0
    var body: some View {
        Group {
            if loading {
                VStack(spacing: 14) { ProgressView(); Text(L("正在读取详情…")).font(.callout).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                EmptyState(title: L("无法加载详情"), description: error, icon: "exclamationmark.circle", actionTitle: L("重试")) { revision += 1 }
            } else if let document {
                if tab == 2 {
                    VStack(spacing: 0) {
                        HStack { Label(L("原始 JSON"), systemImage: "curlybraces").font(.caption).foregroundStyle(.secondary); Spacer(); CopyButton(text: raw) }.padding(.horizontal, 24).padding(.vertical, 10)
                        CodeBlock(text: raw)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if tab == 1 { InspectionConfiguration(kind: kind, document: document) }
                            else { InspectionSummary(kind: kind, document: document) }
                        }.padding(24)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
        .task(id: "\(store.selectedProfileName)-\(kind)-\(identifier)-\(revision)") {
            loading = true; error = nil
            guard let profile = store.currentProfile else { loading = false; error = L("未连接"); return }
            do {
                let output = try await store.service.inspect(profile, kind: kind, id: identifier)
                let parsed = try DockerInspection(json: output)
                guard !Task.isCancelled else { return }
                raw = output; document = parsed; loading = false
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription; loading = false
            }
        }
    }
}

struct InspectView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let request: InspectRequest
    @State private var tab = 0
    private var configurable: Bool { ["container", "image"].contains(request.kind) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: request.kind == "image" ? "square.stack.3d.up" : request.kind == "volume" ? "externaldrive" : "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 23, weight: .medium)).foregroundStyle(Palette.accent)
                    .frame(width: 48, height: 48).background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 5) {
                    Text(request.title).font(.title3.weight(.semibold)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Text(request.kind == "image" ? L("镜像详情") : request.kind == "volume" ? L("存储卷详情") : L("网络详情")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                SmallIconButton(title: L("关闭"), icon: "xmark") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            HStack {
                Picker(L("详情"), selection: $tab) {
                    Text(L("概览")).tag(0)
                    if configurable { Text(L("配置")).tag(1) }
                    Text(L("原始 JSON")).tag(2)
                }.pickerStyle(.segmented).labelsHidden().frame(width: configurable ? 310 : 230)
                Spacer()
            }.padding(.horizontal, 24).padding(.bottom, 18)
            Divider()
            InspectionContent(kind: request.kind, identifier: request.identifier, tab: tab)
        }.frame(width: 900, height: 700).modernControls()
            .onChange(of: store.selectedProfileName) { _, _ in dismiss() }
    }
}

private func detailEmpty(_ text: String) -> some View {
    Text(text).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
}

private func boolText(_ value: Bool?) -> String {
    guard let value else { return "—" }
    return value ? L("已启用") : L("已禁用")
}

private func dateText(_ value: String?) -> String? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    return date?.formatted(date: .abbreviated, time: .standard) ?? value
}
