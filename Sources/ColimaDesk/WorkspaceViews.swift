import SwiftUI
import ColimaCore

struct ProfilesView: View {
    @EnvironmentObject var store: AppStore
    @State private var create = false
    @State private var editing: ColimaProfile?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(L("\(store.profiles.count) 个实例")).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button { create = true } label: { Label(L("新建实例"), systemImage: "plus") }.buttonStyle(.deskPrimary).disabled(store.isBusy)
            }
            if store.profiles.isEmpty {
                EmptyState(title: L("创建你的第一个实例"), description: L("每个实例有独立的 Docker 环境、镜像和数据盘。"), icon: "desktopcomputer", actionTitle: L("新建实例")) { create = true }
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(store.profiles.filter { store.matches($0.name, $0.arch, $0.runtime) }) { profile in
                            Card {
                                HStack(alignment: .top, spacing: 16) {
                                    Image(systemName: "desktopcomputer").font(.system(size: 25)).foregroundStyle(Palette.accent)
                                        .frame(width: 52, height: 52).background(Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                                    VStack(alignment: .leading, spacing: 9) {
                                        HStack { Text(profile.name).font(.title3.weight(.semibold)); StatusBadge(text: profile.isRunning ? L("运行中") : L("已停止"), color: profile.isRunning ? .green : .secondary); if profile.name == store.selectedProfileName { Text(L("当前工作空间")).font(.caption).foregroundStyle(.secondary) } }
                                        Text(L("\(profile.cpus) 核 CPU  /  \(String(format: "%.0f", profile.memoryGiB)) GiB 内存  /  \(profile.diskGiB) GiB 数据盘"))
                                            .font(.callout).foregroundStyle(.secondary)
                                        Text("\(profile.arch) · \(profile.runtime)").font(.caption).foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    HStack(spacing: 10) {
                                        if profile.name != store.selectedProfileName { Button(L("切换")) { store.selectProfile(profile.name) }.buttonStyle(.deskSecondary) }
                                        Button { store.colimaAction(profile.isRunning ? "stop" : "start", profile: profile) } label: { Label(profile.isRunning ? L("停止") : L("启动"), systemImage: profile.isRunning ? "stop.fill" : "play.fill") }.buttonStyle(.deskSecondary)
                                        ActionMenu {
                                            Button(L("调整资源…"), systemImage: "slider.horizontal.3") { editing = profile }
                                            Button(L("重启实例"), systemImage: "arrow.clockwise") { store.colimaAction("restart", profile: profile) }.disabled(!profile.isRunning)
                                            Button(L("在 Finder 中查看配置"), systemImage: "folder") { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".colima/\(profile.name)")) }
                                            Divider()
                                            Button(L("删除实例…"), systemImage: "trash", role: .destructive) {
                                                store.confirmation = Confirmation(title: L("永久删除 \(profile.name)？"), message: L("该实例及其中的容器、镜像和存储卷数据将被永久删除。此操作无法撤销。"), button: L("永久删除实例")) {
                                                    store.execute(L("删除实例 \(profile.name)"), specs: [CommandSpec(.colima, ["delete", "--force", "--profile", profile.name], timeout: 180)])
                                                }
                                            }
                                    }
                                    }.disabled(store.isBusy)
                                }
                            }
                        }
                    }.padding(.bottom, 20)
                }
            }
        }.padding(.horizontal, 28).padding(.bottom, 20)
            .sheet(isPresented: $create) { ProfileEditor(profile: nil) }
            .sheet(item: $editing) { ProfileEditor(profile: $0) }
    }
}

