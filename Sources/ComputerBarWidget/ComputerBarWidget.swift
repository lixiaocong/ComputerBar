import AppIntents
import SwiftUI
import WidgetKit
#if canImport(ComputerBarShared)
import ComputerBarShared
#endif

// MARK: - Widget Configuration

struct ComputerBarWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let selectedAlias: String?
}

private enum ComputerBarWidgetHostID {
    static let local = "local"
    private static let localAliases = Set(["__local__computerbar__", "__local__sshbar__"])

    static func widgetValue(for host: WidgetHostSnapshot) -> String {
        localAliases.contains(host.alias) ? host.widgetTitle : host.alias
    }

    static func snapshotAlias(for widgetValue: String, in snapshot: WidgetSnapshot?) -> String? {
        let trimmedValue = widgetValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        if trimmedValue == local || localAliases.contains(trimmedValue) {
            return snapshot?.selectedHosts.first { localAliases.contains($0.alias) }?.alias
        }

        if let host = snapshot?.selectedHosts.first(where: { host in
            host.alias == trimmedValue || host.widgetTitle == trimmedValue
        }) {
            return host.alias
        }

        return trimmedValue
    }
}

struct ComputerBarHostOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        WidgetSnapshotStore.loadIfAvailable()?.selectedHosts.map {
            ComputerBarWidgetHostID.widgetValue(for: $0)
        } ?? []
    }
}

struct ComputerBarWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Computer Bar"
    static let description = IntentDescription("Shows one monitored computer on the desktop.")

    @Parameter(
        title: "Host",
        description: "The ComputerBar host to show in this widget.",
        optionsProvider: ComputerBarHostOptionsProvider()
    )
    var hostID: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$hostID)")
    }
}

// MARK: - Timeline Provider

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
            selectedAlias: resolvedAlias(from: configuration, snapshot: snapshot)
        )
    }

    func timeline(
        for configuration: ComputerBarWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<ComputerBarWidgetEntry> {
        let snapshot = loadSnapshot()
        let resolved = resolvedAlias(from: configuration, snapshot: snapshot)

        let entry = ComputerBarWidgetEntry(
            date: .now,
            snapshot: snapshot,
            selectedAlias: resolved
        )
        let nextReload = Date().addingTimeInterval(
            snapshot == nil ? Self.missingSnapshotRetryInterval : Self.normalRefreshInterval
        )
        return Timeline(entries: [entry], policy: .after(nextReload))
    }

    /// Resolves the selected host from this widget instance's edit configuration.
    private func resolvedAlias(from configuration: ComputerBarWidgetConfigurationIntent, snapshot: WidgetSnapshot?) -> String? {
        if let configuredAlias = resolvedConfiguredAlias(from: configuration, snapshot: snapshot),
           snapshot?.selectedHosts.contains(where: { $0.alias == configuredAlias }) == true {
            return configuredAlias
        }

        return snapshot?.primaryAlias ?? snapshot?.selectedHosts.first?.alias
    }

    private func resolvedConfiguredAlias(
        from configuration: ComputerBarWidgetConfigurationIntent,
        snapshot: WidgetSnapshot?
    ) -> String? {
        guard let intentID = configuration.hostID else {
            return nil
        }

        return ComputerBarWidgetHostID.snapshotAlias(for: intentID, in: snapshot)
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
                    virtualMemoryUsagePercent: 25,
                    virtualMemoryUsedBytes: 1_073_741_824,
                    virtualMemoryTotalBytes: 4_294_967_296,
                    diskUsagePercent: 72,
                    diskUsedBytes: 193_273_528_320,
                    diskTotalBytes: 268_435_456_000,
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
                    diskUsagePercent: 35,
                    diskUsedBytes: 96_636_764_160,
                    diskTotalBytes: 274_877_906_944,
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
        WidgetSnapshotStore.loadIfAvailable()
    }
}

// MARK: - Widget Definition

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

struct LegacyComputerBarStatusWidget: Widget {
    let kind = ComputerBarWidgetConstants.legacyStatusWidgetKind

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

// MARK: - Widget View

struct ComputerBarWidgetEntryView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: ComputerBarWidgetEntry

    var body: some View {
        let accent = entry.snapshot.flatMap { selectedHost(in: $0) }.map(hostAccent(for:)) ?? palette.accent

        ZStack {
            widgetBackground(accent: accent)

            VStack(alignment: .leading, spacing: 0) {
                if let snapshot = entry.snapshot {
                    content(snapshot)
                } else {
                    emptyState(
                        title: "No Snapshot Yet",
                        message: "Open Computer Bar once so it can populate widget data."
                    )
                }
            }
        }
        .foregroundStyle(palette.primaryText)
        .containerBackground(for: .widget) {
            widgetBackground(accent: accent)
        }
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        if let configErrorMessage = snapshot.configErrorMessage {
            emptyState(title: "SSH Config Problem", message: configErrorMessage)
        } else if let host = selectedHost(in: snapshot) {
            mediumHostView(host, snapshot: snapshot)
        } else {
            emptyState(
                title: "No Host Selected",
                message: "Edit this widget and choose a ComputerBar host."
            )
        }
    }

