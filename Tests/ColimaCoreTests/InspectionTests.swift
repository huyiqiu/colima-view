import XCTest
@testable import ColimaCore

final class InspectionTests: XCTestCase {
    func testContainerInspectProjectsOptionalFieldsAndPreservesEnvironmentValues() throws {
        let document = try DockerInspection(json: #"""
        [{"Id":"container-id","State":{"Running":false,"ExitCode":0},
          "Config":{"Env":["TOKEN=a=b=c","EMPTY=","NO_EQUALS", "=value"],"Labels":null},
          "HostConfig":{"Memory":1073741824},"Mounts":null,
          "DriverSpecific":{"Nested":{"Enabled":true}}}]
        """#)
        XCTAssertEqual(document.string("Id"), "container-id")
        XCTAssertEqual(document.value("State", "Running").bool, false)
        XCTAssertEqual(document.value("State", "ExitCode").number, 0)
        XCTAssertNil(document.value("State", "ExitCode").bool)
        XCTAssertEqual(document.value("HostConfig", "Memory").number, 1_073_741_824)
        XCTAssertEqual(document.environment.map(\.value), ["a=b=c", "", "", "value"])
        XCTAssertEqual(document.environment.map(\.key), ["TOKEN", "EMPTY", "NO_EQUALS", ""])
        XCTAssertTrue(document.value("Config", "Labels").entries.isEmpty)
        XCTAssertTrue(document.value("Mounts").array.isEmpty)
        XCTAssertEqual(document.value("DriverSpecific", "Nested", "Enabled").bool, true)
        XCTAssertNil(document.string("Missing", "Nested"))
    }

    func testPortBindingsKeepExposedPortsIPv6AndUDPDistinct() throws {
        let document = try DockerInspection(json: #"""
        [{"NetworkSettings":{"Ports":{
          "443/tcp":null,
          "80/tcp":[{"HostIp":"0.0.0.0","HostPort":"8080"},{"HostIp":"::1","HostPort":"8080"}],
          "53/udp":[{"HostIp":"127.0.0.1","HostPort":"5353"}],
          "123/tcp":[{"HostIp":"::","HostPort":"0"}],
          "124/tcp":[{"HostIp":"user@other.example/path","HostPort":"8080"}]
        }}}]
        """#)
        XCTAssertEqual(document.ports.count, 6)
        XCTAssertEqual(Set(document.ports.map(\.id)).count, 6)
        XCTAssertNil(try XCTUnwrap(document.ports.first { $0.containerPort == "443/tcp" }).hostPort)
        XCTAssertNil(try XCTUnwrap(document.ports.first { $0.containerPort == "53/udp" }).browserURL)
        XCTAssertNil(try XCTUnwrap(document.ports.first { $0.containerPort == "123/tcp" }).browserURL)
        XCTAssertNil(try XCTUnwrap(document.ports.first { $0.containerPort == "124/tcp" }).browserURL)
        let http = document.ports.filter { $0.containerPort == "80/tcp" }
        XCTAssertEqual(http.map { $0.browserURL?.absoluteString }, ["http://127.0.0.1:8080", "http://[::1]:8080"])
    }

    func testImageVolumeAndNetworkInspectShapes() throws {
        let image = try DockerInspection(json: #"[{"Id":"sha256:image","Config":{"Entrypoint":null,"Cmd":["/bin/app","argument with spaces"]},"RootFS":{"Layers":["a","b"]},"RepoTags":["example:latest"]}]"#)
        XCTAssertTrue(image.value("Config", "Entrypoint").strings.isEmpty)
        XCTAssertEqual(image.value("Config", "Cmd").strings, ["/bin/app", "argument with spaces"])
        XCTAssertEqual(image.value("RootFS", "Layers").array.count, 2)
        let volume = try DockerInspection(json: #"{"Name":"data","Options":null,"Labels":{"z":"last","a":"first"}}"#)
        XCTAssertEqual(volume.string("Name"), "data")
        XCTAssertEqual(volume.value("Labels").entries.map(\.key), ["a", "z"])
        XCTAssertTrue(volume.value("Options").entries.isEmpty)
        let network = try DockerInspection(json: #"[{"Internal":false,"IPAM":{"Config":[{"Subnet":"172.20.0.0/16","Gateway":"172.20.0.1"}]},"Containers":{"id":{"Name":"web","IPv4Address":"172.20.0.2/16"}}}]"#)
        XCTAssertEqual(network.value("Internal").bool, false)
        XCTAssertEqual(network.value("IPAM", "Config").array.first?["Gateway"].string, "172.20.0.1")
        XCTAssertEqual(network.value("Containers").entries.first?.value["Name"].string, "web")
    }

    func testRejectsEmptyMultipleAndInvalidInspectResults() {
        for json in ["", "[]", "[{},{}]", "null", "true", "123", #""string""#, "invalid"] {
            XCTAssertThrowsError(try DockerInspection(json: json), json)
        }
    }
}