struct ContainersView: View {
    @EnvironmentObject var store: AppStore
    @State private var filter = 0
    @State private var run = false
    @State private var selected: DockerContainer?
    var filtered: [DockerContainer] {
        store.containers.filter { (filter == 0 || (filter == 1 ? $0.isRunning : !$0.isRunning)) && store.matches($0.Names, $0.Image, $0.ID, $0.Ports) }
            .sorted { if $0.isRunning != $1.isRunning { return $0.isRunning }; return $0.Names < $1.Names }
    }
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Picker(L("状态"), selection: $filter) { Text(L("全部 \(store.containers.count)")).tag(0); Text(L("运行中")).tag(1); Text(L("已停止 / 暂停")).tag(2) }.pickerStyle(.segmented).labelsHidden().frame(width: 350)
                Spacer()
                Button { run = true } label: { Label(L("运行容器"), systemImage: "plus") }.buttonStyle(.deskPrimary).disabled(!store.dockerAvailable || store.isBusy)
            }
            if !store.dockerAvailable { EngineUnavailableView() }
            else if filtered.isEmpty { EmptyState(title: store.search.isEmpty ? L("这里还没有容器") : L("没有匹配的容器"), description: L("从本地镜像创建应用，或直接填写镜像名称运行。"), icon: "shippingbox", actionTitle: L("运行容器")) { run = true } }
            else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        HStack { Text(L("容器 / 镜像")); Spacer(); Text(L("资源用量")).frame(width: 135, alignment: .leading); Text(L("操作")).frame(width: 130, alignment: .trailing) }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 12)
                        ForEach(filtered) { container in
                            Divider()
                            ContainerRow(container: container) { selected = container }.padding(.horizontal, 16).padding(.vertical, 15).hoverSurface()
                        }
                    }.background(Palette.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
                }
            }
        }.padding(.horizontal, 28).padding(.bottom, 20)
            .sheet(isPresented: $run) { RunContainerView(initialImage: "") }
            .sheet(item: $selected) { ContainerDetailView(container: $0) }
    }
}

struct ContainerRow: View {
    @EnvironmentObject var store: AppStore
    let container: DockerContainer
    let detail: () -> Void
    var stats: ContainerStats? { store.stats.first { container.ID.hasPrefix($0.ID) || $0.ID.hasPrefix(container.ID) } }
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "shippingbox").font(.system(size: 20, weight: .medium)).foregroundStyle(container.isRunning ? Palette.accent : Color.secondary)
                .frame(width: 42, height: 42).background(Palette.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Button(container.Names, action: detail).font(.system(size: 13, weight: .semibold)).buttonStyle(.plain)
                    StatusBadge(text: container.isPaused ? L("已暂停") : container.isRunning ? L("运行中") : L("已停止"), color: container.isPaused ? .orange : container.isRunning ? .green : .secondary)
                }
                Text(container.Image).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !container.webPorts.isEmpty {
                    HStack(spacing: 9) { ForEach(container.webPorts.prefix(3), id: \.self) { port in
                        Link(destination: URL(string: "http://127.0.0.1:\(port)")!) {
                            Label { Text(verbatim: ":\(port)") } icon: { Image(systemName: "arrow.up.right") }
                        }.font(.caption2).buttonStyle(.deskQuiet)
                    } }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(stats.map { $0.CPUPerc + " CPU" } ?? "— CPU")
                Text(stats.map { ByteSize.format($0.memoryBytes) } ?? L("— 内存")).foregroundStyle(.secondary)
            }.font(.caption.monospacedDigit()).frame(width: 135, alignment: .leading)
            HStack(spacing: 9) {
                SmallIconButton(title: container.isRunning ? L("停止") : container.isPaused ? L("恢复") : L("启动"), icon: container.isRunning ? "stop.fill" : "play.fill") { store.containerAction(container.isPaused ? "unpause" : container.isRunning ? "stop" : "start", container) }
                SmallIconButton(title: L("详情"), icon: "info", action: detail)
                ActionMenu {
                    Button(L("重启"), systemImage: "arrow.clockwise") { store.containerAction("restart", container) }
                    Button(container.isPaused ? L("恢复") : L("暂停"), systemImage: "pause") { store.containerAction(container.isPaused ? "unpause" : "pause", container) }.disabled(!container.isRunning && !container.isPaused)
                    Button(L("复制容器 ID"), systemImage: "doc.on.doc") { copyText(container.ID) }
                    Divider()
                    Button(L("删除容器…"), systemImage: "trash", role: .destructive) { store.deleteContainer(container) }
                                }
            }.frame(width: 130, alignment: .trailing).disabled(store.isBusy)
        }
    }
}