    private func mediumHostView(_ host: WidgetHostSnapshot, snapshot: WidgetSnapshot) -> some View {
        let accent = hostAccent(for: host)

        return VStack(alignment: .leading, spacing: 8) {
            summaryHeader(host: host, accent: accent)

            if let errorMessage = host.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                metricRows(for: host)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func metricRows(for host: WidgetHostSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            metricRow(
                title: "CPU Usage",
                value: host.cpuUsagePercent,
                percentText: host.cpuUsageText,
                detail: cpuDetail(for: host)
            )

            metricRow(
                title: "Memory Usage",
                value: host.memoryUsagePercent,
                percentText: host.memoryUsageText,
                detail: host.memoryUsageSummary
            )

            if host.hasVirtualMemoryUsage {
                metricRow(
                    title: "Virtual Memory",
                    value: host.virtualMemoryUsagePercent,
                    percentText: host.virtualMemoryUsageText,
                    detail: host.virtualMemoryUsageSummary
                )
            }

            metricRow(
                title: "Disk Usage",
                value: host.diskUsagePercent,
                percentText: host.diskUsageText,
                detail: host.diskUsageSummary
            )
        }
    }

    private func metricRow(
        title: String,
        value: Double?,
        percentText: String,
        detail: String
    ) -> some View {
        let tint = usageTint(for: value)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if detail != "--" {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 4)

                Text(percentText)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }

            usageBar(value: value, tint: tint)
        }
    }

    private func usageBar(value: Double?, tint: Color) -> some View {
        let progress = min(max(value ?? 0, 0), 100) / 100

        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.track)

                Capsule()
                    .fill(tint)
                    .frame(width: max(3, proxy.size.width * progress))
            }
        }
        .frame(height: 5)
    }

    private func metricCard(title: String, value: Double?, text: String) -> some View {
        let tint = usageTint(for: value)

        return VStack(alignment: .leading, spacing: 6) {
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

    private func usageTint(for percent: Double?) -> Color {
        guard let percent else { return .green }

        switch percent {
        case 95...:
            return .red
        case 80...:
            return .orange
        default:
            return .green
        }
    }

    private func summaryHeader(host: WidgetHostSnapshot, accent: Color) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(host.widgetTitle)
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(host.endpointDescription)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: -1) {
                Text(host.cpuUsageText)
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(usageTint(for: host.cpuUsagePercent))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("cpu")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func detailBlock(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(palette.pillBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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

    private func hostAccent(for host: WidgetHostSnapshot) -> Color {
        isLocalHost(host)
            ? Color(red: 0.02, green: 0.64, blue: 0.70)
            : Color(red: 0.05, green: 0.42, blue: 0.92)
    }

    private func cpuDetail(for host: WidgetHostSnapshot) -> String {
        isLocalHost(host) ? "Sampled from macOS host statistics" : "Sampled from /proc/stat"
    }

    private func isLocalHost(_ host: WidgetHostSnapshot) -> Bool {
        host.alias.hasPrefix("__local__") || host.widgetTitle == "This Mac"
    }

    private func widgetBackground(accent: Color) -> some View {
        ZStack {
            LinearGradient(
                colors: [palette.backgroundTop, palette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    accent.opacity(colorScheme == .dark ? 0.20 : 0.12),
                    accent.opacity(colorScheme == .dark ? 0.08 : 0.04)
                ],
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
    let pillBackground: Color
    let primaryText: Color
    let secondaryText: Color
    let track: Color
    let accent: Color

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            backgroundTop = Color(red: 0.16, green: 0.18, blue: 0.22)
            backgroundBottom = Color(red: 0.21, green: 0.24, blue: 0.29)
            pillBackground = Color.white.opacity(0.12)
            primaryText = Color.white.opacity(0.98)
            secondaryText = Color.white.opacity(0.78)
            track = Color.white.opacity(0.22)
            accent = Color(red: 0.38, green: 0.72, blue: 1.0)
        } else {
            backgroundTop = Color(red: 0.985, green: 0.988, blue: 0.995)
            backgroundBottom = Color(red: 0.945, green: 0.956, blue: 0.976)
            pillBackground = Color.white.opacity(0.92)
            primaryText = Color(red: 0.10, green: 0.16, blue: 0.23)
            secondaryText = Color(red: 0.31, green: 0.39, blue: 0.49)
            track = Color.black.opacity(0.16)
            accent = Color(red: 0.05, green: 0.42, blue: 0.92)
        }
    }
}

@main
struct ComputerBarWidgets: WidgetBundle {
    var body: some Widget {
        ComputerBarStatusWidget()
        LegacyComputerBarStatusWidget()
    }
}
