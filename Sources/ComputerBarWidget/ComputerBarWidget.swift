import AppIntents
import SwiftUI
import WidgetKit
#if canImport(ComputerBarShared)
import ComputerBarShared
#endif

private final class WidgetSnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: WidgetSnapshot?

    func set(_ snapshot: WidgetSnapshot?) {
        lock.lock()
        self.snapshot = snapshot
        lock.unlock()
    }

    func get() -> WidgetSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }
}

struct ComputerBarWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let selectedAlias: String?
}

struct ComputerBarHostSelection: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Host")
    static let defaultQuery = ComputerBarHostSelectionQuery()

    let id: String
    let title: String
    let subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitle)"
        )
    }
}

struct ComputerBarHostSelectionQuery: EntityQuery {
    func entities(for identifiers: [ComputerBarHostSelection.ID]) async throws -> [ComputerBarHostSelection] {
        let selections = Self.availableSelections()
        return identifiers.map { identifier in
            selections.first { $0.id == identifier } ?? ComputerBarHostSelection(
                id: identifier,
                title: identifier,
                subtitle: "Unavailable host"
            )
        }
    }

    func suggestedEntities() async throws -> [ComputerBarHostSelection] {
        Self.availableSelections()
    }

    func defaultResult() async -> ComputerBarHostSelection? {
        Self.availableSelections().first
    }

    private static func availableSelections() -> [ComputerBarHostSelection] {
        WidgetSnapshotStore.loadIfAvailable()?.selectedHosts.map(selection) ?? []
    }

    private static func selection(for host: WidgetHostSnapshot) -> ComputerBarHostSelection {
        let subtitle: String
        if host.errorMessage != nil {
            subtitle = "Error"
        } else if host.hasMetrics {
            subtitle = "CPU \(host.cpuUsageText), memory \(host.memoryUsageText)"
        } else {
            subtitle = host.endpointDescription
        }

        return ComputerBarHostSelection(
            id: host.alias,
            title: host.alias,
            subtitle: subtitle
        )
    }
}

struct ComputerBarWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Computer Bar"
    static let description = IntentDescription("Shows one monitored computer on the desktop.")

    @Parameter(title: "Host", description: "The ComputerBar host to show in this widget.")
    var host: ComputerBarHostSelection?

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$host)")
    }
}

struct ComputerBarWidgetProvider: AppIntentTimelineProvider {
    typealias Intent = ComputerBarWidgetConfigurationIntent

    private static let missingSnapshotRetryInterval: TimeInterval = 5
    private static let normalRefreshInterval: TimeInterval = 60

    func placeholder(in context: Context) -> ComputerBarWidgetEntry {
        ComputerBarWidgetEntry(
            date: .now,
            snapshot: placeholderSnapshot,
            selectedAlias: placeholderSnapshot.selectedHosts.first?.alias
        )
    }

    func snapshot(
        for configuration: ComputerBarWidgetConfigurationIntent,
        in context: Context
    ) async -> ComputerBarWidgetEntry {
        if context.isPreview {
            return placeholder(in: context)
        }

        let snapshot = loadSnapshot() ?? placeholderSnapshot
        return ComputerBarWidgetEntry(
            date: .now,
            snapshot: snapshot,
            selectedAlias: configuration.host?.id
        )
    }

    func timeline(
        for configuration: ComputerBarWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<ComputerBarWidgetEntry> {
        let snapshot = loadSnapshot()
        let entry = ComputerBarWidgetEntry(
            date: .now,
            snapshot: snapshot,
            selectedAlias: configuration.host?.id
        )
        let nextReload = Date().addingTimeInterval(
            snapshot == nil ? Self.missingSnapshotRetryInterval : Self.normalRefreshInterval
        )
        return Timeline(entries: [entry], policy: .after(nextReload))
    }

    private var placeholderSnapshot: WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: .now,
            lastRefreshAt: .now,
            primaryAlias: "dev",
            selectedHosts: [
                WidgetHostSnapshot(
                    alias: "alpha",
                    endpointDescription: "ops@example.internal:22",
                    cpuUsagePercent: 28,
                    memoryUsagePercent: 63,
                    memoryUsedBytes: 6_764_298_240,
                    memoryTotalBytes: 10_737_418_240,
                    loadAverages: [0.42, 0.37, 0.29],
                    uptimeSeconds: 86_400,
                    updatedAt: .now,
                    errorMessage: nil
                ),
                WidgetHostSnapshot(
                    alias: "beta",
                    endpointDescription: "ubuntu@example.internal:22",
                    cpuUsagePercent: 12,
                    memoryUsagePercent: 41,
                    memoryUsedBytes: 2_147_483_648,
                    memoryTotalBytes: 8_589_934_592,
                    loadAverages: [0.09, 0.11, 0.13],
                    uptimeSeconds: 43_200,
                    updatedAt: .now,
                    errorMessage: nil
                )
            ],
            configErrorMessage: nil
        )
    }

    private func loadSnapshot() -> WidgetSnapshot? {
        if let storedSnapshot = WidgetSnapshotStore.loadIfAvailable() {
            return storedSnapshot
        }

        return fetchLiveSnapshot()
    }

    private func fetchLiveSnapshot() -> WidgetSnapshot? {
        guard let url = URL(
            string: "http://127.0.0.1:\(ComputerBarWidgetConstants.localSnapshotServerPort)\(ComputerBarWidgetConstants.localSnapshotServerPath)"
        ) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1
        configuration.timeoutIntervalForResource = 1

        let semaphore = DispatchSemaphore(value: 0)
        let snapshotBox = WidgetSnapshotBox()

        let task = URLSession(configuration: configuration).dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }

            guard
                let data,
                let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            snapshotBox.set(try? decoder.decode(WidgetSnapshot.self, from: data))
        }

        task.resume()
        _ = semaphore.wait(timeout: .now() + 1.2)
        task.cancel()
        return snapshotBox.get()
    }
}

