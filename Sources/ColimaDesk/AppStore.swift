import SwiftUI
import ColimaCore

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview", profiles = "Instances", containers = "Containers", images = "Images", compose = "Compose", storage = "Storage", volumes = "Volumes", networks = "Networks", activity = "Activity"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return L("概览")
        case .profiles: return L("实例")
        case .containers: return L("容器")
        case .images: return L("镜像")
        case .compose: return "Compose"
        case .storage: return L("存储占用")
        case .volumes: return L("存储卷")
        case .networks: return L("网络")
        case .activity: return L("活动记录")
        }
    }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .profiles: return "desktopcomputer"
        case .containers: return "shippingbox"
        case .images: return "square.3.layers.3d"
        case .compose: return "square.stack.3d.up"
        case .storage: return "chart.pie"
        case .volumes: return "externaldrive"
        case .networks: return "network"
        case .activity: return "clock.arrow.circlepath"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return L("你的本地容器工作空间")
        case .profiles: return L("管理虚拟机及其资源分配")
        case .containers: return L("运行应用、查看状态与日志")
        case .images: return L("拉取和管理本地镜像")
        case .compose: return L("将多个服务作为一个项目管理")
        case .storage: return L("查看 Mac 实际占用、虚拟机磁盘与 Docker 分类统计")
        case .volumes: return L("管理容器的持久化数据")
        case .networks: return L("连接和隔离你的容器")
        case .activity: return L("查看操作结果与诊断信息")
        }
    }
}

struct ResourceSample: Identifiable {
    let id = UUID()
    let date: Date
    let cpu: Double
    let memory: Double
}

struct ActivityEntry: Identifiable {
    let id: UUID
    let date: Date
    let title: String
    var output: String
    var succeeded: Bool?
}

struct AppNotice: Identifiable { let id = UUID(); let title: String; let message: String }
struct Confirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let button: String
    let action: () -> Void
}

@MainActor
final class AppStore: ObservableObject {
    @Published var section: AppSection = .overview
    @Published var search = ""
    @Published var profiles: [ColimaProfile] = []
    @Published var selectedProfileName = UserDefaults.standard.string(forKey: "selectedProfile") ?? "default"
    @Published var snapshot: DockerSnapshot?
    @Published var history: [ResourceSample] = []
    @Published var activity: [ActivityEntry] = []
    @Published var isRefreshing = false
    @Published var isBusy = false
    @Published var activeOperation: String?
    @Published var connectionError: String?
    @Published var lastRefresh: Date?
    @Published var notice: AppNotice?
    @Published var confirmation: Confirmation?
    @Published var showProgress = false
    @Published var storageUsage: StorageUsage?
    @Published var isLoadingDisk = false
    private var refreshTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private var storageTask: Task<Void, Never>?
    private var storageID = UUID()
    private var refreshID = UUID()

    var service: DockerService {
        DockerService(tools: Toolchain(colima: UserDefaults.standard.string(forKey: "colimaPath"),
                                      docker: UserDefaults.standard.string(forKey: "dockerPath"),
                                      proxy: UserDefaults.standard.string(forKey: "downloadProxy")))
    }
    var currentProfile: ColimaProfile? { profiles.first { $0.name == selectedProfileName } }
    var containers: [DockerContainer] { snapshot?.containers ?? [] }
    var images: [DockerImage] { snapshot?.images ?? [] }
    var runningContainers: [DockerContainer] { containers.filter(\.isRunning) }
    var stats: [ContainerStats] { snapshot?.stats ?? [] }
    var cpu: Double { stats.reduce(0) { $0 + $1.cpu } }
    var memory: Double { stats.reduce(0) { $0 + $1.memoryBytes } }
    var dockerAvailable: Bool { currentProfile?.isRunning == true && snapshot != nil }
    var activeLog: String { activity.first?.output ?? "" }

