import SwiftUI
import ColimaCore

struct StorageView: View {
    @EnvironmentObject var store: AppStore
    private var usage: StorageUsage? { store.storageUsage }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    if store.isLoadingDisk { ProgressView().controlSize(.small); Text(L("正在统计存储占用…")) }
                    else if let date = usage?.collectedAt { Text(L("更新于 \(date.formatted(date: .omitted, time: .standard)) · 每分钟自动更新")) }
                    else { Text(L("统计当前 Colima 的存储使用情况")) }
                    Spacer()
                    Button(L("刷新用量"), systemImage: "arrow.clockwise") { store.loadStorage(force: true) }
                        .disabled(store.isLoadingDisk || store.isBusy || store.currentProfile == nil)
                }.font(.caption).foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 16) {
                    hostCard
                    dataCard
                }

                if let warnings = usage?.warnings, !warnings.isEmpty {
                    Card {
                        Label(L("部分统计暂不可用"), systemImage: "exclamationmark.triangle").font(.headline).foregroundStyle(.orange)
                        ForEach(warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L("Docker 分类统计")).font(.headline)
                        if let categories = usage?.categories, !categories.isEmpty {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                                ForEach(categories) { item in category(item) }
                            }
                            Label(L("镜像与构建缓存可能共享数据，分类大小不能直接相加作为实际占用。"), systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(store.currentProfile?.isRunning == true ? (store.isLoadingDisk ? L("正在读取镜像、容器、存储卷与构建缓存…") : L("暂时无法读取分类统计，请刷新重试。")) : L("启动 Docker 实例后可查看镜像、容器、存储卷与构建缓存。"))
                                .font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
                        }
                    }
                }
            }.padding(.horizontal, 28).padding(.bottom, 26)
        }.onAppear { store.loadStorage() }
    }

    private var hostCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Label(L("Mac 实际占用"), systemImage: "laptopcomputer").font(.headline); Spacer(); Text(L("全部实例")).font(.caption).foregroundStyle(.secondary) }
                Text(usage?.hostAllocated.map(ByteSize.binary) ?? "—")
                    .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(L("包含所有 Colima 实例的系统盘、数据盘和缓存。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(usage?.homePath ?? L("正在定位存储目录…")).font(.caption.monospaced()).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }.frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        }
    }

    private var dataCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Label(L("虚拟机数据盘"), systemImage: "internaldrive").font(.headline); Spacer(); Text(store.selectedProfileName).font(.caption).foregroundStyle(.secondary) }
                if let disk = usage?.dataDisk {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(ByteSize.binary(disk.used)).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(L("已用")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(disk.usedPercent))%").font(.callout.weight(.medium)).foregroundStyle(disk.usedPercent >= 85 ? .orange : Palette.accent)
                    }
                    ProgressView(value: min(disk.usedPercent, 100), total: 100).tint(disk.usedPercent >= 85 ? .orange : Palette.accent)
                    Text(L("可用 \(ByteSize.binary(disk.available)) · 文件系统容量 \(ByteSize.binary(disk.capacity))"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let root = usage?.systemDisk {
                        Text(L("另有系统盘已用 \(ByteSize.binary(root.used))")).font(.caption).foregroundStyle(.tertiary)
                    }
                } else {
                    Text("—").font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text(store.currentProfile?.isRunning == true ? L("等待磁盘统计，点击刷新用量可重新读取。") : L("实例已停止，启动后可读取已用与可用空间。"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let profile = store.currentProfile { Text(L("配置容量 \(profile.diskGiB) GiB，不代表实际占用。 ")).font(.caption).foregroundStyle(.tertiary) }
                }
            }.frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        }
    }

    private func category(_ item: DiskUsage) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(categoryTitle(item.type), systemImage: categoryIcon(item.type)).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            Text(item.Size).font(.title2.weight(.semibold)).monospacedDigit()
            HStack {
                Text(L("共 \(item.TotalCount) 项 · 活跃 \(item.Active) 项"))
                Spacer()
                Text(L("可回收 \(item.Reclaimable)"))
            }.font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
    private func categoryTitle(_ type: String) -> String {
        switch type { case "Images": return L("镜像"); case "Containers": return L("容器"); case "Local Volumes": return L("存储卷"); case "Build Cache": return L("构建缓存"); default: return type }
    }
    private func categoryIcon(_ type: String) -> String {
        switch type { case "Images": return "square.stack.3d.up"; case "Containers": return "shippingbox"; case "Local Volumes": return "externaldrive"; default: return "hammer" }
    }
}
