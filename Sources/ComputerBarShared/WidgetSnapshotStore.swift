import Foundation
import Security

public enum ComputerBarWidgetConstants {
    public static let appBundleIdentifier = "com.computerbar.app"
    public static let widgetBundleIdentifier = "com.computerbar.app.widget"
    public static let statusWidgetKind = "ComputerBarStatusWidget"
    public static let legacyStatusWidgetKind = "ComputerBarStatusWidget-2"
    public static let snapshotFilename = "widget-snapshot.json"
    public static let snapshotDirectoryName = "ComputerBar"
    public static let localSnapshotServerPort: UInt16 = 61337
    public static let localSnapshotServerPath = "/widget-snapshot"
}

public struct WidgetSnapshot: Codable, Equatable {
    public let generatedAt: Date
    public let lastRefreshAt: Date?
    public let primaryAlias: String?
    public let selectedHosts: [WidgetHostSnapshot]
    public let configErrorMessage: String?

    public init(
        generatedAt: Date,
        lastRefreshAt: Date?,
        primaryAlias: String?,
        selectedHosts: [WidgetHostSnapshot],
        configErrorMessage: String?
    ) {
        self.generatedAt = generatedAt
        self.lastRefreshAt = lastRefreshAt
        self.primaryAlias = primaryAlias
        self.selectedHosts = selectedHosts
        self.configErrorMessage = configErrorMessage
    }
}

public struct WidgetHostSnapshot: Codable, Equatable, Identifiable {
    public let alias: String
    public let displayName: String?
    public let endpointDescription: String
    public let cpuUsagePercent: Double?
    public let memoryUsagePercent: Double?
    public let memoryUsedBytes: UInt64?
    public let memoryTotalBytes: UInt64?
    public let virtualMemoryUsagePercent: Double?
    public let virtualMemoryUsedBytes: UInt64?
    public let virtualMemoryTotalBytes: UInt64?
    public let diskUsagePercent: Double?
    public let diskUsedBytes: UInt64?
    public let diskTotalBytes: UInt64?
    public let loadAverages: [Double]
    public let uptimeSeconds: TimeInterval?
    public let updatedAt: Date?
    public let errorMessage: String?

    public init(
        alias: String,
        displayName: String? = nil,
        endpointDescription: String,
        cpuUsagePercent: Double?,
        memoryUsagePercent: Double?,
        memoryUsedBytes: UInt64?,
        memoryTotalBytes: UInt64?,
        virtualMemoryUsagePercent: Double? = nil,
        virtualMemoryUsedBytes: UInt64? = nil,
        virtualMemoryTotalBytes: UInt64? = nil,
        diskUsagePercent: Double? = nil,
        diskUsedBytes: UInt64? = nil,
        diskTotalBytes: UInt64? = nil,
        loadAverages: [Double],
        uptimeSeconds: TimeInterval?,
        updatedAt: Date?,
        errorMessage: String?
    ) {
        self.alias = alias
        self.displayName = displayName
        self.endpointDescription = endpointDescription
        self.cpuUsagePercent = cpuUsagePercent
        self.memoryUsagePercent = memoryUsagePercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.virtualMemoryUsagePercent = virtualMemoryUsagePercent
        self.virtualMemoryUsedBytes = virtualMemoryUsedBytes
        self.virtualMemoryTotalBytes = virtualMemoryTotalBytes
        self.diskUsagePercent = diskUsagePercent
        self.diskUsedBytes = diskUsedBytes
        self.diskTotalBytes = diskTotalBytes
        self.loadAverages = loadAverages
        self.uptimeSeconds = uptimeSeconds
        self.updatedAt = updatedAt
        self.errorMessage = errorMessage
    }

    public var id: String { alias }