    func startPolling() {
        guard pollingTask == nil else { return }
        refresh()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = max(5, UserDefaults.standard.integer(forKey: "refreshInterval"))
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                if !self.isBusy && !self.isRefreshing { self.refresh(forceStorage: false) }
            }
        }
    }

    func selectProfile(_ name: String) {
        guard name != selectedProfileName else { return }
        selectedProfileName = name
        UserDefaults.standard.set(name, forKey: "selectedProfile")
        snapshot = nil; history = []; resetStorage()
        refresh()
    }

    func refresh(forceStorage: Bool = true) {
        refreshTask?.cancel()
        let token = UUID()
        refreshID = token
        refreshTask = Task {
            isRefreshing = true
            defer { if refreshID == token { isRefreshing = false } }
            do {
                let result = try await service.profiles()
                try Task.checkCancellation()
                guard refreshID == token else { return }
                profiles = result
                if !result.contains(where: { $0.name == selectedProfileName }) {
                    snapshot = nil; history = []; resetStorage()
                    if let first = result.first {
                        selectedProfileName = first.name
                        UserDefaults.standard.set(first.name, forKey: "selectedProfile")
                    }
                }
                if let profile = currentProfile, profile.isRunning, profile.runtime == "docker" {
                    let data = try await service.snapshot(profile)
                    try Task.checkCancellation()
                    guard refreshID == token else { return }
                    snapshot = data
                    history.append(ResourceSample(date: Date(), cpu: cpu, memory: memory / 1_048_576))
                    if history.count > 90 { history.removeFirst(history.count - 90) }
                } else { snapshot = nil }
                loadStorage(force: forceStorage)
                lastRefresh = Date()
                connectionError = nil
            } catch {
                if !Task.isCancelled && refreshID == token {
                    connectionError = error.localizedDescription
                    loadStorage(force: forceStorage)
                }
            }
        }
    }

    func execute(_ title: String, specs: [CommandSpec], selectAfter: String? = nil) {
        guard !isBusy else { return }
        refreshTask?.cancel()
        storageTask?.cancel(); storageID = UUID(); isLoadingDisk = false
        isBusy = true; activeOperation = title
        let entryID = UUID()
        activity.insert(ActivityEntry(id: entryID, date: Date(), title: title, output: "", succeeded: nil), at: 0)
        if activity.count > 60 { activity.removeLast() }
        let service = service
        operationTask = Task {
            var success = false
            do {
                for spec in specs {
                    try Task.checkCancellation()
                    appendOutput("› \(spec.tool.rawValue) \(spec.arguments.joined(separator: " "))\n", id: entryID)
                    _ = try await service.execute(spec) { [weak self] chunk in
                        Task { @MainActor in self?.appendOutput(chunk, id: entryID) }
                    }
                }
                success = true
                appendOutput(L("\n操作完成。\n"), id: entryID)
                if let name = selectAfter {
                    selectedProfileName = name
                    UserDefaults.standard.set(name, forKey: "selectedProfile")
                    snapshot = nil; history = []; resetStorage()
                }
            } catch {
                appendOutput("\n\(error.localizedDescription)\n", id: entryID)
                notice = AppNotice(title: L("\(title)未完成"), message: error.localizedDescription)
            }
            if let index = activity.firstIndex(where: { $0.id == entryID }) { activity[index].succeeded = success }
            isBusy = false; activeOperation = nil; operationTask = nil
            refresh()
        }
    }

    private func appendOutput(_ output: String, id: UUID) {
        guard let index = activity.firstIndex(where: { $0.id == id }) else { return }
        activity[index].output += output
        if activity[index].output.count > 250_000 { activity[index].output = String(activity[index].output.suffix(250_000)) }
    }

    func colimaAction(_ action: String, profile: ColimaProfile) {
        let title = ["start": L("启动"), "stop": L("停止"), "restart": L("重启")][action] ?? action
        if action == "restart" {
            execute(L("重启 \(profile.name)"), specs: [CommandSpec(.colima, ["stop", "--profile", profile.name]),
                CommandSpec(.colima, ["start", "--profile", profile.name, "--activate=false"], timeout: 1800)])
        } else {
            let args = [action, "--profile", profile.name] + (action == "start" ? ["--activate=false"] : [])
            execute("\(title) \(profile.name)", specs: [CommandSpec(.colima, args, timeout: 1800)])
        }
    }

    func dockerAction(_ title: String, args: [String], timeout: TimeInterval = 120) {
        guard let profile = currentProfile else { return }
        execute(title, specs: [CommandSpec(.docker, ["--context", profile.context] + args, timeout: timeout)])
    }

    func containerAction(_ action: String, _ container: DockerContainer) {
        let title = ["start": L("启动"), "stop": L("停止"), "restart": L("重启"), "pause": L("暂停"), "unpause": L("恢复")][action] ?? action
        dockerAction("\(title) \(container.Names)", args: ["container", action, container.ID])
    }

    func deleteContainer(_ container: DockerContainer) {
        confirmation = Confirmation(title: L("删除容器 \(container.Names)？"), message: L("容器会被停止并删除，容器可写层内的数据将丢失。关联的存储卷和镜像会保留。"), button: L("删除容器")) { [weak self] in
            self?.dockerAction(L("删除 \(container.Names)"), args: ["container", "rm", "--force", container.ID])
        }
    }

    private func resetStorage() {
        storageTask?.cancel(); storageID = UUID()
        storageUsage = nil; isLoadingDisk = false
    }

    func loadStorage(force: Bool = false) {
        guard let profile = currentProfile, !isBusy else { return }
        if !force {
            guard !isLoadingDisk else { return }
            if let value = storageUsage, value.profileName == profile.name,
               value.profileIsRunning == profile.isRunning, Date().timeIntervalSince(value.collectedAt) < 60 { return }
        }
        storageTask?.cancel()
        let token = UUID()
        storageID = token
        isLoadingDisk = true
        let service = service
        let dockerRoot = snapshot?.info.DockerRootDir ?? "/var/lib/docker"
        storageTask = Task {
            defer { if storageID == token { isLoadingDisk = false } }
            let value = await service.storageUsage(profile, dockerRoot: dockerRoot)
            guard !Task.isCancelled, storageID == token, currentProfile?.name == profile.name,
                  currentProfile?.isRunning == profile.isRunning else { return }
            storageUsage = value
        }
    }

    func matches(_ values: String...) -> Bool {
        search.isEmpty || values.contains { $0.localizedCaseInsensitiveContains(search) }
    }
}
