import SwiftUI
import ColimaCore

struct ContainerDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let container: DockerContainer
    @State private var tab = 0
    private var live: DockerContainer { store.containers.first { $0.ID == container.ID } ?? container }
    private var stats: ContainerStats? { store.stats.first { container.ID.hasPrefix($0.ID) || $0.ID.hasPrefix(container.ID) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "shippingbox").font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Palette.accent).frame(width: 50, height: 50)
                    .background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 10) {
                        Text(live.Names).font(.title3.weight(.semibold)).lineLimit(1).textSelection(.enabled)
                        StatusBadge(text: live.isPaused ? L("已暂停") : live.isRunning ? L("运行中") : L("已停止"), color: live.isPaused ? .orange : live.isRunning ? .green : .secondary)
                    }
                    Text(live.Image).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    if let stats {
                        HStack(spacing: 14) {
                            Label(stats.CPUPerc + " CPU", systemImage: "cpu")
                            Label(ByteSize.format(stats.memoryBytes), systemImage: "memorychip")
                        }.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                Button {
                    store.containerAction(live.isPaused ? "unpause" : live.isRunning ? "stop" : "start", live)
                } label: {
                    Label(live.isPaused ? L("恢复") : live.isRunning ? L("停止") : L("启动"), systemImage: live.isRunning ? "stop.fill" : "play.fill")
                }.disabled(store.isBusy || !store.dockerAvailable)
                SmallIconButton(title: L("重启容器"), icon: "arrow.clockwise") { store.containerAction("restart", live) }
                    .disabled(store.isBusy || !store.dockerAvailable)
                Divider().frame(height: 26).padding(.horizontal, 4)
                SmallIconButton(title: L("关闭"), icon: "xmark") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            HStack {
                Picker(L("详情"), selection: $tab) {
                    Text(L("概览")).tag(0)
                    Text(L("日志")).tag(1)
                    Text(L("配置")).tag(2)
                    Text(L("原始 JSON")).tag(3)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 380)
                Spacer()
                Text(live.shortID).font(.caption.monospaced()).foregroundStyle(.tertiary)
            }.padding(.horizontal, 24).padding(.bottom, 18)
            Divider()
            if tab == 1 { ContainerLogsView(container: container) }
            else { InspectionContent(kind: "container", identifier: container.ID, tab: tab == 2 ? 1 : tab == 3 ? 2 : 0) }
        }.frame(width: 940, height: 720).modernControls()
            .onChange(of: store.selectedProfileName) { _, _ in dismiss() }
    }
}

private struct ContainerLogsView: View {
    @EnvironmentObject var store: AppStore
    let container: DockerContainer
    @State private var follow = true
    @State private var text = ""
    @State private var error: String?
    @State private var filter = ""
    @State private var revision = 0
    @State private var loading = false
    private var displayed: String {
        filter.isEmpty ? text : text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .filter { $0.localizedCaseInsensitiveContains(filter) }.joined(separator: "\n")
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                DeskSearchField(title: L("过滤日志…"), text: $filter).frame(width: 240)
                Spacer()
                Toggle(L("自动刷新"), isOn: $follow).toggleStyle(.switch).controlSize(.small)
                Divider().frame(height: 22)
                SmallIconButton(title: L("刷新日志"), icon: "arrow.clockwise") { revision += 1 }.disabled(loading)
                CopyButton(text: displayed).disabled(displayed.isEmpty)
                SmallIconButton(title: L("导出日志"), icon: "square.and.arrow.up") { export() }.disabled(displayed.isEmpty)
            }.padding(.horizontal, 24).padding(.vertical, 14)
            if let error {
                HStack {
                    Label(error, systemImage: "exclamationmark.circle").lineLimit(2)
                    Spacer()
                    Button(L("重试")) { revision += 1 }
                }.font(.caption).foregroundStyle(.orange).padding(12).background(Color.orange.opacity(0.07))
            }
            Divider()
            if loading && text.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayed.isEmpty {
                EmptyState(title: filter.isEmpty ? L("暂无日志") : L("没有匹配的日志"), description: filter.isEmpty ? L("应用产生输出后会显示在这里。") : L("尝试调整搜索内容。"), icon: "text.alignleft")
            } else {
                ScrollViewReader { reader in
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(displayed).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Color.clear.frame(height: 1).id("end")
                        }.padding(20)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: text) { _, _ in if follow { reader.scrollTo("end", anchor: .bottom) } }
                }
            }
            Divider()
            HStack(spacing: 8) {
                Circle().fill(follow ? Color.green : .secondary).frame(width: 6, height: 6)
                Text(follow ? L("每 3 秒刷新 · 自动跟随最新输出") : L("实时刷新已暂停"))
                Spacer()
                Text(L("最近 500 行"))
            }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 10)
        }
        .background(Palette.canvas)
        .task(id: "\(store.selectedProfileName)-\(follow)-\(revision)") {
            guard let profile = store.currentProfile else { return }
            loading = true
            repeat {
                guard !Task.isCancelled else { return }
                do {
                    let output = try await store.service.logs(profile, container: container.ID)
                    guard !Task.isCancelled else { return }
                    text = output; error = nil; loading = false
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = error.localizedDescription; loading = false
                }
                if !follow { return }
                try? await Task.sleep(for: .seconds(3))
            } while !Task.isCancelled
        }
    }
    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(container.Names).log"
        if panel.runModal() == .OK, let url = panel.url {
            do { try displayed.write(to: url, atomically: true, encoding: .utf8) }
            catch { self.error = error.localizedDescription }
        }
    }
}
