import Foundation

public struct FileSystemUsage: Sendable {
    public let mount: String
    public let capacity: Double
    public let used: Double
    public let available: Double
    public let usedPercent: Double
}

public struct StorageUsage: Sendable {
    public let profileName: String
    public let profileIsRunning: Bool
    public let homePath: String
    public let hostAllocated: Double?
    public let systemDisk: FileSystemUsage?
    public let dataDisk: FileSystemUsage?
    public let categories: [DiskUsage]?
    public let warnings: [String]
    public let collectedAt: Date
}

public enum StorageParsing {
    public static func allocatedBytes(_ output: String) throws -> Double {
        guard let token = output.split(whereSeparator: \.isWhitespace).first,
              let blocks = UInt64(token) else { throw invalid(L("Mac 磁盘占用")) }
        return Double(blocks) * 1024
    }

    public static func fileSystems(_ output: String) throws -> [FileSystemUsage] {
        let rows = output.split(whereSeparator: \.isNewline).dropFirst()
        let result = try rows.map { row -> FileSystemUsage in
            let fields = row.split(maxSplits: 5, whereSeparator: \.isWhitespace)
            guard fields.count == 6,
                  let capacity = UInt64(fields[1]), capacity > 0,
                  let used = UInt64(fields[2]),
                  let available = Int64(fields[3]), fields[4].hasSuffix("%"),
                  let percent = Double(fields[4].dropLast()), percent.isFinite, percent >= 0 else {
                throw invalid(L("虚拟机磁盘占用"))
            }
            return FileSystemUsage(mount: String(fields[5]), capacity: Double(capacity) * 1024,
                                   used: Double(used) * 1024, available: Double(max(0, available)) * 1024,
                                   usedPercent: percent)
        }
        guard !result.isEmpty else { throw invalid(L("虚拟机磁盘占用")) }
        return result
    }

    private static func invalid(_ name: String) -> CommandFailure {
        .failed(name, 1, L("统计输出格式无法识别，请刷新重试。"))
    }
}

private struct StorageRead<Value: Sendable>: Sendable {
    let value: Value?
    let error: String?
}

private func readStorage<Value: Sendable>(_ action: @Sendable () async throws -> Value) async -> StorageRead<Value> {
    do { let value = try await action(); return StorageRead(value: value, error: nil) }
    catch { return StorageRead(value: nil, error: error.localizedDescription) }
}

extension DockerService {
    public func storageUsage(_ profile: ColimaProfile, dockerRoot: String = "/var/lib/docker") async -> StorageUsage {
        let configuredHome = ProcessInfo.processInfo.environment["COLIMA_HOME"]
        let home = configuredHome.flatMap { $0.isEmpty ? nil : ($0 as NSString).expandingTildeInPath }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".colima").path
        let homePath = URL(fileURLWithPath: home, isDirectory: true).path
        async let host = readStorage {
            let output = try await runner.run(executable: "/usr/bin/du", arguments: ["-sk", homePath], timeout: 45).stdout
            return try StorageParsing.allocatedBytes(output)
        }
        async let disks: StorageRead<[FileSystemUsage]> = readStorage {
            guard profile.isRunning else { return [] }
            let output = try await execute(CommandSpec(.colima, ["ssh", "--profile", profile.name, "--", "df", "-Pk", "/", dockerRoot], timeout: 30)).stdout
            let values = try StorageParsing.fileSystems(output)
            guard values.count == 2 else { throw CommandFailure.failed(L("虚拟机磁盘占用"), 1, L("未返回完整的系统盘和数据盘统计。")) }
            return values
        }
        async let dockerUsage: StorageRead<[DiskUsage]> = readStorage {
            guard profile.isRunning && profile.runtime == "docker" else { return [] }
            return try await diskUsage(profile)
        }
        let (hostResult, diskResult, dockerResult) = await (host, disks, dockerUsage)
        let warnings = [(L("Mac 实际占用"), hostResult.error), (L("虚拟机磁盘"), diskResult.error), (L("Docker 分类统计"), dockerResult.error)]
            .compactMap { name, error in error.map { "\(name)：\($0)" } }
        return StorageUsage(profileName: profile.name, profileIsRunning: profile.isRunning,
                            homePath: homePath, hostAllocated: hostResult.value,
                            systemDisk: diskResult.value?.first, dataDisk: diskResult.value?.dropFirst().first,
                            categories: profile.isRunning && profile.runtime == "docker" ? dockerResult.value : nil,
                            warnings: warnings, collectedAt: Date())
    }
}

extension ByteSize {
    public static func binary(_ bytes: Double) -> String {
        guard bytes > 0 else { return "0 B" }
        let units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
        var value = bytes
        var index = 0
        while value >= 1024 && index < units.count - 1 { value /= 1024; index += 1 }
        return (index == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)) + " " + units[index]
    }
}