struct InspectRequest: Identifiable { let id = UUID(); let kind: String; let identifier: String; let title: String }
struct ImageRunRequest: Identifiable { let id = UUID(); let image: String }

struct ImagesView: View {
    @EnvironmentObject var store: AppStore
    @State private var pull = false
    @State private var build = false
    @State private var inspect: InspectRequest?
    @State private var run: ImageRunRequest?
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(L("\(store.images.count) 个本地镜像")).font(.callout).foregroundStyle(.secondary)
                Spacer()
                DeskMenu(title: L("清理"), icon: "sparkles") {
                    Button(L("清理未使用的镜像…")) {
                        store.confirmation = Confirmation(title: L("清理未使用的镜像？"), message: L("所有未被容器引用的镜像会被删除，包括带有标签的镜像。之后使用时需要重新下载。"), button: L("清理镜像")) { store.dockerAction(L("清理未使用的镜像"), args: ["image", "prune", "--all", "--force"], timeout: 180) }
                    }
                    Button(L("清理构建缓存…")) {
                        store.confirmation = Confirmation(title: L("清理构建缓存？"), message: L("未使用的构建缓存会被删除，之后的构建可能需要更长时间。"), button: L("清理缓存")) { store.dockerAction(L("清理构建缓存"), args: ["builder", "prune", "--all", "--force"], timeout: 180) }
                    }
                }.disabled(!store.dockerAvailable || store.isBusy)
                Button { build = true } label: { Label(L("构建镜像"), systemImage: "hammer") }.buttonStyle(.deskSecondary).disabled(!store.dockerAvailable || store.isBusy)
                Button { pull = true } label: { Label(L("拉取镜像"), systemImage: "arrow.down") }.buttonStyle(.deskPrimary).disabled(!store.dockerAvailable || store.isBusy)
            }
            if !store.dockerAvailable { EngineUnavailableView() }
            else if store.images.filter({ store.matches($0.Repository, $0.Tag, $0.ID) }).isEmpty { EmptyState(title: L("准备你的第一个镜像"), description: L("填写镜像名称，例如 nginx:alpine，即可下载到当前实例。"), icon: "square.stack.3d.up", actionTitle: L("拉取镜像")) { pull = true } }
            else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.images.filter { store.matches($0.Repository, $0.Tag, $0.ID) }) { image in
                            HStack(spacing: 14) {
                                Image(systemName: "square.stack.3d.up").font(.title2).foregroundStyle(Palette.accent).frame(width: 36)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack { Text(image.Repository).font(.system(size: 13, weight: .semibold)); Text(image.Tag).font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(Palette.accent) }
                                    Text("\(image.ID) · \(image.CreatedSince)").font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Text(image.Size).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                                Button { run = ImageRunRequest(image: image.reference) } label: { Label(L("运行"), systemImage: "play.fill") }.buttonStyle(.deskSecondary)
                                ActionMenu {
                                    Button(L("镜像详情")) { inspect = InspectRequest(kind: "image", identifier: image.ID, title: image.reference) }
                                    Button(L("复制镜像名称")) { copyText(image.reference) }
                                    Divider()
                                    Button(L("删除镜像…"), role: .destructive) {
                                        store.confirmation = Confirmation(title: L("删除镜像 \(image.reference)？"), message: L("正在被容器使用的镜像不会被删除。"), button: L("删除镜像")) { store.dockerAction(L("删除镜像"), args: ["image", "rm", image.reference]) }
                                    }
                                }
                            }.padding(18).hoverSurface().disabled(store.isBusy)
                            Divider()
                        }
                    }.background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }.padding(.horizontal, 28).padding(.bottom, 20)
            .sheet(isPresented: $pull) { PullImageView() }
            .sheet(isPresented: $build) { BuildImageView() }
            .sheet(item: $inspect) { InspectView(request: $0) }
            .sheet(item: $run) { RunContainerView(initialImage: $0.image) }
    }
}

