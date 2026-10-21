import Foundation
import ColimaCore

@main
struct Probe {
    static func main() async {
        do {
            let service = DockerService()
            let profiles = try await service.profiles()
            print("Profiles: \(profiles.map { "\($0.name):\($0.status)" }.joined(separator: ", "))")
            guard let profile = profiles.first(where: { $0.isRunning && $0.runtime == "docker" }) else {
                throw CommandFailure.failed("probe", 1, "No running Docker profile")
            }
            let snapshot = try await service.snapshot(profile)
            print("Engine: \(snapshot.info.ServerVersion); containers: \(snapshot.containers.count); images: \(snapshot.images.count); volumes: \(snapshot.volumes.count); networks: \(snapshot.networks.count); projects: \(snapshot.projects.count)")
            let usage = try await service.diskUsage(profile)
            print("Disk usage categories: \(usage.map(\.type).joined(separator: ", "))")
            let storage = await service.storageUsage(profile, dockerRoot: snapshot.info.DockerRootDir)
            guard let host = storage.hostAllocated, host > 0, let dataDisk = storage.dataDisk,
                  storage.systemDisk != nil, storage.categories?.isEmpty == false, storage.warnings.isEmpty else {
                throw CommandFailure.failed("storage", 1, storage.warnings.joined(separator: "\n"))
            }
            print("Storage: Mac \(ByteSize.binary(host)); data disk \(ByteSize.binary(dataDisk.used)) used, \(ByteSize.binary(dataDisk.available)) available; \(storage.categories?.count ?? 0) Docker categories")
            if CommandLine.arguments.contains("--smoke-test") {
                let name = "colima-desk-test-" + UUID().uuidString.prefix(8).lowercased()
                let args = ["--context", profile.context]
                _ = try await service.execute(CommandSpec(.docker, args + ["create", "--name", name, "hello-world"]))
                do {
                    let after = try await service.snapshot(profile)
                    guard let container = after.containers.first(where: { $0.Names == name }) else {
                        throw CommandFailure.failed("probe", 1, "Created container missing from snapshot")
                    }
                    _ = try await service.execute(CommandSpec(.docker, args + ["start", "--attach", container.ID]))
                    let logs = try await service.logs(profile, container: container.ID)
                    guard logs.contains("Hello from Docker!") else { throw CommandFailure.failed("probe", 1, "Expected log output missing") }
                    let inspect = try await service.inspect(profile, kind: "container", id: container.ID)
                    guard inspect.contains(name) else { throw CommandFailure.failed("probe", 1, "Inspect data missing") }
                    _ = try await service.execute(CommandSpec(.docker, args + ["rm", container.ID]))
                    print("PASS: create → snapshot → start → logs → inspect → remove")
                } catch {
                    _ = try? await service.execute(CommandSpec(.docker, args + ["rm", "--force", name]))
                    throw error
                }
                try await checkResources(service, profile: profile)
            }
            print("PASS: real Colima/Docker compatibility check")
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func checkResources(_ service: DockerService, profile: ColimaProfile) async throws {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let name = "colima-desk-check-\(suffix)"
        let image = "colima-desk-check:\(suffix)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let compose = directory.appendingPathComponent("compose.yaml")
        try "FROM scratch\nLABEL app=colima-desk-smoke-test\n".write(to: directory.appendingPathComponent("Dockerfile"), atomically: true, encoding: .utf8)
        try "services:\n  smoke:\n    image: hello-world:latest\n    restart: \"no\"\n".write(to: compose, atomically: true, encoding: .utf8)
        let prefix = ["--context", profile.context]
        let composePrefix = ["compose", "--project-name", name, "--file", compose.path]
        func run(_ args: [String]) async throws -> CommandResult {
            try await service.execute(CommandSpec(.docker, prefix + args, timeout: 120))
        }
        func cleanup() async {
            _ = try? await run(composePrefix + ["down"])
            _ = try? await run(["network", "rm", name])
            _ = try? await run(["volume", "rm", name])
            _ = try? await run(["image", "rm", image])
            try? FileManager.default.removeItem(at: directory)
        }
        do {
            _ = try await run(["volume", "create", "--", name])
            _ = try await run(["network", "create", "--driver", "bridge", "--", name])
            let before = try await service.snapshot(profile)
            guard before.volumes.contains(where: { $0.Name == name }), before.networks.contains(where: { $0.Name == name }) else {
                throw CommandFailure.failed("probe", 1, "Volume/network missing from snapshot")
            }
            _ = try await service.inspect(profile, kind: "volume", id: name)
            _ = try await service.inspect(profile, kind: "network", id: name)
            _ = try await run(["build", "--tag", image, "--file", directory.appendingPathComponent("Dockerfile").path, "--progress", "plain", "--", directory.path])
            _ = try await service.inspect(profile, kind: "image", id: image)
            _ = try await run(composePrefix + ["up", "--detach", "--pull", "never"])
            let after = try await service.snapshot(profile)
            guard after.projects.contains(where: { $0.Name == name }) else { throw CommandFailure.failed("probe", 1, "Compose project missing from snapshot") }
            _ = try await run(composePrefix + ["wait", "smoke"])
            let logs = try await run(composePrefix + ["logs", "--no-color", "--tail", "100"])
            guard logs.combined.contains("Hello from Docker!") else { throw CommandFailure.failed("probe", 1, "Compose logs missing: \(logs.combined)") }
            await cleanup()
            print("PASS: image build/inspect/remove, volume and network CRUD, Compose deploy/logs/down")
        } catch {
            await cleanup()
            throw error
        }
    }
}
