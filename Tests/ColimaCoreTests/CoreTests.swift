import XCTest
@testable import ColimaCore

final class CoreTests: XCTestCase {
    func testProfilesJSONLinesAndByteUnits() throws {
        let text = """
        {"name":"default","status":"Running","arch":"aarch64","cpus":2,"memory":2147483648,"disk":21474836480,"runtime":"docker"}
        {"name":"work","status":"Stopped","arch":"aarch64","cpus":4,"memory":4294967296,"disk":32212254720,"runtime":"docker"}
        """
        let profiles = try JSONLines.decode(ColimaProfile.self, from: text)
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles[0].context, "colima")
        XCTAssertEqual(profiles[1].context, "colima-work")
        XCTAssertEqual(profiles[0].memoryGiB, 2)
        XCTAssertEqual(profiles[1].diskGiB, 30)
        XCTAssertEqual(ByteSize.parse("128.5MiB / 2GiB"), 128.5 * 1_048_576)
        XCTAssertEqual(ByteSize.parse("1.25GB"), 1_250_000_000)
    }
    func testEmptyArrayAndInvalidData() throws {
        XCTAssertEqual(try JSONLines.decode(ComposeProject.self, from: "[]").count, 0)
        XCTAssertEqual(try JSONLines.decode(ComposeProject.self, from: " \n ").count, 0)
        XCTAssertThrowsError(try JSONLines.decode(ColimaProfile.self, from: "not JSON"))
    }
    func testPortsAndComposeFiles() throws {
        let data = #"{"ID":"123456789012abc","Names":"web","Image":"nginx","State":"running","Status":"Up","Ports":"0.0.0.0:8080->80/tcp, [::]:8080->80/tcp, 127.0.0.1:9000->9000/tcp"}"#
        let container = try XCTUnwrap(try JSONLines.decode(DockerContainer.self, from: data).first)
        XCTAssertEqual(container.webPorts, [8080, 9000])
        let project = try XCTUnwrap(try JSONLines.decode(ComposeProject.self, from: #"[{"Name":"test","Status":"running(2)","ConfigFiles":"/a space/compose.yml,/b/override.yml"}]"#).first)
        XCTAssertEqual(DockerService.composeArguments(project, action: ["up", "-d"]), ["compose", "--project-name", "test", "--file", "/a space/compose.yml", "--file", "/b/override.yml", "up", "-d"])
    }
    func testInputValidation() {
        XCTAssertTrue(InputValidation.profileName("work-2"))
        XCTAssertFalse(InputValidation.profileName("../default"))
        XCTAssertFalse(InputValidation.profileName("--help"))
        XCTAssertTrue(InputValidation.environment("TOKEN=value=with=equals"))
        XCTAssertFalse(InputValidation.environment("bad-key=x"))
        XCTAssertTrue(InputValidation.port("127.0.0.1:8080:80/tcp"))
        XCTAssertFalse(InputValidation.port("70000:80"))
        XCTAssertFalse(InputValidation.port("0:80"))
    }
    func testDockerStatsAndProxyWireKeys() throws {
        let stats = try XCTUnwrap(try JSONLines.decode(ContainerStats.self, from: #"{"ID":"abc","Name":"web","CPUPerc":"2.5%","MemUsage":"32.5MiB / 2GiB","MemPerc":"1.6%"}"#).first)
        XCTAssertEqual(stats.cpu, 2.5)
        XCTAssertEqual(stats.memoryBytes, 32.5 * 1_048_576)
        let info = try JSONDecoder().decode(EngineInfo.self, from: Data(#"{"ServerVersion":"29.5.2","NCPU":2,"MemTotal":2147483648,"Driver":"overlayfs","DockerRootDir":"/var/lib/docker","OperatingSystem":"Ubuntu","HttpProxy":"http://host.lima.internal:7890","HttpsProxy":"http://host.lima.internal:7890"}"#.utf8))
        XCTAssertEqual(info.HTTPProxy, "http://host.lima.internal:7890")
    }
    func testStoragePhysicalAllocationAndFilesystemAccounting() throws {
        XCTAssertEqual(try StorageParsing.allocatedBytes("6085220\t/Users/test/a space/.colima\n"), 6_085_220 * 1024)
        let output = """
        Filesystem 1024-blocks Used Available Capacity Mounted on
        /dev/root 19221248 1184196 18020668 7% /
        /dev/vdb1 20464208 4499376 14899976 24% /var/lib/docker
        """
        let disks = try StorageParsing.fileSystems(output)
        XCTAssertEqual(disks.count, 2)
        XCTAssertEqual(disks[0].mount, "/")
        XCTAssertEqual(disks[1].capacity, 20_464_208 * 1024)
        XCTAssertEqual(disks[1].used, 4_499_376 * 1024)
        XCTAssertEqual(disks[1].available, 14_899_976 * 1024)
        XCTAssertEqual(disks[1].usedPercent, 24)
        XCTAssertEqual(ByteSize.binary(5.8 * 1_073_741_824), "5.8 GiB")
        XCTAssertEqual(ByteSize.binary(0), "0 B")
    }
    func testStorageRejectsMissingStatsAndHandlesFullDisks() throws {
        XCTAssertThrowsError(try StorageParsing.allocatedBytes(""))
        XCTAssertThrowsError(try StorageParsing.allocatedBytes("permission denied"))
        XCTAssertThrowsError(try StorageParsing.fileSystems("Filesystem 1024-blocks Used Available Capacity Mounted on\n"))
        XCTAssertThrowsError(try StorageParsing.fileSystems("header\n/dev/vdb1 invalid 100 200 30% /data"))
        let disk = try XCTUnwrap(StorageParsing.fileSystems("header\n/dev/vdb1 1000 995 -45 105% /data with spaces").first)
        XCTAssertEqual(disk.available, 0)
        XCTAssertEqual(disk.usedPercent, 105)
        XCTAssertEqual(disk.mount, "/data with spaces")
    }
    func testEnglishAndChineseLocalizationWithLiteralArguments() {
        let title: LocalizedText = "存储占用"
        XCTAssertEqual(title.localized(language: "en"), "Storage")
        XCTAssertEqual(title.localized(language: "zh-Hans"), "存储占用")
        let name = "name {1} 50% 'quote'"
        let operation: LocalizedText = "创建\(name) \(5)"
        XCTAssertEqual(operation.localized(language: "en"), "Create name {1} 50% 'quote' 5")
        XCTAssertEqual(operation.localized(language: "zh-Hans"), "创建name {1} 50% 'quote' 5")
        let usage: LocalizedText = "可用 \("14.2 GiB") · 文件系统容量 \("19.5 GiB")"
        XCTAssertEqual(usage.localized(language: "en"), "Available 14.2 GiB · Filesystem capacity 19.5 GiB")
    }
    func testLocalizationCatalogCoverageAndPlaceholders() throws {
        func catalog(_ language: String) throws -> [String: String] {
            let url = Localization.resources.bundleURL.appendingPathComponent("\(language).lproj/Localizable.strings")
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
        }
        let english = try catalog("en"), chinese = try catalog("zh-Hans")
        XCTAssertFalse(english.isEmpty)
        XCTAssertEqual(english.keys.sorted(), chinese.keys.sorted())
        let regex = try NSRegularExpression(pattern: #"\{\d+\}"#)
        func placeholders(_ string: String) -> [String] {
            let text = string as NSString
            return regex.matches(in: string, range: NSRange(location: 0, length: text.length)).map { text.substring(with: $0.range) }.sorted()
        }
        for (key, value) in english {
            XCTAssertNil(value.range(of: #"\p{Han}"#, options: .regularExpression), "Untranslated: \(key)")
            XCTAssertEqual(placeholders(key), placeholders(value), "Placeholder mismatch: \(key)")
        }
    }
    func testRunnerPreservesArgumentsWithoutShellExpansion() async throws {
        let literal = "$(touch /tmp/should-not-exist) `whoami` ; space ' quote"
        let result = try await CommandRunner().run(executable: "/usr/bin/printf", arguments: ["%s", literal])
        XCTAssertEqual(result.stdout, literal)
    }
    func testRunnerDrainsBothPipes() async throws {
        let result = try await CommandRunner().run(executable: "/bin/sh", arguments: ["-c", "i=0; while [ $i -lt 12000 ]; do printf 'stdout row\\n'; printf 'stderr row\\n' >&2; i=$((i+1)); done"], timeout: 10)
        XCTAssertEqual(result.stdout.components(separatedBy: "\n").count, 12001)
        XCTAssertEqual(result.stderr.components(separatedBy: "\n").count, 12001)
    }
    func testRunnerTimeout() async {
        do {
            _ = try await CommandRunner().run(executable: "/bin/sleep", arguments: ["5"], timeout: 0.1)
            XCTFail("Expected timeout")
        } catch {
            guard case CommandFailure.timedOut = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }
    func testRunnerCancellation() async throws {
        let task = Task { try await CommandRunner().run(executable: "/bin/sleep", arguments: ["5"]) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { guard case CommandFailure.cancelled = error else { return XCTFail("Unexpected error: \(error)") } }
    }
}
