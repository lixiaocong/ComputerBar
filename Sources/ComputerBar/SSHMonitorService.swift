import Foundation
import Darwin

struct NodeFetchResult {
    let alias: String
    let status: NodeStatus?
    let errorMessage: String?
}

enum SSHMonitorParseError: LocalizedError {
    case missingField(String)
    case invalidField(String)

    var errorDescription: String? {
        switch self {
        case let .missingField(field):
            return "Missing field in SSH monitor output: \(field)"
        case let .invalidField(field):
            return "Invalid field in SSH monitor output: \(field)"
        }
    }
}

actor SSHMonitorService {
    func fetchStatuses(for hosts: [SSHHost]) async -> [NodeFetchResult] {
        await withTaskGroup(of: NodeFetchResult.self, returning: [NodeFetchResult].self) { group in
            for host in hosts {
                group.addTask {
                    await Self.fetchStatus(for: host)
                }
            }

            var results: [NodeFetchResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    private static func fetchStatus(for host: SSHHost) async -> NodeFetchResult {
        if host.isLocal {
            do {
                let status = try await fetchLocalStatus(for: host)
                return NodeFetchResult(alias: host.alias, status: status, errorMessage: nil)
            } catch {
                return NodeFetchResult(alias: host.alias, status: nil, errorMessage: error.localizedDescription)
            }
        }

        do {
            let result = try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
                arguments: [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=4",
                    "-o", "ServerAliveInterval=4",
                    "-o", "ServerAliveCountMax=1",
                    host.alias,
                    "sh",
                    "-s"
                ],
                standardInput: remoteScript,
                timeout: 10
            )

            guard result.exitCode == 0 else {
                return NodeFetchResult(
                    alias: host.alias,
                    status: nil,
                    errorMessage: sanitizedErrorMessage(
                        result.stderr,
                        fallback: "SSH exited with code \(result.exitCode)."
                    )
                )
            }

            let status = try parseStatusOutput(result.stdout, host: host, collectedAt: Date())
            return NodeFetchResult(alias: host.alias, status: status, errorMessage: nil)
        } catch {
            return NodeFetchResult(alias: host.alias, status: nil, errorMessage: error.localizedDescription)
        }
    }

    private static func fetchLocalStatus(for host: SSHHost) async throws -> NodeStatus {
        let firstCPUTicks = try readLocalCPUTicks()
        try await Task.sleep(for: .milliseconds(200))
        let secondCPUTicks = try readLocalCPUTicks()

        let cpuUsagePercent = localCPUUsagePercent(
            firstSample: firstCPUTicks,
            secondSample: secondCPUTicks
        )
        let memory = try readLocalMemoryUsage()
        let disk = try readLocalDiskUsage()
        let loadAverages = readLocalLoadAverages()

        return NodeStatus(
            host: host,
            cpuUsagePercent: cpuUsagePercent,
            memoryUsagePercent: memory.usagePercent,
            memoryUsedBytes: memory.usedBytes,
            memoryTotalBytes: memory.totalBytes,
            virtualMemoryUsagePercent: nil,
            virtualMemoryUsedBytes: nil,
            virtualMemoryTotalBytes: nil,
            diskUsagePercent: disk.usagePercent,
            diskUsedBytes: disk.usedBytes,
            diskTotalBytes: disk.totalBytes,
            loadAverages: loadAverages,
            uptimeSeconds: ProcessInfo.processInfo.systemUptime,
            collectedAt: Date()
        )
    }

    static func parseStatusOutput(_ output: String, host: SSHHost, collectedAt: Date) throws -> NodeStatus {
        var values: [String: String] = [:]

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let parts = rawLine.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            values[parts[0]] = parts[1]
        }

        guard let cpuUsagePercent = values["cpu_percent"].flatMap(Double.init) else {
            throw values["cpu_percent"] == nil ? SSHMonitorParseError.missingField("cpu_percent") : SSHMonitorParseError.invalidField("cpu_percent")
        }
        guard let totalKilobytes = values["mem_total_kb"].flatMap(UInt64.init) else {
            throw values["mem_total_kb"] == nil ? SSHMonitorParseError.missingField("mem_total_kb") : SSHMonitorParseError.invalidField("mem_total_kb")
        }
        guard let availableKilobytes = values["mem_available_kb"].flatMap(UInt64.init) else {
            throw values["mem_available_kb"] == nil ? SSHMonitorParseError.missingField("mem_available_kb") : SSHMonitorParseError.invalidField("mem_available_kb")
        }
        guard let diskTotalKilobytes = values["disk_total_kb"].flatMap(UInt64.init) else {
            throw values["disk_total_kb"] == nil ? SSHMonitorParseError.missingField("disk_total_kb") : SSHMonitorParseError.invalidField("disk_total_kb")
        }
        guard let diskUsedKilobytes = values["disk_used_kb"].flatMap(UInt64.init) else {
            throw values["disk_used_kb"] == nil ? SSHMonitorParseError.missingField("disk_used_kb") : SSHMonitorParseError.invalidField("disk_used_kb")
        }
        guard let uptimeSeconds = values["uptime_seconds"].flatMap(Double.init) else {
            throw values["uptime_seconds"] == nil ? SSHMonitorParseError.missingField("uptime_seconds") : SSHMonitorParseError.invalidField("uptime_seconds")
        }
        let swap = try parseOptionalSwapUsage(from: values)

        let totalBytes = totalKilobytes * 1_024
        let availableBytes = min(availableKilobytes * 1_024, totalBytes)
        let usedBytes = totalBytes >= availableBytes ? totalBytes - availableBytes : 0
        let memoryUsagePercent = totalBytes == 0 ? 0 : (Double(usedBytes) / Double(totalBytes)) * 100
        let diskTotalBytes = diskTotalKilobytes * 1_024
        let diskUsedBytes = min(diskUsedKilobytes * 1_024, diskTotalBytes)
        let diskUsagePercent = diskTotalBytes == 0 ? 0 : (Double(diskUsedBytes) / Double(diskTotalBytes)) * 100

        var loadAverages = (values["loadavg"] ?? "")
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Double($0) }
        while loadAverages.count < 3 {
            loadAverages.append(0)
        }

        return NodeStatus(
            host: host,
            cpuUsagePercent: clamp(cpuUsagePercent),
            memoryUsagePercent: clamp(memoryUsagePercent),
            memoryUsedBytes: usedBytes,
            memoryTotalBytes: totalBytes,
            virtualMemoryUsagePercent: swap?.usagePercent,
            virtualMemoryUsedBytes: swap?.usedBytes,
            virtualMemoryTotalBytes: swap?.totalBytes,
            diskUsagePercent: clamp(diskUsagePercent),
            diskUsedBytes: diskUsedBytes,
            diskTotalBytes: diskTotalBytes,
            loadAverages: Array(loadAverages.prefix(3)),
            uptimeSeconds: uptimeSeconds,
            collectedAt: collectedAt
        )
    }

    private static func parseOptionalSwapUsage(
        from values: [String: String]
    ) throws -> (usedBytes: UInt64, totalBytes: UInt64, usagePercent: Double)? {
        guard let rawTotal = values["swap_total_kb"],
              let rawFree = values["swap_free_kb"] else {
            return nil
        }

        guard let totalKilobytes = UInt64(rawTotal) else {
            throw SSHMonitorParseError.invalidField("swap_total_kb")
        }
        guard let freeKilobytes = UInt64(rawFree) else {
            throw SSHMonitorParseError.invalidField("swap_free_kb")
        }
        guard totalKilobytes > 0 else {
            return nil
        }

        let totalBytes = totalKilobytes * 1_024
        let freeBytes = min(freeKilobytes * 1_024, totalBytes)
        let usedBytes = totalBytes >= freeBytes ? totalBytes - freeBytes : 0
        let usagePercent = totalBytes == 0 ? 0 : (Double(usedBytes) / Double(totalBytes)) * 100
        return (usedBytes, totalBytes, clamp(usagePercent))
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }

    private static func readLocalCPUTicks() throws -> [UInt64] {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &cpuInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            throw SSHMonitorParseError.invalidField("local_cpu")
        }

        return [
            UInt64(cpuInfo.cpu_ticks.0),
            UInt64(cpuInfo.cpu_ticks.1),
            UInt64(cpuInfo.cpu_ticks.2),
            UInt64(cpuInfo.cpu_ticks.3)
        ]
    }

    private static func localCPUUsagePercent(firstSample: [UInt64], secondSample: [UInt64]) -> Double {
        guard firstSample.count == secondSample.count else {
            return 0
        }

        let deltas = zip(firstSample, secondSample).map { max(Int64($1) - Int64($0), 0) }
        let total = deltas.reduce(0, +)
        let idle = deltas[safe: CPU_STATE_IDLE] ?? 0

        guard total > 0 else {
            return 0
        }

        return clamp((Double(total - idle) / Double(total)) * 100)
    }

    private static func readLocalMemoryUsage() throws -> (
        usedBytes: UInt64,
        totalBytes: UInt64,
        usagePercent: Double
    ) {
        var totalBytes = UInt64.zero
        var totalLength = MemoryLayout<UInt64>.size
        let totalResult = withUnsafeMutableBytes(of: &totalBytes) { bytes in
            sysctlbyname("hw.memsize", bytes.baseAddress, &totalLength, nil, 0)
        }

        guard totalResult == 0 else {
            throw SSHMonitorParseError.invalidField("local_memsize")
        }

        var pageSize = vm_size_t.zero
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else {
            throw SSHMonitorParseError.invalidField("local_page_size")
        }

        var vmStats = vm_statistics64()
        var vmStatsCount = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let statsResult = withUnsafeMutablePointer(to: &vmStats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmStatsCount)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &vmStatsCount)
            }
        }

        guard statsResult == KERN_SUCCESS else {
            throw SSHMonitorParseError.invalidField("local_vm_stats")
        }

        // Approximate Activity Monitor's "Memory Used" by counting anonymous app
        // pages, wired pages, and compressed pages. This excludes file-backed
        // cached pages and does not fold swap usage into the RAM number.
        let anonymousPages = max(Int64(vmStats.internal_page_count) - Int64(vmStats.purgeable_count), 0)
        let usedPages = UInt64(anonymousPages)
            + UInt64(vmStats.wire_count)
            + UInt64(vmStats.compressor_page_count)
        let usedBytes = min(usedPages * UInt64(pageSize), totalBytes)
        let usagePercent = totalBytes == 0 ? 0 : (Double(usedBytes) / Double(totalBytes)) * 100

        return (usedBytes, totalBytes, clamp(usagePercent))
    }

    private static func readLocalDiskUsage() throws -> (
        usedBytes: UInt64,
        totalBytes: UInt64,
        usagePercent: Double
    ) {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: "/")

        guard let totalBytes = (attributes[.systemSize] as? NSNumber)?.uint64Value else {
            throw SSHMonitorParseError.invalidField("local_disk_total")
        }
        guard let freeBytes = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value else {
            throw SSHMonitorParseError.invalidField("local_disk_free")
        }

        let normalizedFreeBytes = min(freeBytes, totalBytes)
        let usedBytes = totalBytes > normalizedFreeBytes ? totalBytes - normalizedFreeBytes : 0
        let usagePercent = totalBytes == 0 ? 0 : (Double(usedBytes) / Double(totalBytes)) * 100

        return (usedBytes, totalBytes, clamp(usagePercent))
    }

    private static func readLocalLoadAverages() -> [Double] {
        var buffer = [Double](repeating: 0, count: 3)
        let result = getloadavg(&buffer, Int32(buffer.count))
        guard result >= 0 else {
            return [0, 0, 0]
        }

        let sampleCount = min(max(Int(result), 0), buffer.count)
        if sampleCount < buffer.count {
            for index in sampleCount ..< buffer.count {
                buffer[index] = 0
            }
        }

        return buffer
    }

    private static func sanitizedErrorMessage(_ message: String, fallback: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static let remoteScript = """
    set -eu

    cpu_a="$(grep '^cpu ' /proc/stat)"
    sleep 0.2
    cpu_b="$(grep '^cpu ' /proc/stat)"

    mem_total_kb="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo)"
    mem_available_kb="$(awk '/^MemAvailable:/ { print $2; exit }' /proc/meminfo || true)"
    swap_total_kb="$(awk '/^SwapTotal:/ { print $2; exit }' /proc/meminfo || true)"
    swap_free_kb="$(awk '/^SwapFree:/ { print $2; exit }' /proc/meminfo || true)"
    disk_total_kb="$(df -kP / | awk 'NR == 2 { print $2; exit }')"
    disk_used_kb="$(df -kP / | awk 'NR == 2 { print $3; exit }')"

    if [ -z "${mem_available_kb:-}" ]; then
      mem_available_kb="$(awk '
        /^MemFree:/ { free = $2 }
        /^Buffers:/ { buffers = $2 }
        /^Cached:/ { cached = $2 }
        END { print free + buffers + cached }
      ' /proc/meminfo)"
    fi
    swap_total_kb="${swap_total_kb:-0}"
    swap_free_kb="${swap_free_kb:-0}"

    loadavg="$(cut -d ' ' -f 1-3 /proc/loadavg)"
    uptime_seconds="$(cut -d ' ' -f 1 /proc/uptime)"

    cpu_percent="$(
      awk -v first="$cpu_a" -v second="$cpu_b" '
      BEGIN {
          count_a = split(first, a)
          count_b = split(second, b)
          total_a = 0
          total_b = 0
          for (i = 2; i <= count_a; i++) {
              total_a += a[i]
          }
          for (i = 2; i <= count_b; i++) {
              total_b += b[i]
          }
          idle_a = a[5] + a[6]
          idle_b = b[5] + b[6]
          delta_total = total_b - total_a
          delta_idle = idle_b - idle_a
          if (delta_total <= 0) {
              print "0.00"
          } else {
              printf "%.2f", ((delta_total - delta_idle) / delta_total) * 100
          }
      }'
    )"

    printf 'cpu_percent=%s\n' "$cpu_percent"
    printf 'mem_total_kb=%s\n' "$mem_total_kb"
    printf 'mem_available_kb=%s\n' "$mem_available_kb"
    printf 'swap_total_kb=%s\n' "$swap_total_kb"
    printf 'swap_free_kb=%s\n' "$swap_free_kb"
    printf 'disk_total_kb=%s\n' "$disk_total_kb"
    printf 'disk_used_kb=%s\n' "$disk_used_kb"
    printf 'loadavg=%s\n' "$loadavg"
    printf 'uptime_seconds=%s\n' "$uptime_seconds"
    """
}

private extension Array where Element == Int64 {
    subscript(safe index: Int32) -> Int64? {
        let normalizedIndex = Int(index)
        guard indices.contains(normalizedIndex) else {
            return nil
        }

        return self[normalizedIndex]
    }
}
