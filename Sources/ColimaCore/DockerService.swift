import Foundation

public struct DockerService: Sendable {
    public let tools: Toolchain
    public let runner = CommandRunner()
    public init(tools: Toolchain = Toolchain()) { self.tools = tools }

    public func execute(_ spec: CommandSpec, output: (@Sendable (String) -> Void)? = nil) async throws -> CommandResult {
        var environment: [String: String] = [:]
        if spec.tool == .colima, let proxy = tools.proxy {
            environment = ["HTTP_PROXY": proxy, "HTTPS_PROXY": proxy, "NO_PROXY": "localhost,127.0.0.1,::1"]
        }
        return try await runner.run(executable: tools.path(spec.tool), arguments: spec.arguments, timeout: spec.timeout, environment: environment, output: output)
    }
    public func docker(_ profile: ColimaProfile, _ args: [String], timeout: TimeInterval = 30) async throws -> String {
        try await execute(CommandSpec(.docker, ["--context", profile.context] + args, timeout: timeout)).stdout
    }
    public func profiles() async throws -> [ColimaProfile] {
        let text = try await execute(CommandSpec(.colima, ["list", "--json"], timeout: 20)).stdout
        return try JSONLines.decode(ColimaProfile.self, from: text).sorted { $0.name < $1.name }
    }
    public func snapshot(_ profile: ColimaProfile) async throws -> DockerSnapshot {
        async let containersText = docker(profile, ["ps", "--all", "--no-trunc", "--format", "{{json .}}"])
        async let imagesText = docker(profile, ["image", "ls", "--format", "{{json .}}"])
        async let volumesText = docker(profile, ["volume", "ls", "--format", "{{json .}}"])
        async let networksText = docker(profile, ["network", "ls", "--format", "{{json .}}"])
        async let projectsText = docker(profile, ["compose", "ls", "--all", "--format", "json"])
        async let infoText = docker(profile, ["info", "--format", "{{json .}}"])
        let containers = try JSONLines.decode(DockerContainer.self, from: await containersText)
        let stats: [ContainerStats]
        if containers.contains(where: \.isRunning) {
            stats = try await JSONLines.decode(ContainerStats.self, from: docker(profile, ["stats", "--no-stream", "--format", "{{json .}}"], timeout: 15))
        } else { stats = [] }
        return try await DockerSnapshot(
            containers: containers,
            images: JSONLines.decode(DockerImage.self, from: imagesText),
            volumes: JSONLines.decode(DockerVolume.self, from: volumesText),
            networks: JSONLines.decode(DockerNetwork.self, from: networksText),
            projects: JSONLines.decode(ComposeProject.self, from: projectsText),
            stats: stats,
            info: JSONDecoder().decode(EngineInfo.self, from: Data(infoText.utf8))
        )
    }
    public func logs(_ profile: ColimaProfile, container: String) async throws -> String {
        try await execute(CommandSpec(.docker, ["--context", profile.context, "logs", "--timestamps", "--tail", "500", container], timeout: 15)).combined
    }
    public func inspect(_ profile: ColimaProfile, kind: String, id: String) async throws -> String {
        JSONLines.pretty(try await docker(profile, [kind, "inspect", id]))
    }
    public func diskUsage(_ profile: ColimaProfile) async throws -> [DiskUsage] {
        try await JSONLines.decode(DiskUsage.self, from: docker(profile, ["system", "df", "--format", "{{json .}}"], timeout: 60))
    }
    public static func composeArguments(_ project: ComposeProject, action: [String]) -> [String] {
        ["compose", "--project-name", project.Name] + project.files.flatMap { ["--file", $0] } + action
    }
}