struct ComposeView: View {
    @EnvironmentObject var store: AppStore
    @State private var deploy = false
    var body: some View {
        VStack(spacing: 16) {
            HStack { Text(L("\(store.snapshot?.projects.count ?? 0) 个项目")).foregroundStyle(.secondary).font(.callout); Spacer(); Button { deploy = true } label: { Label(L("部署项目"), systemImage: "plus") }.buttonStyle(.deskPrimary).disabled(!store.dockerAvailable || store.isBusy) }
            if !store.dockerAvailable { EngineUnavailableView() }
            else if (store.snapshot?.projects ?? []).isEmpty { EmptyState(title: L("一次管理整个应用"), description: L("导入 Compose 文件，统一部署、启动和停止多个服务。"), icon: "square.stack.3d.up", actionTitle: L("部署 Compose 项目")) { deploy = true } }
            else {
                ScrollView { LazyVStack(spacing: 14) {
                    ForEach((store.snapshot?.projects ?? []).filter { store.matches($0.Name, $0.ConfigFiles) }) { project in
                        Card {
                            HStack {
                                Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(Palette.accent).frame(width: 40)
                                VStack(alignment: .leading, spacing: 7) { Text(project.Name).font(.headline); Text(project.Status).font(.caption).foregroundStyle(.secondary); Text(project.ConfigFiles).font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled) }
                                Spacer()
                                Button(L("启动")) { perform(project, ["up", "--detach"]) }
                                Button(L("停止")) { perform(project, ["stop"]) }
                                ActionMenu {
                                    Button(L("重启项目")) { perform(project, ["restart"]) }
                                    if let file = project.files.first { Button(L("在 Finder 中显示")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file)]) } }
                                    Divider()
                                    Button(L("移除项目容器…"), role: .destructive) {
                                        store.confirmation = Confirmation(title: L("移除项目 \(project.Name) 的容器？"), message: L("项目容器和默认网络会被移除，存储卷与镜像保留。"), button: L("移除项目容器")) { perform(project, ["down"]) }
                                    }
                                }
                            }.disabled(store.isBusy)
                        }
                    }
                } }
            }
        }.padding(.horizontal, 28).padding(.bottom, 20).sheet(isPresented: $deploy) { ComposeDeployView() }
    }
    private func perform(_ project: ComposeProject, _ args: [String]) {
        guard !project.files.isEmpty, project.files.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) else {
            store.notice = AppNotice(title: L("找不到项目文件"), message: L("Compose 配置文件不在本机原来的位置，请重新导入项目文件。")); return
        }
        store.dockerAction("\(project.Name) · \(args.first ?? "Compose")", args: DockerService.composeArguments(project, action: args), timeout: 1800)
    }
}

