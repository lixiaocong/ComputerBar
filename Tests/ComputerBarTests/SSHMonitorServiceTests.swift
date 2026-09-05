import XCTest
@testable import ComputerBar

final class SSHMonitorServiceTests: XCTestCase {
    func testParseStatusOutputBuildsNodeStatus() throws {
        let host = SSHHost(alias: "dev", hostName: "example.internal", user: "ubuntu", port: 22)
        let collectedAt = Date(timeIntervalSince1970: 1_718_000_000)
        let output = """
        cpu_percent=23.50
        mem_total_kb=2048000
        mem_available_kb=512000
        swap_total_kb=1048576
        swap_free_kb=786432
        disk_total_kb=8192000
        disk_used_kb=2048000
        loadavg=0.10 0.20 0.30
        uptime_seconds=3661.12
        """

        let status = try SSHMonitorService.parseStatusOutput(output, host: host, collectedAt: collectedAt)

        XCTAssertEqual(status.host, host)
        XCTAssertEqual(status.cpuUsagePercent, 23.5, accuracy: 0.001)
        XCTAssertEqual(status.memoryUsagePercent, 75, accuracy: 0.001)
        XCTAssertEqual(status.memoryUsedBytes, 1_572_864_000)
        XCTAssertEqual(status.memoryTotalBytes, 2_097_152_000)
        XCTAssertEqual(try XCTUnwrap(status.virtualMemoryUsagePercent), 25, accuracy: 0.001)
        XCTAssertEqual(status.virtualMemoryUsedBytes, 268_435_456)
        XCTAssertEqual(status.virtualMemoryTotalBytes, 1_073_741_824)
        XCTAssertEqual(status.diskUsagePercent, 25, accuracy: 0.001)
        XCTAssertEqual(status.diskUsedBytes, 2_097_152_000)
        XCTAssertEqual(status.diskTotalBytes, 8_388_608_000)
        XCTAssertEqual(status.loadAverages, [0.10, 0.20, 0.30])
        XCTAssertEqual(status.uptimeSeconds, 3_661.12, accuracy: 0.001)
        XCTAssertEqual(status.collectedAt, collectedAt)
    }

    func testParseStatusOutputOmitsVirtualMemoryWhenSwapIsDisabled() throws {
        let host = SSHHost(alias: "dev", hostName: "example.internal", user: "ubuntu", port: 22)
        let output = """
        cpu_percent=23.50
        mem_total_kb=2048000
        mem_available_kb=512000
        swap_total_kb=0
        swap_free_kb=0
        disk_total_kb=8192000
        disk_used_kb=2048000
        loadavg=0.10 0.20 0.30
        uptime_seconds=3661.12
        """

        let status = try SSHMonitorService.parseStatusOutput(output, host: host, collectedAt: .now)

        XCTAssertFalse(status.hasVirtualMemoryUsage)
        XCTAssertNil(status.virtualMemoryUsagePercent)
        XCTAssertEqual(status.virtualMemoryUsageText, "--")
    }

    func testParseStatusOutputThrowsForMissingFields() {
        let host = SSHHost(alias: "dev", hostName: "example.internal", user: nil, port: nil)
        let output = """
        mem_total_kb=2048000
        mem_available_kb=512000
        disk_total_kb=8192000
        disk_used_kb=2048000
        loadavg=0.10 0.20 0.30
        uptime_seconds=3661.12
        """

        XCTAssertThrowsError(try SSHMonitorService.parseStatusOutput(output, host: host, collectedAt: .now))
    }
}