    /// The name to show in the widget header. Falls back to alias if no displayName is set.
    public var widgetTitle: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        if alias.hasPrefix("__") && alias.hasSuffix("__") {
            return "This Mac"
        }
        return alias
    }

    public var cpuUsageText: String {
        metricText(cpuUsagePercent)
    }

    public var memoryUsageText: String {
        metricText(memoryUsagePercent)
    }

    public var diskUsageText: String {
        metricText(diskUsagePercent)
    }

    public var hasVirtualMemoryUsage: Bool {
        virtualMemoryUsagePercent != nil
    }

    public var virtualMemoryUsageText: String {
        metricText(virtualMemoryUsagePercent)
    }

    public var loadAverageText: String {
        guard !loadAverages.isEmpty else { return "--" }
        return loadAverages.prefix(3)
            .map { String(format: "%.2f", $0) }
            .joined(separator: "  ")
    }

    /// Shorter load average for widget detail blocks (1-min only).
    public var loadAverageShort: String {
        guard let first = loadAverages.first else { return "--" }
        return String(format: "%.2f", first)
    }

    public var uptimeText: String {
        guard let uptimeSeconds else { return "--" }
        return uptimeSeconds.compactDurationString
    }

    public var memoryUsageSummary: String {
        guard let memoryUsedBytes, let memoryTotalBytes else { return "--" }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(memoryUsedBytes), countStyle: .binary)) / \(ByteCountFormatter.string(fromByteCount: Int64(memoryTotalBytes), countStyle: .binary))"
    }

    public var virtualMemoryUsageSummary: String {
        guard let virtualMemoryUsedBytes, let virtualMemoryTotalBytes else { return "--" }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(virtualMemoryUsedBytes), countStyle: .binary)) / \(ByteCountFormatter.string(fromByteCount: Int64(virtualMemoryTotalBytes), countStyle: .binary))"
    }

    public var diskUsageSummary: String {
        guard let diskUsedBytes, let diskTotalBytes else { return "--" }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(diskUsedBytes), countStyle: .binary)) / \(ByteCountFormatter.string(fromByteCount: Int64(diskTotalBytes), countStyle: .binary))"
    }

    public var updatedAtText: String {
        guard let updatedAt else { return "--" }
        return updatedAt.formatted(date: .omitted, time: .standard)
    }

    public var hasMetrics: Bool {
        cpuUsagePercent != nil
            || memoryUsagePercent != nil
            || virtualMemoryUsagePercent != nil
            || diskUsagePercent != nil
    }

    private func metricText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))%"
    }
}

public enum WidgetSnapshotStore {
    private static let appGroupIdentifierSuffix = ".com.computerbar.app.shared"
    private static let legacySnapshotDirectoryName = "SSHBar"

    public static var snapshotURL: URL {
        writeSnapshotURLs(fileManager: .default).first ?? legacySnapshotURL(fileManager: .default)
    }