struct VolumesView: View {
    @EnvironmentObject var store: AppStore
    @State private var create = false
    @State private var inspect: InspectRequest?
    var body: some View {
        VStack(spacing: 16) {
            HStack { Text(L("容器的持久化数据")).font(.callout).foregroundStyle(.secondary); Spacer(); Button(L("查看存储占用"), systemImage: "chart.pie") { store.section = .storage }; Button(L("新建存储卷"), systemImage: "plus") { create = true }.buttonStyle(.deskPrimary).disabled(!store.dockerAvailable || store.isBusy) }
            if !store.dockerAvailable { EngineUnavailableView() }
            else if (store.snapshot?.volumes ?? []).isEmpty { EmptyState(title: L("暂无存储卷"), description: L("存储卷中的数据可以在容器删除后保留。"), icon: "externaldrive", actionTitle: L("新建存储卷")) { create = true } }
            else {
                ScrollView { LazyVStack(spacing: 0) {
                    ForEach((store.snapshot?.volumes ?? []).filter { store.matches($0.Name, $0.Driver) }) { volume in
                        HStack(spacing: 14) {
                            Image(systemName: "externaldrive").font(.title2).foregroundStyle(Palette.accent).frame(width: 36)
                            VStack(alignment: .leading, spacing: 6) { Text(volume.Name).font(.callout.weight(.medium)).lineLimit(1); Text("\(volume.Driver) · \(volume.Scope ?? "local")").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
                            Button(L("详情")) { inspect = InspectRequest(kind: "volume", identifier: volume.Name, title: volume.Name) }
                            SmallIconButton(title: L("删除存储卷"), icon: "trash", role: .destructive) {
                                store.confirmation = Confirmation(title: L("永久删除存储卷 \(volume.Name)？"), message: L("卷内所有数据将永久丢失。正在被容器使用的卷不会被删除。"), button: L("永久删除存储卷")) { store.dockerAction(L("删除存储卷"), args: ["volume", "rm", volume.Name]) }
                            }
                        }.padding(18).hoverSurface().disabled(store.isBusy)
                        Divider()
                    }
                }.background(Palette.card, in: RoundedRectangle(cornerRadius: 12)) }
            }
        }.padding(.horizontal, 28).padding(.bottom, 20)
            .sheet(isPresented: $create) { CreateResourceView(kind: .volume) }
            .sheet(item: $inspect) { InspectView(request: $0) }
    }
}

struct NetworksView: View {
    @EnvironmentObject var store: AppStore
    @State private var create = false
    @State private var inspect: InspectRequest?
    var body: some View {
        VStack(spacing: 16) {
            HStack { Text(L("\(store.snapshot?.networks.count ?? 0) 个网络")).font(.callout).foregroundStyle(.secondary); Spacer(); Button(L("新建网络"), systemImage: "plus") { create = true }.buttonStyle(.deskPrimary).disabled(!store.dockerAvailable || store.isBusy) }
            if !store.dockerAvailable { EngineUnavailableView() }
            else {
                ScrollView { LazyVStack(spacing: 0) {
                    ForEach((store.snapshot?.networks ?? []).filter { store.matches($0.Name, $0.Driver) }) { network in
                        HStack(spacing: 14) {
                            Image(systemName: "network").font(.title2).foregroundStyle(Palette.accent).frame(width: 36)
                            VStack(alignment: .leading, spacing: 6) { HStack { Text(network.Name).font(.callout.weight(.medium)); if network.isSystem { Text(L("系统")).font(.caption2).foregroundStyle(.secondary) } }; Text("\(network.Driver) · \(network.Scope)").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
                            Button(L("详情")) { inspect = InspectRequest(kind: "network", identifier: network.ID, title: network.Name) }
                            SmallIconButton(title: L("删除网络"), icon: "trash", role: .destructive) {
                                store.confirmation = Confirmation(title: L("删除网络 \(network.Name)？"), message: L("仍有容器连接的网络不会被删除。"), button: L("删除网络")) { store.dockerAction(L("删除网络"), args: ["network", "rm", network.ID]) }
                            }.disabled(network.isSystem)
                        }.padding(18).hoverSurface().disabled(store.isBusy)
                        Divider()
                    }
                }.background(Palette.card, in: RoundedRectangle(cornerRadius: 12)) }
            }
        }.padding(.horizontal, 28).padding(.bottom, 20)
            .sheet(isPresented: $create) { CreateResourceView(kind: .network) }
            .sheet(item: $inspect) { InspectView(request: $0) }
    }
}

struct ActivityView: View {
    @EnvironmentObject var store: AppStore
    @State private var selected: UUID?
    var body: some View {
        if store.activity.isEmpty { EmptyState(title: L("一切准备就绪"), description: L("操作进度、执行结果和诊断信息会显示在这里。活动记录仅在本次应用会话中保留。"), icon: "clock.arrow.circlepath") }
        else {
            HSplitView {
                List(store.activity, selection: $selected) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.succeeded == nil ? "clock" : entry.succeeded == true ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(entry.succeeded == false ? Color.orange : Palette.accent)
                        VStack(alignment: .leading, spacing: 6) { Text(entry.title).font(.callout.weight(.medium)); Text(entry.date.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 8).tag(entry.id)
                }.frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                let entry = store.activity.first(where: { $0.id == selected }) ?? store.activity.first
                VStack(spacing: 0) {
                    HStack { Text(entry?.title ?? L("操作详情")).font(.headline); Spacer(); Button(L("复制输出"), systemImage: "doc.on.doc") { copyText(entry?.output ?? "") } }.padding(18)
                    Divider(); CodeBlock(text: entry?.output ?? "")
                }
            }.padding(.horizontal, 28).padding(.bottom, 20)
        }
    }
}
