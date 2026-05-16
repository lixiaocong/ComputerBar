import Foundation

enum SSHHostKind: String, Codable, Hashable {
    case remote
    case local
}

struct SSHHost: Codable, Hashable, Identifiable {
    let alias: String
    let hostName: String
    let user: String?
    let port: Int?
    let kind: SSHHostKind

    init(
        alias: String,
        hostName: String,
        user: String?,
        port: Int?,
        kind: SSHHostKind = .remote
    ) {
        self.alias = alias
        self.hostName = hostName
        self.user = user
        self.port = port
        self.kind = kind
    }

    var id: String { alias }

    var isLocal: Bool {
        kind == .local
    }

    var displayName: String {
        isLocal ? "This Mac" : alias
    }

    var endpointDescription: String {
        let userPrefix = user.map { "\($0)@" } ?? ""
        let portSuffix = port.map { ":\($0)" } ?? ""
        return "\(userPrefix)\(hostName)\(portSuffix)"
    }
}

struct NodeStatus: Equatable, Identifiable {
    let host: SSHHost
    let cpuUsagePercent: Double
    let memoryUsagePercent: Double
    let memoryUsedBytes: UInt64
    let memoryTotalBytes: UInt64
    let diskUsagePercent: Double
    let diskUsedBytes: UInt64
    let diskTotalBytes: UInt64
    let loadAverages: [Double]
    let uptimeSeconds: TimeInterval
    let collectedAt: Date

    var id: String { host.id }

    var cpuUsageText: String {
        "\(Int(cpuUsagePercent.rounded()))%"
    }

    var memoryUsageText: String {
        "\(Int(memoryUsagePercent.rounded()))%"
    }

    var memoryUsageSummary: String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(memoryUsedBytes), countStyle: .binary)) / \(ByteCountFormatter.string(fromByteCount: Int64(memoryTotalBytes), countStyle: .binary))"
    }

    var diskUsageText: String {
        "\(Int(diskUsagePercent.rounded()))%"
    }

    var diskUsageSummary: String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(diskUsedBytes), countStyle: .binary)) / \(ByteCountFormatter.string(fromByteCount: Int64(diskTotalBytes), countStyle: .binary))"
    }

    var loadAverageText: String {
        loadAverages.map { String(format: "%.2f", $0) }
            .joined(separator: "  ")
    }

    var uptimeText: String {
        uptimeSeconds.compactDurationString
    }

    var updatedAtText: String {
        collectedAt.formatted(date: .omitted, time: .standard)
    }
}

struct NodeStatusState: Equatable {
    var isLoading = false
    var status: NodeStatus?
    var errorMessage: String?

    static let idle = NodeStatusState()
}

enum MenuBarSeverity {
    case idle
    case normal
    case warning
    case critical
    case error
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
