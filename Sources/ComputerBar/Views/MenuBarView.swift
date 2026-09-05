import SwiftUI

struct MenuBarView: View {
    let model: AppModel
    let openSettingsAction: () -> Void
    let quitAction: () -> Void
    let onPreferredSizeChange: @MainActor (CGSize) -> Void

    static let minimumContentSize = CGSize(width: 360, height: 220)
    private let hostColumnWidth: CGFloat = 252
    private let singleHostColumnWidth: CGFloat = 456

    init(
        model: AppModel,
        openSettingsAction: @escaping () -> Void = {},
        quitAction: @escaping () -> Void = {},
        onPreferredSizeChange: @escaping @MainActor (CGSize) -> Void = { _ in }
    ) {
        self.model = model
        self.openSettingsAction = openSettingsAction
        self.quitAction = quitAction
        self.onPreferredSizeChange = onPreferredSizeChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView([.horizontal, .vertical]) {
                content
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(12)
            }

            Divider()

            controls
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .background(contentSizeReader)
        .frame(
            minWidth: Self.minimumContentSize.width,
            minHeight: Self.minimumContentSize.height,
            alignment: .topLeading
        )
        .onPreferenceChange(MenuBarContentSizePreferenceKey.self) { size in
            let preferredSize = CGSize(
                width: max(Self.minimumContentSize.width, size.width),
                height: max(Self.minimumContentSize.height, size.height)
            )
            onPreferredSizeChange(preferredSize)
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let configErrorMessage = model.configErrorMessage {
                messageBlock(
                    eyebrow: "CONFIG",
                    title: "SSH Config Problem",
                    message: configErrorMessage,
                    tint: .orange
                )
            } else if model.selectedHosts.isEmpty {
                messageBlock(
                    eyebrow: "SETUP",
                    title: "No Hosts Selected",
                    message: "Choose one or more local or SSH hosts in Settings to monitor them here.",
                    tint: .secondary
                )
            }

            if !model.windowHosts.isEmpty {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(model.windowHosts) { host in
                        hostColumn(for: host)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func hostColumn(for host: SSHHost) -> some View {
        let state = model.statusState(for: host)
        let accent = accentColor(for: host)
        let columnWidth = model.windowHosts.count == 1 ? singleHostColumnWidth : hostColumnWidth

        VStack(alignment: .leading, spacing: 10) {
            hostColumnHeader(host, state: state, tint: accent)
            hostStatusCard(host, state: state, tint: accent)
        }
        .frame(width: columnWidth, alignment: .topLeading)
    }

    private func hostColumnHeader(
        _ host: SSHHost,
        state: NodeStatusState,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headerEyebrow(for: host))
                    .font(.system(.caption2, design: .rounded).weight(.black))
                    .tracking(1)
                    .foregroundStyle(tint)

                Text(host.displayName)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .lineLimit(1)

                Text(headerSubtitle(for: host))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(headerMetricValue(for: state))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text(headerMetricLabel(for: state))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func hostStatusCard(
        _ host: SSHHost,
        state: NodeStatusState,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(host.endpointDescription)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let status = state.status {
                metricBlock(
                    title: "CPU Usage",
                    percentText: status.cpuUsageText,
                    value: status.cpuUsagePercent,
                    detail: host.isLocal ? "Sampled from macOS host statistics" : "Sampled from /proc/stat",
                    tint: usageTint(for: status.cpuUsagePercent)
                )

                metricBlock(
                    title: "Memory Usage",
                    percentText: status.memoryUsageText,
                    value: status.memoryUsagePercent,
                    detail: status.memoryUsageSummary,
                    tint: usageTint(for: status.memoryUsagePercent)
                )

                if status.hasVirtualMemoryUsage {
                    metricBlock(
                        title: "Virtual Memory Usage",
                        percentText: status.virtualMemoryUsageText,
                        value: status.virtualMemoryUsagePercent ?? 0,
                        detail: status.virtualMemoryUsageSummary,
                        tint: usageTint(for: status.virtualMemoryUsagePercent ?? 0)
                    )
                }

                metricBlock(
                    title: "Disk Usage",
                    percentText: status.diskUsageText,
                    value: status.diskUsagePercent,
                    detail: status.diskUsageSummary,
                    tint: usageTint(for: status.diskUsagePercent)
                )

                detailRow(label: "Load Avg", value: status.loadAverageText)
                detailRow(label: "Uptime", value: status.uptimeText)
                detailRow(label: "Updated", value: status.updatedAtText)
            } else if let errorMessage = state.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                placeholderMetricBlock(title: "CPU Usage")
                placeholderMetricBlock(title: "Memory Usage")
                placeholderMetricBlock(title: "Disk Usage")
                detailRow(label: "Load Avg", value: "--")
                detailRow(label: "Uptime", value: "--")
                detailRow(label: "Updated", value: state.isLoading ? "Refreshing…" : "--")
            }

            if let errorMessage = state.errorMessage, state.status != nil {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        }
    }

    private func metricBlock(
        title: String,
        percentText: String,
        value: Double,
        detail: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            ProgressView(value: value, total: 100)
                .tint(tint)

            HStack {
                Text(detail)
                Spacer()
                Text(percentText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func placeholderMetricBlock(title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            Capsule()
                .fill(Color.secondary.opacity(0.16))
                .frame(height: 6)

            HStack {
                Text("No data yet")
                Spacer()
                Text("--")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func messageBlock(
        eyebrow: String,
        title: String,
        message: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.system(.caption2, design: .rounded).weight(.black))
                .tracking(1)
                .foregroundStyle(tint)

            Text(title)
                .font(.system(.title3, design: .rounded).weight(.heavy))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: 460, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }

    private func accentColor(for host: SSHHost) -> Color {
        if host.isLocal {
            return .teal
        }

        switch model.selectionIndex(for: host) ?? 0 {
        case 1:
            return .blue
        case 2:
            return .green
        case 3:
            return .orange
        case 4:
            return .brown
        default:
            return .teal
        }
    }

    private func usageTint(for percent: Double) -> Color {
        switch percent {
        case 95...:
            return .red
        case 80...:
            return .orange
        default:
            return .green
        }
    }

    private func headerEyebrow(for host: SSHHost) -> String {
        if model.isHostShownInMenuBar(host) {
            return "MENU BAR"
        }

        if host.isLocal {
            return "LOCAL"
        }

        if let selectionIndex = model.selectionIndex(for: host) {
            return "HOST \(selectionIndex)"
        }

        return "HOST"
    }

    private func headerSubtitle(for host: SSHHost) -> String {
        if host.isLocal {
            return "this Mac"
        }

        return host.endpointDescription
    }

    private func headerMetricValue(for state: NodeStatusState) -> String {
        if let status = state.status {
            return status.cpuUsageText
        }

        if state.errorMessage != nil {
            return "!"
        }

        return state.isLoading ? "..." : "--"
    }

    private func headerMetricLabel(for state: NodeStatusState) -> String {
        if state.status != nil {
            return "cpu"
        }

        if state.errorMessage != nil {
            return "error"
        }

        return state.isLoading ? "loading" : "idle"
    }

    private var controls: some View {
        HStack(spacing: 10) {

            Button("Settings…") {
                openSettingsAction()
            }

            Spacer(minLength: 0)

            if let lastRefreshAt = model.lastRefreshAt {
                Text(lastRefreshAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Button("Quit") {
                quitAction()
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private var contentSizeReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: MenuBarContentSizePreferenceKey.self, value: proxy.size)
        }
    }
}

private struct MenuBarContentSizePreferenceKey: PreferenceKey {
    static let defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}
