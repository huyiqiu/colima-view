import Foundation

/// Docker inspect contains optional and driver-specific fields. Keep unknown data
/// while providing safe projections for the resource detail screens.
public enum InspectionValue: Decodable, Equatable, Sendable {
    case object([String: InspectionValue]), array([InspectionValue])
    case string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([String: InspectionValue].self) { self = .object(value) }
        else { self = .array(try container.decode([InspectionValue].self)) }
    }

    public subscript(_ key: String) -> InspectionValue {
        guard case .object(let object) = self else { return .null }
        return object[key] ?? .null
    }
    public var string: String? { if case .string(let value) = self { return value }; return nil }
    public var number: Double? { if case .number(let value) = self { return value }; return nil }
    public var bool: Bool? { if case .bool(let value) = self { return value }; return nil }
    public var array: [InspectionValue] { if case .array(let value) = self { return value }; return [] }
    public var entries: [InspectionEntry] {
        guard case .object(let value) = self else { return [] }
        return value.keys.sorted().map { InspectionEntry(key: $0, value: value[$0]!) }
    }
    public var strings: [String] { array.compactMap(\.string) }
    public var scalar: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.rounded() == value ? String(format: "%.0f", value) : String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }
}

public struct InspectionEntry: Identifiable, Equatable, Sendable {
    public let key: String
    public let value: InspectionValue
    public var id: String { key }
}

public struct InspectionEnvironment: Identifiable, Equatable, Sendable {
    public let id: Int
    public let key: String
    public let value: String
}

public struct InspectionPort: Identifiable, Equatable, Sendable {
    public let id: String
    public let containerPort: String
    public let hostIP: String
    public let hostPort: String?
    public var browserURL: URL? {
        guard containerPort.hasSuffix("/tcp"), let hostPort,
              let port = Int(hostPort), (1...65535).contains(port) else { return nil }
        let host = ["", "0.0.0.0", "::"].contains(hostIP) ? "127.0.0.1" : hostIP
        let addressCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF:.")
        guard !host.isEmpty, host.unicodeScalars.allSatisfy(addressCharacters.contains) else { return nil }
        let address = host.contains(":") ? "[\(host)]" : host
        return URL(string: "http://\(address):\(port)")
    }
}

public struct DockerInspection: Sendable {
    public let root: InspectionValue

    public init(json: String) throws {
        let decoded = try JSONDecoder().decode(InspectionValue.self, from: Data(json.utf8))
        let value: InspectionValue
        if case .array(let items) = decoded {
            guard items.count == 1, let first = items.first else { throw InspectionError.invalidResource }
            value = first
        } else { value = decoded }
        guard case .object = value else { throw InspectionError.invalidResource }
        root = value
    }

    public func value(_ path: String...) -> InspectionValue { path.reduce(root) { $0[$1] } }
    public func string(_ path: String...) -> String? { path.reduce(root) { $0[$1] }.scalar }
    public var environment: [InspectionEnvironment] {
        value("Config", "Env").strings.enumerated().map { index, entry in
            let pair = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return InspectionEnvironment(id: index, key: String(pair[0]), value: pair.count == 2 ? String(pair[1]) : "")
        }
    }
    public var ports: [InspectionPort] {
        value("NetworkSettings", "Ports").entries.flatMap { entry in
            if entry.value.array.isEmpty {
                return [InspectionPort(id: entry.key, containerPort: entry.key, hostIP: "", hostPort: nil)]
            }
            return entry.value.array.enumerated().map { index, binding in
                InspectionPort(id: "\(entry.key)-\(index)", containerPort: entry.key,
                               hostIP: binding["HostIp"].string ?? "", hostPort: binding["HostPort"].string)
            }
        }
    }
}

public enum InspectionError: LocalizedError {
    case invalidResource
    public var errorDescription: String? { L("无法读取有效的资源详情。") }
}
