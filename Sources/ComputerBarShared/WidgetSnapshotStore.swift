import Foundation

public enum ComputerBarWidgetConstants {
    public static let appBundleIdentifier = "com.computerbar.app"
    public static let widgetBundleIdentifier = "com.computerbar.app.widget"
    public static let statusWidgetKind = "ComputerBarStatusWidget"
    public static let snapshotFilename = "widget-snapshot.json"
    public static let snapshotDirectoryName = "ComputerBar"
    public static let snapshotDefaultsKey = "widgetSnapshotData"
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

    public var updatedAtText: String {
        guard let updatedAt else { return "--" }
        return updatedAt.formatted(date: .omitted, time: .standard)
    }

    public var hasMetrics: Bool {
        cpuUsagePercent != nil || memoryUsagePercent != nil
    }

    private func metricText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))%"
    }
}

public enum WidgetSnapshotStore {
    public static let appGroupIdentifier = "group.com.computerbar.shared"
    private static let legacyAppGroupIdentifier = "group.com.sshbar.shared"
    private static let legacySnapshotDirectoryName = "SSHBar"

    public static var snapshotURL: URL {
        writeSnapshotURLs.first ?? legacySnapshotURL
    }

    public static func load() throws -> WidgetSnapshot {
        let fileManager = FileManager.default
        var loadedSnapshots: [WidgetSnapshot] = []
        var lastError: Error?

        if let sharedDefaults,
           let data = sharedDefaults.data(forKey: ComputerBarWidgetConstants.snapshotDefaultsKey) {
            do {
                loadedSnapshots.append(try decodeSnapshot(from: data))
            } catch {
                lastError = error
            }
        }

        if let legacySharedDefaults,
           let data = legacySharedDefaults.data(forKey: ComputerBarWidgetConstants.snapshotDefaultsKey) {
            do {
                loadedSnapshots.append(try decodeSnapshot(from: data))
            } catch {
                lastError = error
            }
        }

        for url in readSnapshotURLs where fileManager.fileExists(atPath: url.path) {
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

        if let sharedDefaults {
            sharedDefaults.set(data, forKey: ComputerBarWidgetConstants.snapshotDefaultsKey)
            sharedDefaults.synchronize()
            savedAtLeastOnce = true
        }

        for url in writeSnapshotURLs {
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
        sharedDefaults?.removeObject(forKey: ComputerBarWidgetConstants.snapshotDefaultsKey)
        sharedDefaults?.synchronize()
        for url in writeSnapshotURLs where fileManager.fileExists(atPath: url.path) {
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

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private static var legacySharedDefaults: UserDefaults? {
        UserDefaults(suiteName: legacyAppGroupIdentifier)
    }

    private static func decodeSnapshot(from data: Data) throws -> WidgetSnapshot {
        try decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func newestSnapshot(in snapshots: [WidgetSnapshot]) -> WidgetSnapshot? {
        snapshots.max { lhs, rhs in
            lhs.generatedAt < rhs.generatedAt
        }
    }

    private static var writeSnapshotURLs: [URL] {
        var urls: [URL] = []

        urls.append(contentsOf: appGroupSnapshotURLs(for: appGroupIdentifier))

        guard !isWidgetExtension else {
            return uniqueURLs(urls)
        }

        if let ownAppSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(
                ownAppSupportURL
                    .appending(path: ComputerBarWidgetConstants.snapshotDirectoryName, directoryHint: .isDirectory)
                    .appending(path: ComputerBarWidgetConstants.snapshotFilename)
            )
        }

        urls.append(legacySnapshotURL)
        urls.append(contentsOf: widgetSandboxSnapshotURLs)

        return uniqueURLs(urls)
    }

    private static var readSnapshotURLs: [URL] {
        if isWidgetExtension {
            return uniqueURLs(widgetLocalSnapshotURLs + appGroupSnapshotURLs(for: appGroupIdentifier))
        }

        return uniqueURLs(writeSnapshotURLs + legacyCandidateSnapshotURLs)
    }

    /// Paths inside the widget extension's sandbox container, writable by the unsandboxed main app.
    private static var widgetSandboxSnapshotURLs: [URL] {
        let containerPath = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers", directoryHint: .isDirectory)
            .appending(path: ComputerBarWidgetConstants.widgetBundleIdentifier, directoryHint: .isDirectory)
            .appending(path: "Data", directoryHint: .isDirectory)

        return [
            containerPath
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
                .appending(path: ComputerBarWidgetConstants.snapshotDirectoryName, directoryHint: .isDirectory)
                .appending(path: ComputerBarWidgetConstants.snapshotFilename),
            containerPath
                .appending(path: ComputerBarWidgetConstants.snapshotFilename)
        ]
    }

    /// Paths the widget extension can read from within its own sandbox.
    private static var widgetLocalSnapshotURLs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
                .appending(path: ComputerBarWidgetConstants.snapshotDirectoryName, directoryHint: .isDirectory)
                .appending(path: ComputerBarWidgetConstants.snapshotFilename),
            home
                .appending(path: ComputerBarWidgetConstants.snapshotFilename)
        ]
    }

    private static var legacyCandidateSnapshotURLs: [URL] {
        guard !isWidgetExtension else {
            return []
        }

        var urls: [URL] = []

        if let ownAppSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(
                ownAppSupportURL
                    .appending(path: legacySnapshotDirectoryName, directoryHint: .isDirectory)
                    .appending(path: ComputerBarWidgetConstants.snapshotFilename)
            )
        }

        if let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: legacyAppGroupIdentifier) {
            urls.append(
                sharedContainerURL
                    .appending(path: "Library/Application Support", directoryHint: .isDirectory)
                    .appending(path: legacySnapshotDirectoryName, directoryHint: .isDirectory)
                    .appending(path: ComputerBarWidgetConstants.snapshotFilename)
            )
            urls.append(
                sharedContainerURL
                    .appending(path: ComputerBarWidgetConstants.snapshotFilename)
            )
        }

        return urls
    }

    private static func appGroupSnapshotURLs(for appGroupIdentifier: String) -> [URL] {
        guard let sharedContainerURL = FileManager.default.containerURL(
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

    private static var legacySnapshotURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
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