    public static func load() throws -> WidgetSnapshot {
        let fileManager = FileManager.default
        var loadedSnapshots: [WidgetSnapshot] = []
        var lastError: Error?

        for url in readSnapshotURLs(fileManager: fileManager) where fileManager.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                loadedSnapshots.append(try decodeSnapshot(from: data))
            } catch {
                lastError = error
            }
        }

        if let newestSnapshot = newestSnapshot(in: loadedSnapshots) {
            return newestSnapshot
        }

        throw lastError ?? CocoaError(.fileReadNoSuchFile)
    }

    public static func loadIfAvailable() -> WidgetSnapshot? {
        try? load()
    }

    public static func save(_ snapshot: WidgetSnapshot) throws {
        let fileManager = FileManager.default
        let data = try encoder.encode(snapshot)
        var savedAtLeastOnce = false
        var lastError: Error?

        for url in writeSnapshotURLs(fileManager: fileManager) {
            do {
                let directoryURL = url.deletingLastPathComponent()
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                savedAtLeastOnce = true
            } catch {
                lastError = error
            }
        }

        if !savedAtLeastOnce {
            throw lastError ?? CocoaError(.fileWriteUnknown)
        }
    }

    public static func delete() throws {
        let fileManager = FileManager.default
        for url in writeSnapshotURLs(fileManager: fileManager) where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func decodeSnapshot(from data: Data) throws -> WidgetSnapshot {
        try decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func newestSnapshot(in snapshots: [WidgetSnapshot]) -> WidgetSnapshot? {
        snapshots.max { lhs, rhs in
            lhs.generatedAt < rhs.generatedAt
        }
    }

    static func writeSnapshotURLs(
        fileManager: FileManager,
        isWidgetExtension: Bool = Self.isWidgetExtension
    ) -> [URL] {
        var urls: [URL] = []

        urls.append(contentsOf: appGroupSnapshotURLs(fileManager: fileManager))

        guard !isWidgetExtension else {
            return uniqueURLs(urls)
        }

        if let ownAppSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(
                ownAppSupportURL
                    .appending(path: ComputerBarWidgetConstants.snapshotDirectoryName, directoryHint: .isDirectory)
                    .appending(path: ComputerBarWidgetConstants.snapshotFilename)
            )
        }

        urls.append(legacySnapshotURL(fileManager: fileManager))

        return uniqueURLs(urls)
    }

    private static func readSnapshotURLs(fileManager: FileManager) -> [URL] {
        if isWidgetExtension {
            return uniqueURLs(
                widgetLocalSnapshotURLs(fileManager: fileManager)
                    + appGroupSnapshotURLs(fileManager: fileManager)
            )
        }

        return uniqueURLs(
            writeSnapshotURLs(fileManager: fileManager)
                + legacyCandidateSnapshotURLs(fileManager: fileManager)
        )
    }

    /// Legacy paths the widget extension can read from within its own sandbox.
    /// The host app must never write here; doing so triggers macOS App Data access.
    private static func widgetLocalSnapshotURLs(fileManager: FileManager) -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        return [
            home
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
                .appending(path: ComputerBarWidgetConstants.snapshotDirectoryName, directoryHint: .isDirectory)
                .appending(path: ComputerBarWidgetConstants.snapshotFilename),
            home
                .appending(path: ComputerBarWidgetConstants.snapshotFilename)
        ]
    }

    private static func legacyCandidateSnapshotURLs(fileManager: FileManager) -> [URL] {
        guard !isWidgetExtension else {
            return []
        }

        var urls: [URL] = []

        if let ownAppSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(
                ownAppSupportURL
                    .appending(path: legacySnapshotDirectoryName, directoryHint: .isDirectory)
                    .appending(path: ComputerBarWidgetConstants.snapshotFilename)
            )
        }

        return urls
    }

    private static func appGroupSnapshotURLs(fileManager: FileManager) -> [URL] {
        guard let appGroupIdentifier = processAppGroupIdentifier,
              let sharedContainerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return []
        }

        return [
            sharedContainerURL
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
                .appending(path: ComputerBarWidgetConstants.snapshotDirectoryName, directoryHint: .isDirectory)
                .appending(path: ComputerBarWidgetConstants.snapshotFilename),
            sharedContainerURL
                .appending(path: ComputerBarWidgetConstants.snapshotFilename)
        ]
    }

    private static var processAppGroupIdentifier: String? {
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.security.application-groups" as CFString,
                nil
              ) as? [String] else {
            return nil
        }
        return appGroupIdentifier(in: groups)
    }

    static func appGroupIdentifier(in signedGroups: [String]) -> String? {
        signedGroups.first { $0.hasSuffix(appGroupIdentifierSuffix) }
    }

    private static func legacySnapshotURL(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
            .appending(path: ComputerBarWidgetConstants.snapshotDirectoryName, directoryHint: .isDirectory)
            .appending(path: ComputerBarWidgetConstants.snapshotFilename)
    }

    private static var isWidgetExtension: Bool {
        let mainBundle = Bundle.main
        return mainBundle.bundleIdentifier == ComputerBarWidgetConstants.widgetBundleIdentifier
            || mainBundle.bundlePath.hasSuffix(".appex")
            || mainBundle.infoDictionary?["NSExtension"] != nil
            || ProcessInfo.processInfo.processName == "ComputerBarWidgetExtension"
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}

private extension TimeInterval {
    var compactDurationString: String {
        let totalSeconds = max(0, Int(self.rounded(.down)))
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        var parts: [String] = []
        if days > 0 {
            parts.append("\(days)d")
        }
        if hours > 0 {
            parts.append("\(hours)h")
        }
        if minutes > 0, parts.count < 2 {
            parts.append("\(minutes)m")
        }
        if parts.isEmpty {
            parts.append("\(seconds)s")
        }

        return parts.joined(separator: " ")
    }
}
