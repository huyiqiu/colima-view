import Foundation

public struct ColimaProfile: Decodable, Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let status: String
    public let arch: String
    public let cpus: Int
    public let memory: Int64
    public let disk: Int64
    public let runtime: String
    public var isRunning: Bool { status.lowercased() == "running" }
    public var context: String { name == "default" ? "colima" : "colima-\(name)" }
    public var memoryGiB: Double { Double(memory) / 1_073_741_824 }
    public var diskGiB: Int { Int(disk / 1_073_741_824) }
}

public struct DockerContainer: Decodable, Identifiable, Hashable, Sendable {
    public let ID: String
    public let Names: String
    public let Image: String
    public let State: String
    public let Status: String
    public let Ports: String
    public let Labels: String?
    public var id: String { self.ID }
    public var shortID: String { String(self.ID.prefix(12)) }
    public var isRunning: Bool { State == "running" }
    public var isPaused: Bool { State == "paused" }
    public var project: String? {
        Labels?.split(separator: ",").first { $0.hasPrefix("com.docker.compose.project=") }
            .map { String($0.dropFirst("com.docker.compose.project=".count)) }
    }
    public var webPorts: [Int] {
        guard let regex = try? NSRegularExpression(pattern: #"(?:0\.0\.0\.0|127\.0\.0\.1|\[::\]|:::|\[::1\]):(\d+)->"#) else { return [] }
        let ns = Ports as NSString
        let ports = regex.matches(in: Ports, range: NSRange(location: 0, length: ns.length))
            .compactMap { Int(ns.substring(with: $0.range(at: 1))) }
        return Array(Set(ports)).sorted()
    }
}

public struct DockerImage: Decodable, Identifiable, Hashable, Sendable {
    public let ID: String
    public let Repository: String
    public let Tag: String
    public let Size: String
    public let CreatedSince: String
    public var id: String { "\(self.ID):\(Repository):\(Tag)" }
    public var reference: String { Repository == "<none>" ? self.ID : "\(Repository):\(Tag)" }
}

public struct DockerVolume: Decodable, Identifiable, Hashable, Sendable {
    public let Name: String
    public let Driver: String
    public let Scope: String?
    public var id: String { Name }
}

public struct DockerNetwork: Decodable, Identifiable, Hashable, Sendable {
    public let ID: String
    public let Name: String
    public let Driver: String
    public let Scope: String
    public var id: String { self.ID }
    public var isSystem: Bool { ["bridge", "host", "none"].contains(Name) }
}

public struct ComposeProject: Decodable, Identifiable, Hashable, Sendable {
    public let Name: String
    public let Status: String
    public let ConfigFiles: String
    public var id: String { Name }
    public var files: [String] { ConfigFiles.split(separator: ",").map(String.init) }
}

public struct ContainerStats: Decodable, Identifiable, Sendable {
    public let ID: String
    public let Name: String
    public let CPUPerc: String
    public let MemUsage: String
    public let MemPerc: String
    public var id: String { self.ID }
    public var cpu: Double { Double(CPUPerc.replacingOccurrences(of: "%", with: "")) ?? 0 }
    public var memoryBytes: Double { ByteSize.parse(MemUsage.components(separatedBy: "/").first ?? "") }
}

public struct EngineInfo: Decodable, Sendable {
    public let ServerVersion: String
    public let NCPU: Int
    public let MemTotal: Int64
    public let Driver: String
    public let DockerRootDir: String
    public let OperatingSystem: String
    public let HTTPProxy: String?
    public let HTTPSProxy: String?
    enum CodingKeys: String, CodingKey {
        case ServerVersion, NCPU, MemTotal, Driver, DockerRootDir, OperatingSystem
        case HTTPProxy = "HttpProxy"
        case HTTPSProxy = "HttpsProxy"
    }
}

public struct DiskUsage: Decodable, Identifiable, Sendable {
    public let type: String
    public let TotalCount: String
    public let Active: String
    public let Size: String
    public let Reclaimable: String
    public var id: String { type }
    enum CodingKeys: String, CodingKey { case type = "Type"; case TotalCount, Active, Size, Reclaimable }
}

public struct DockerSnapshot: Sendable {
    public let containers: [DockerContainer]
    public let images: [DockerImage]
    public let volumes: [DockerVolume]
    public let networks: [DockerNetwork]
    public let projects: [ComposeProject]
    public let stats: [ContainerStats]
    public let info: EngineInfo
}

public enum JSONLines {
    public static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> [T] {
        let data = Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        if data.first == 91 { return try decoder.decode([T].self, from: data) }
        return try text.split(whereSeparator: \.isNewline).map {
            try decoder.decode(T.self, from: Data($0.utf8))
        }
    }
    public static func pretty(_ text: String) -> String {
        guard let value = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
              let result = String(data: data, encoding: .utf8) else { return text }
        return result
    }
}

public enum ByteSize {
    public static func parse(_ text: String) -> Double {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard let regex = try? NSRegularExpression(pattern: #"^([\d.]+)\s*([A-Za-z]+)?"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text), let value = Double(text[range]) else { return 0 }
        let unit = Range(match.range(at: 2), in: text).map { String(text[$0]).lowercased() } ?? "b"
        let units: [String: Double] = ["b": 1, "kb": 1e3, "mb": 1e6, "gb": 1e9, "tb": 1e12,
                                       "kib": 1024, "mib": 1_048_576, "gib": 1_073_741_824, "tib": 1_099_511_627_776]
        return value * (units[unit] ?? 1)
    }
    public static func format(_ bytes: Double) -> String {
        if bytes <= 0 { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }
}

public enum InputValidation {
    public static func profileName(_ value: String) -> Bool {
        value.range(of: #"^[a-z][a-z0-9-]{0,31}$"#, options: .regularExpression) != nil
    }
    public static func resourceName(_ value: String) -> Bool {
        value.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9_.-]*$"#, options: .regularExpression) != nil
    }
    public static func imageReference(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("-") && !value.contains(where: \.isWhitespace)
    }
    public static func environment(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z_][A-Za-z0-9_]*="#, options: .regularExpression) != nil
    }
    public static func port(_ value: String) -> Bool {
        let pattern = #"^(?:(?:127\.0\.0\.1|0\.0\.0\.0):)?([0-9]{1,5}):([0-9]{1,5})(?:/(?:tcp|udp))?$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let match = re.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return false }
        return [1,2].allSatisfy { index in
            guard let range = Range(match.range(at: index), in: value), let n = Int(value[range]) else { return false }
            return (1...65535).contains(n)
        }
    }
}