struct ComputerBarStatusWidget: Widget {
    let kind = ComputerBarWidgetConstants.statusWidgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ComputerBarWidgetConfigurationIntent.self,
            provider: ComputerBarWidgetProvider()
        ) { entry in
            ComputerBarWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Computer Bar")
        .description("Shows the latest status for one monitored computer.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct ComputerBarWidgetEntryView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: ComputerBarWidgetEntry

    var body: some View {
        ZStack {
            widgetBackground

            if let snapshot = entry.snapshot {
                content(snapshot)
            } else {
                emptyState(
                    title: "No Snapshot Yet",
                    message: "Open Computer Bar once so it can populate widget data."
                )
            }
        }
        .foregroundStyle(palette.primaryText)
        .containerBackground(for: .widget) {
            widgetBackground
        }
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        if let configErrorMessage = snapshot.configErrorMessage {
            emptyState(title: "SSH Config Problem", message: configErrorMessage)
        } else if let host = selectedHost(in: snapshot) {
            mediumHostView(host, snapshot: snapshot)
        } else if entry.selectedAlias != nil {
            emptyState(
                title: "Host Not Found",
                message: "Edit the widget and choose a ComputerBar host that is still available."
            )
        } else {
            emptyState(
                title: "No Hosts Selected",
                message: "Choose local or SSH hosts in Computer Bar settings to populate this widget."
            )
        }
    }

    private func mediumHostView(_ host: WidgetHostSnapshot, snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryHeader(
                alias: host.alias,
                supportingText: host.endpointDescription,
                refreshText: snapshot.lastRefreshAt?.formatted(date: .omitted, time: .shortened)
            )

            if let errorMessage = host.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 10) {
                    metricCard(title: "CPU", value: host.cpuUsagePercent, text: host.cpuUsageText, tint: .cyan)
                    metricCard(title: "Mem", value: host.memoryUsagePercent, text: host.memoryUsageText, tint: .green)
                }

                HStack(spacing: 8) {
                    detailPill(label: "Load", value: host.loadAverageText)
                    detailPill(label: "Uptime", value: host.uptimeText)
                    detailPill(label: "Updated", value: host.updatedAtText)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func largeView(_ snapshot: WidgetSnapshot) -> some View {
        if snapshot.selectedHosts.count == 1, let host = primaryHost(in: snapshot) {
            VStack(alignment: .leading, spacing: 14) {
                summaryHeader(
                    alias: host.alias,
                    supportingText: host.endpointDescription,
                    refreshText: snapshot.lastRefreshAt?.formatted(date: .omitted, time: .standard)
                )

                if let errorMessage = host.errorMessage {
                    Text(errorMessage)
                        .font(.body)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 12) {
                        largeMetricBlock(title: "CPU", value: host.cpuUsagePercent, text: host.cpuUsageText, tint: .cyan)
                        largeMetricBlock(title: "Mem", value: host.memoryUsagePercent, text: host.memoryUsageText, tint: .green)
                    }

                    Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            detailStatCard(title: "Load", value: host.loadAverageText)
                            detailStatCard(title: "Uptime", value: host.uptimeText)
                        }

                        GridRow {
                            detailStatCard(title: "Memory", value: host.memoryUsageSummary)
                            detailStatCard(title: "Updated", value: host.updatedAtText)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            let hosts = Array(snapshot.selectedHosts.prefix(4))

            VStack(alignment: .leading, spacing: 10) {
                widgetHeader(title: "Computer Bar", subtitle: subtitle(for: snapshot))

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach(hosts) { host in
                        hostTile(host: host, showDetail: false)
                    }
                }

                if let lastRefreshAt = snapshot.lastRefreshAt {
                    Text("Updated \(lastRefreshAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func widgetHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer()
        }
    }

    private func hostTile(host: WidgetHostSnapshot, showDetail: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.alias)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    Text(host.endpointDescription)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(showDetail ? 2 : 1)
                }

                Spacer()

                if showDetail {
                    Text(host.updatedAtText)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                }
            }

            HStack(spacing: 10) {
                metricCard(title: "CPU", value: host.cpuUsagePercent, text: host.cpuUsageText, tint: .cyan)
                metricCard(title: "Mem", value: host.memoryUsagePercent, text: host.memoryUsageText, tint: .green)
            }

            if let errorMessage = host.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(showDetail ? 3 : 2)
            } else if showDetail {
                HStack(spacing: 10) {
                    detailPill(label: "Load", value: host.loadAverageText)
                    detailPill(label: "Uptime", value: host.uptimeText)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.surfaceStroke, lineWidth: 1)
        }
        .shadow(color: palette.shadow, radius: 10, x: 0, y: 4)
    }

    private func metricCard(title: String, value: Double?, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                Text(text)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .monospacedDigit()
            }

            ProgressView(value: value ?? 0, total: 100)
                .tint(tint)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.24 : 0.14))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(colorScheme == .dark ? 0.24 : 0.16), lineWidth: 1)
        }
    }

    private func summaryHeader(alias: String, supportingText: String?, refreshText: String?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(alias)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if let supportingText {
                    Text(supportingText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }

            Spacer(minLength: 0)

            if let refreshText {
                Text(refreshText)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private func largeMetricBlock(title: String, value: Double?, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.secondaryText)

            Text(text)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            ProgressView(value: value ?? 0, total: 100)
                .tint(tint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.24 : 0.14))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(colorScheme == .dark ? 0.24 : 0.16), lineWidth: 1)
        }
    }

    private func detailStatCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryText)

            Text(value)
                .font(.system(.headline, design: .monospaced).weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.pillBackground)
        )
    }

    private func detailPill(label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.secondaryText)
            Text(value)
                .font(.system(.caption2, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(palette.pillBackground, in: Capsule())
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.semibold))

            Text(message)
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func subtitle(for snapshot: WidgetSnapshot) -> String {
        let count = snapshot.selectedHosts.count
        return count == 1 ? "1 selected host" : "\(count) selected hosts"
    }

    private func primaryHost(in snapshot: WidgetSnapshot) -> WidgetHostSnapshot? {
        if let primaryAlias = snapshot.primaryAlias,
           let host = snapshot.selectedHosts.first(where: { $0.alias == primaryAlias }) {
            return host
        }

        return snapshot.selectedHosts.first
    }

    private func selectedHost(in snapshot: WidgetSnapshot) -> WidgetHostSnapshot? {
        if let selectedAlias = entry.selectedAlias,
           let host = snapshot.selectedHosts.first(where: { $0.alias == selectedAlias }) {
            return host
        }

        return primaryHost(in: snapshot)
    }

    private var widgetBackground: some View {
        ZStack {
            LinearGradient(
                colors: [palette.backgroundTop, palette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.06 : 0.52),
                    Color.white.opacity(0)
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
    }

    private var palette: WidgetPalette {
        WidgetPalette(colorScheme: colorScheme)
    }
}

private struct WidgetPalette {
    let backgroundTop: Color
    let backgroundBottom: Color
    let surface: Color
    let surfaceStroke: Color
    let pillBackground: Color
    let primaryText: Color
    let secondaryText: Color
    let shadow: Color

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            backgroundTop = Color(red: 0.16, green: 0.18, blue: 0.22)
            backgroundBottom = Color(red: 0.21, green: 0.24, blue: 0.29)
            surface = Color.white.opacity(0.14)
            surfaceStroke = Color.white.opacity(0.18)
            pillBackground = Color.white.opacity(0.12)
            primaryText = Color.white.opacity(0.98)
            secondaryText = Color.white.opacity(0.78)
            shadow = Color.black.opacity(0.24)
        } else {
            backgroundTop = Color(red: 0.985, green: 0.988, blue: 0.995)
            backgroundBottom = Color(red: 0.945, green: 0.956, blue: 0.976)
            surface = Color.white.opacity(0.86)
            surfaceStroke = Color.black.opacity(0.06)
            pillBackground = Color.white.opacity(0.92)
            primaryText = Color(red: 0.10, green: 0.16, blue: 0.23)
            secondaryText = Color(red: 0.31, green: 0.39, blue: 0.49)
            shadow = Color.black.opacity(0.08)
        }
    }
}

@main
struct ComputerBarWidgets: WidgetBundle {
    var body: some Widget {
        ComputerBarStatusWidget()
    }
}
