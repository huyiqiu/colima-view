import SwiftUI
import Charts
import ColimaCore

struct DashboardView: View {
    @EnvironmentObject var store: AppStore
    @State private var chartMemory = false
    @State private var detailContainer: DockerContainer?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 10) { Text(store.currentProfile?.name ?? L("欢迎使用")).font(.title3.weight(.semibold)); StatusBadge(text: store.currentProfile?.isRunning == true ? L("运行中") : L("已停止"), color: store.currentProfile?.isRunning == true ? .green : .secondary) }
                        Text(store.currentProfile.map { L("\($0.arch)  ·  \($0.cpus) 核 CPU  ·  \(String(format: "%.0f", $0.memoryGiB)) GiB 内存") } ?? L("创建或启动一个 Colima 实例，开始你的容器工作流。"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let profile = store.currentProfile {
                        Button { store.colimaAction(profile.isRunning ? "stop" : "start", profile: profile) } label: { Label(profile.isRunning ? L("停止实例") : L("启动实例"), systemImage: profile.isRunning ? "stop.fill" : "play.fill") }
                            .buttonStyle(.deskSecondary).disabled(store.isBusy)
                    } else { Button(L("管理实例")) { store.section = .profiles }.buttonStyle(.deskPrimary) }
                }
                HStack(spacing: 14) {
                    ResourceCard(title: L("运行中容器"), value: "\(store.runningContainers.count)", detail: L("共 \(store.containers.count) 个容器"), icon: "shippingbox")
                    ResourceCard(title: L("容器 CPU"), value: String(format: "%.1f%%", store.cpu), detail: L("100% 表示占用 1 个核心"), icon: "cpu")
                    ResourceCard(title: L("容器内存"), value: ByteSize.format(store.memory), detail: L("运行中容器的合计用量"), icon: "memorychip")
                    Button { store.section = .storage } label: {
                        ResourceCard(title: L("Mac 存储占用"), value: store.storageUsage?.hostAllocated.map(ByteSize.binary) ?? "—", detail: L("全部 Colima 实例 · 查看详情"), icon: "internaldrive")
                    }.buttonStyle(.plain).help(L("查看存储占用详情"))
                }
                Card {
                    SectionHeading(L("资源趋势")) {
                        Picker(L("指标"), selection: $chartMemory) { Text("CPU").tag(false); Text(L("内存")).tag(true) }.pickerStyle(.segmented).frame(width: 145)
                    }
                    if store.history.isEmpty {
                        VStack(spacing: 9) { Image(systemName: "waveform.path.ecg").font(.title2); Text(L("实例启动后将在这里显示实时用量")).font(.caption) }.foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 170)
                    } else {
                        Chart(store.history) { sample in
                            AreaMark(x: .value(L("时间"), sample.date), y: .value(chartMemory ? "MiB" : "%", chartMemory ? sample.memory : sample.cpu))
                                .foregroundStyle(LinearGradient(colors: [Palette.accent.opacity(0.16), Palette.accent.opacity(0.01)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.monotone)
                            LineMark(x: .value(L("时间"), sample.date), y: .value(chartMemory ? "MiB" : "%", chartMemory ? sample.memory : sample.cpu))
                                .foregroundStyle(Palette.accent).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.monotone)
                        }.chartYScale(domain: 0...max(chartMemory ? 32 : 10, (store.history.map { chartMemory ? $0.memory : $0.cpu }.max() ?? 0) * 1.2))
                            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { AxisValueLabel(format: .dateTime.hour().minute().second()); AxisGridLine() } }
                            .chartYAxis { AxisMarks(position: .trailing) }.frame(height: 175).padding(.top, 16)
                    }
                }
                HStack(alignment: .top, spacing: 18) {
                    Card {
                        SectionHeading(L("运行中的应用")) { Button(L("查看全部")) { store.section = .containers }.buttonStyle(.deskQuiet).font(.caption) }
                        if store.runningContainers.isEmpty {
                            VStack(spacing: 8) { Image(systemName: "shippingbox").font(.title2); Text(L("还没有运行中的容器")).font(.callout); Text(L("从镜像创建容器，或部署 Compose 项目。")).font(.caption).foregroundStyle(.secondary) }.foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 135)
                        } else {
                            ForEach(Array(store.runningContainers.prefix(4))) { container in
                                Divider().padding(.vertical, 4)
                                HStack {
                                    Circle().fill(.green).frame(width: 7, height: 7)
                                    Button(container.Names) { detailContainer = container }.buttonStyle(.plain).font(.callout.weight(.medium))
                                    Spacer()
                                    Text(container.Image).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }.padding(.vertical, 5)
                            }
                        }
                    }
                    Card {
                        Text(L("工作空间信息")).font(.headline).padding(.bottom, 12)
                        infoRow(L("运行时"), store.currentProfile?.runtime ?? "—")
                        infoRow("Docker", store.snapshot?.info.ServerVersion ?? L("未连接"))
                        infoRow(L("存储驱动"), store.snapshot?.info.Driver ?? "—")
                        infoRow(L("镜像 / 存储卷"), "\(store.images.count) / \(store.snapshot?.volumes.count ?? 0)")
                        if store.snapshot?.info.HTTPProxy?.isEmpty == false {
                            Label(L("已配置网络代理"), systemImage: "network.badge.shield.half.filled").font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                        }
                    }.frame(width: 280)
                }
            }.padding(.horizontal, 28).padding(.bottom, 26)
        }.sheet(item: $detailContainer) { ContainerDetailView(container: $0) }
    }
    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).lineLimit(1) }.font(.caption).padding(.vertical, 5)
    }
}
