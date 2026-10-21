import Foundation

public struct CommandResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public var combined: String { [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n") }
}

public enum CommandFailure: LocalizedError, Sendable {
    case missingTool(String)
    case failed(String, Int32, String)
    case timedOut(String)
    case cancelled
    public var errorDescription: String? {
        switch self {
        case .missingTool(let name): return L("未找到 \(name)。请在设置中指定已安装的可执行文件。")
        case .failed(let name, let code, let output): return L("\(name) 未能完成（退出码 \(code)）。\n\(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        case .timedOut(let name): return L("\(name) 等待超时。请刷新状态后重试；已启动的虚拟机可能仍在初始化。")
        case .cancelled: return L("操作已取消。请刷新以查看当前状态。")
        }
    }
}

private final class ProcessControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var reason: CommandFailure?
    func attach(_ process: Process) { lock.lock(); self.process = process; lock.unlock() }
    func detach() { lock.lock(); process = nil; lock.unlock() }
    func stop(_ reason: CommandFailure) {
        lock.lock()
        guard self.reason == nil else { lock.unlock(); return }
        self.reason = reason
        let process = self.process
        lock.unlock()
        if process?.isRunning == true {
            process?.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }
    var failure: CommandFailure? { lock.lock(); defer { lock.unlock() }; return reason }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var truncated = false
    func read(_ handle: FileHandle, output: (@Sendable (String) -> Void)?) {
        while let chunk = try? handle.read(upToCount: 65_536), !chunk.isEmpty {
            lock.lock()
            let remaining = max(0, 8_388_608 - data.count)
            data.append(chunk.prefix(remaining))
            if chunk.count > remaining { truncated = true }
            lock.unlock()
            output?(String(decoding: chunk, as: UTF8.self))
        }
    }
    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self) + (truncated ? L("\n…输出过长，已截断。") : "")
    }
}

public struct CommandRunner: Sendable {
    public init() {}
    public func run(executable: String, arguments: [String], timeout: TimeInterval = 30, environment overrides: [String: String] = [:],
                    output: (@Sendable (String) -> Void)? = nil) async throws -> CommandResult {
        let control = ProcessControl()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        if let error = control.failure { throw error }
                        let process = Process()
                        let stdout = Pipe(), stderr = Pipe()
                        let out = OutputBuffer(), err = OutputBuffer()
                        let group = DispatchGroup()
                        process.executableURL = URL(fileURLWithPath: executable)
                        process.arguments = arguments
                        var environment = ProcessInfo.processInfo.environment
                        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                        environment["LC_ALL"] = "en_US.UTF-8"
                        environment.removeValue(forKey: "DOCKER_HOST")
                        environment.removeValue(forKey: "DOCKER_CONTEXT")
                        environment.merge(overrides) { _, new in new }
                        process.environment = environment
                        process.standardInput = FileHandle.nullDevice
                        process.standardOutput = stdout
                        process.standardError = stderr
                        control.attach(process)
                        defer { control.detach() }
                        try process.run()
                        if control.failure != nil { process.terminate() }
                        group.enter()
                        DispatchQueue.global().async { out.read(stdout.fileHandleForReading, output: output); group.leave() }
                        group.enter()
                        DispatchQueue.global().async { err.read(stderr.fileHandleForReading, output: output); group.leave() }
                        let deadline = DispatchWorkItem { control.stop(.timedOut(URL(fileURLWithPath: executable).lastPathComponent)) }
                        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                        process.waitUntilExit()
                        deadline.cancel()
                        group.wait()
                        if let error = control.failure { throw error }
                        let result = CommandResult(stdout: out.text, stderr: err.text, exitCode: process.terminationStatus)
                        if result.exitCode != 0 {
                            throw CommandFailure.failed(URL(fileURLWithPath: executable).lastPathComponent, result.exitCode, result.combined)
                        }
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: { control.stop(.cancelled) }
    }
}

public enum Tool: String, Sendable { case colima, docker }

public struct Toolchain: Sendable {
    public var colima: String?
    public var docker: String?
    public var proxy: String?
    public init(colima: String? = nil, docker: String? = nil, proxy: String? = nil) {
        self.colima = Self.find("colima", override: colima)
        self.docker = Self.find("docker", override: docker)
        self.proxy = proxy.flatMap { $0.isEmpty ? nil : $0 }
    }
    public static func find(_ name: String, override: String?) -> String? {
        let paths = [override, "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
        return paths.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    public func path(_ tool: Tool) throws -> String {
        guard let result = tool == .colima ? colima : docker else { throw CommandFailure.missingTool(tool.rawValue) }
        return result
    }
}

public struct CommandSpec: Sendable {
    public let tool: Tool
    public let arguments: [String]
    public let timeout: TimeInterval
    public init(_ tool: Tool, _ arguments: [String], timeout: TimeInterval = 120) {
        self.tool = tool; self.arguments = arguments; self.timeout = timeout
    }
}
