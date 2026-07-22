import XCTest
@testable import ComputerBarShared

final class WidgetSnapshotStoreTests: XCTestCase {
    func testSnapshotEncodingRoundTrip() throws {
        let snapshot = WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_718_000_000),
            lastRefreshAt: Date(timeIntervalSince1970: 1_718_000_120),
            primaryAlias: "dev",
            selectedHosts: [
                WidgetHostSnapshot(
                    alias: "dev",
                    endpointDescription: "ubuntu@example.internal:22",
                    cpuUsagePercent: 31.5,
                    memoryUsagePercent: 68.2,
                    memoryUsedBytes: 2_147_483_648,
                    memoryTotalBytes: 4_294_967_296,
                    virtualMemoryUsagePercent: 25,
                    virtualMemoryUsedBytes: 1_073_741_824,
                    virtualMemoryTotalBytes: 4_294_967_296,
                    loadAverages: [0.1, 0.2, 0.3],
                    uptimeSeconds: 3_661,
                    updatedAt: Date(timeIntervalSince1970: 1_718_000_100),
                    errorMessage: nil
                )
            ],
            configErrorMessage: nil
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "widget-snapshot.json")

        try FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.iso8601Encoder.encode(snapshot)
        try data.write(to: tempURL)
        let reloaded = try JSONDecoder.iso8601Decoder.decode(WidgetSnapshot.self, from: Data(contentsOf: tempURL))

        XCTAssertEqual(reloaded, snapshot)
        XCTAssertEqual(reloaded.selectedHosts.first?.virtualMemoryUsageText, "25%")
        XCTAssertEqual(reloaded.selectedHosts.first?.virtualMemoryUsedBytes, 1_073_741_824)
        XCTAssertEqual(reloaded.selectedHosts.first?.virtualMemoryTotalBytes, 4_294_967_296)
    }

    func testStoreChoosesNewestGeneratedSnapshot() {
        let olderSnapshot = WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_718_000_000),
            lastRefreshAt: nil,
            primaryAlias: "old",
            selectedHosts: [],
            configErrorMessage: nil
        )
        let newerSnapshot = WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_718_000_600),
            lastRefreshAt: nil,
            primaryAlias: "new",
            selectedHosts: [],
            configErrorMessage: nil
        )

        let selectedSnapshot = WidgetSnapshotStore.newestSnapshot(in: [olderSnapshot, newerSnapshot])

        XCTAssertEqual(selectedSnapshot?.primaryAlias, "new")
    }

    func testHostSnapshotWritesNeverTargetWidgetContainer() {
        let widgetContainerFragment = "/Library/Containers/\(ComputerBarWidgetConstants.widgetBundleIdentifier)/"
        let urls = WidgetSnapshotStore.writeSnapshotURLs(
            fileManager: .default,
            isWidgetExtension: false
        )

        XCTAssertFalse(urls.isEmpty)
        XCTAssertTrue(urls.allSatisfy { !$0.standardizedFileURL.path.contains(widgetContainerFragment) })
    }

    func testAppGroupUsesStableTeamIdentifierPrefix() {
        XCTAssertEqual(
            WidgetSnapshotStore.appGroupIdentifier,
            "CP22VZ6846.com.computerbar.app.shared"
        )
    }
}

private extension JSONEncoder {
    static var iso8601Encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso8601Decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
