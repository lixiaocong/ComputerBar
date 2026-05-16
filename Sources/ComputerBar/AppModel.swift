import Foundation
import Observation
#if canImport(ComputerBarShared)
import ComputerBarShared
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    static let defaultRefreshIntervalSeconds = 1
    static let minimumRefreshIntervalSeconds = 1
    static let maximumRefreshIntervalSeconds = 60
    static let defaultMenuBarMaxDisplayedHosts = 2
    static let minimumMenuBarMaxDisplayedHosts = 1
    static let maximumMenuBarMaxDisplayedHosts = 3

    private static let refreshIntervalDefaultsKey = "refreshIntervalSeconds"
    private static let selectedAliasesDefaultsKey = "selectedAliases"
    private static let menuBarSelectedAliasesDefaultsKey = "menuBarSelectedAliases"
    private static let menuBarMaxDisplayedHostsDefaultsKey = "menuBarMaxDisplayedHosts"
    private static let legacyMenuBarAliasDefaultsKey = "menuBarAlias"
    private static let localHostAlias = "__local__computerbar__"
    private static let legacyBundleIdentifier = "com.sshbar.app"
    private static let legacyDefaultsMigrationKey = "migratedLegacySSHBarDefaults"
    private static let legacyLocalHostAlias = "__local__sshbar__"

    private let userDefaults: UserDefaults
    private let configService: SSHConfigService
    private let monitorService: SSHMonitorService
    private let localSnapshotServer: LocalSnapshotServer

    private var refreshTask: Task<Void, Never>?
    private var needsRefreshAfterCurrentRun = false
    private var statusStatesByAlias: [String: NodeStatusState] = [:]

    var detectedHosts: [SSHHost] = []
    var configErrorMessage: String?
    var lastHostReloadAt: Date?
    var lastRefreshAt: Date?
    var isRefreshing = false
    private var isMenuBarHostSelectionExplicit = false
    var menuBarMaxDisplayedHosts: Int {
        didSet {
            let normalized = Self.normalizeMenuBarMaxDisplayedHosts(menuBarMaxDisplayedHosts)
            if menuBarMaxDisplayedHosts != normalized {
                menuBarMaxDisplayedHosts = normalized
                return
            }

            guard oldValue != menuBarMaxDisplayedHosts else { return }
            userDefaults.set(menuBarMaxDisplayedHosts, forKey: Self.menuBarMaxDisplayedHostsDefaultsKey)
            trimMenuBarSelectedAliasesToDisplayLimit()
            publishWidgetSnapshot()
        }
    }
    var menuBarSelectedAliases: [String] = [] {
        didSet {
            guard oldValue != menuBarSelectedAliases else { return }
            persistMenuBarHostSelection()
        }
    }

    var refreshIntervalSeconds: Int {
        didSet {
            let normalized = Self.normalizeRefreshInterval(refreshIntervalSeconds)
            if refreshIntervalSeconds != normalized {
                refreshIntervalSeconds = normalized
                return
            }

            guard oldValue != refreshIntervalSeconds else { return }
            userDefaults.set(refreshIntervalSeconds, forKey: Self.refreshIntervalDefaultsKey)
            startAutoRefresh()
        }
    }

    private(set) var selectedAliases: [String] {
        didSet {
            guard oldValue != selectedAliases else { return }
            userDefaults.set(selectedAliases, forKey: Self.selectedAliasesDefaultsKey)
        }
    }

    init(
        userDefaults: UserDefaults = .standard,
        configService: SSHConfigService = SSHConfigService(),
        monitorService: SSHMonitorService = SSHMonitorService(),
        localSnapshotServer: LocalSnapshotServer = .shared,
        startImmediately: Bool = true
    ) {
        self.userDefaults = userDefaults
        self.configService = configService
        self.monitorService = monitorService
        self.localSnapshotServer = localSnapshotServer
        Self.migrateLegacyDefaultsIfNeeded(into: userDefaults)
        refreshIntervalSeconds = Self.normalizeRefreshInterval(
            userDefaults.object(forKey: Self.refreshIntervalDefaultsKey) as? Int
        )
        menuBarMaxDisplayedHosts = Self.normalizeMenuBarMaxDisplayedHosts(
            userDefaults.object(forKey: Self.menuBarMaxDisplayedHostsDefaultsKey) as? Int
        )
        selectedAliases = userDefaults.stringArray(forKey: Self.selectedAliasesDefaultsKey) ?? []
        if let storedMenuBarSelectedAliases = userDefaults.stringArray(forKey: Self.menuBarSelectedAliasesDefaultsKey) {
            isMenuBarHostSelectionExplicit = true
            menuBarSelectedAliases = Self.uniqueAliases(storedMenuBarSelectedAliases)
        } else if let legacyMenuBarAlias = userDefaults.string(forKey: Self.legacyMenuBarAliasDefaultsKey) {
            isMenuBarHostSelectionExplicit = true
            menuBarSelectedAliases = [legacyMenuBarAlias]
        }
        self.localSnapshotServer.start()

        if startImmediately {
            Task {
                await reloadHostsTask(triggerRefresh: true)
            }
            startAutoRefresh()
        } else {
            publishWidgetSnapshot()
        }
    }

    var sshConfigPathDisplay: String {
        NSString(string: configService.configURL.path).abbreviatingWithTildeInPath
    }

    var localHost: SSHHost {
        SSHHost(
            alias: Self.localHostAlias,
            hostName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            user: NSUserName(),
            port: nil,
            kind: .local
        )
    }

    var availableHosts: [SSHHost] {
        [localHost] + detectedHosts
    }

    var selectedHosts: [SSHHost] {
        selectedAliases.compactMap { alias in
            availableHosts.first { $0.alias == alias }
        }
    }

    var windowHosts: [SSHHost] {
        selectedHosts
    }

    var primaryHost: SSHHost? {
        menuBarHosts.first
    }

    var menuBarAccessibilityTitle: String {
        let hosts = menuBarHosts
        guard !hosts.isEmpty else {
            if let configErrorMessage {
                return configErrorMessage
            }
            if selectedHosts.isEmpty {
                return "No monitored hosts selected."
            }
            return "No menu bar hosts selected."
        }

        return hosts.map(menuBarAccessibilitySegment(for:)).joined(separator: "; ")
    }

    var menuBarHosts: [SSHHost] {
        let hostsByAlias = Dictionary(uniqueKeysWithValues: selectedHosts.map { ($0.alias, $0) })
        if isMenuBarHostSelectionExplicit {
            return Array(menuBarSelectedAliases.compactMap { hostsByAlias[$0] }.prefix(menuBarMaxDisplayedHosts))
        }

        return Array(selectedHosts.prefix(menuBarMaxDisplayedHosts))
    }

    var hasExplicitMenuBarHostSelection: Bool {
        isMenuBarHostSelectionExplicit
    }

    private func menuBarAccessibilitySegment(for host: SSHHost) -> String {
        let state = statusState(for: host)
        let title = host.displayName
        if let status = state.status {
            return "\(title): CPU \(status.cpuUsageText), memory \(status.memoryUsageText), disk \(status.diskUsageText), load average \(status.loadAverageText)."
        }
        if let errorMessage = state.errorMessage {
            return "\(title): \(errorMessage)"
        }
        return "\(title): waiting for first refresh."
    }

    var menuBarSeverity: MenuBarSeverity {
        let hosts = menuBarHosts
        guard !hosts.isEmpty else {
            return configErrorMessage == nil ? .idle : .error
        }

        let states = hosts.map(statusState(for:))
        if states.contains(where: { $0.errorMessage != nil && $0.status == nil }) {
            return .error
        }
        let statuses = states.compactMap(\.status)
        guard !statuses.isEmpty else { return .idle }

        let highestUsage = statuses
            .map { max($0.cpuUsagePercent, max($0.memoryUsagePercent, $0.diskUsagePercent)) }
            .max() ?? 0
        switch highestUsage {
        case 95...:
            return .critical
        case 80...:
            return .warning
        default:
            return .normal
        }
    }

    var menuBarStatusBars: [MenuBarStatusImage.Bar] {
        let hosts = menuBarHosts
        guard !hosts.isEmpty else {
            return [MenuBarStatusImage.Bar(label: "--", isError: configErrorMessage != nil)]
        }

        return hosts.map { host in
            let state = statusState(for: host)
            guard let status = state.status else {
                return MenuBarStatusImage.Bar(
                    label: menuBarLabel(for: host),
                    isError: state.errorMessage != nil
                )
            }

            return MenuBarStatusImage.Bar(
                label: menuBarLabel(for: host),
                cpuPercent: status.cpuUsagePercent,
                memoryPercent: status.memoryUsagePercent,
                diskPercent: status.diskUsagePercent
            )
        }
    }

    func reloadHosts() {
        Task {
            await reloadHostsTask(triggerRefresh: true)
        }
    }

    func refreshNow() {
        if isRefreshing {
            needsRefreshAfterCurrentRun = true
            return
        }

        let refreshHosts = hostsForRefresh()
        guard !refreshHosts.isEmpty else {
            lastRefreshAt = Date()
            publishWidgetSnapshot()
            return
        }

        isRefreshing = true
        for host in refreshHosts {
            var state = statusStatesByAlias[host.alias] ?? .idle
            state.isLoading = true
            statusStatesByAlias[host.alias] = state
        }

        Task { [monitorService] in
            let results = await monitorService.fetchStatuses(for: refreshHosts)
            await MainActor.run {
                for result in results {
                    var state = self.statusStatesByAlias[result.alias] ?? .idle
                    state.isLoading = false
                    if let status = result.status {
                        state.status = status
                        state.errorMessage = nil
                    } else {
                        state.errorMessage = result.errorMessage
                    }
                    self.statusStatesByAlias[result.alias] = state
                }

                self.lastRefreshAt = Date()
                self.isRefreshing = false
                self.publishWidgetSnapshot()

                if self.needsRefreshAfterCurrentRun {
                    self.needsRefreshAfterCurrentRun = false
                    self.refreshNow()
                }
            }
        }
    }

    func isHostSelected(_ host: SSHHost) -> Bool {
        selectedAliases.contains(host.alias)
    }

    func selectionIndex(for host: SSHHost) -> Int? {
        selectedAliases.firstIndex(of: host.alias).map { $0 + 1 }
    }

    func isHostShownInMenuBar(_ host: SSHHost) -> Bool {
        effectiveMenuBarSelectedAliases.contains(host.alias)
    }

    func setHost(_ host: SSHHost, selected: Bool) {
        var updatedAliases = selectedAliases
        if selected {
            if !updatedAliases.contains(host.alias) {
                updatedAliases.append(host.alias)
            }
        } else {
            updatedAliases.removeAll { $0 == host.alias }
        }

        applySelectedAliases(updatedAliases)
        refreshNow()
    }

    func setHost(_ host: SSHHost, shownInMenuBar: Bool) {
        if shownInMenuBar, !selectedAliases.contains(host.alias) {
            applySelectedAliases(selectedAliases + [host.alias])
        }

        var updatedAliases = effectiveMenuBarSelectedAliases.filter { $0 != host.alias }
        if shownInMenuBar {
            while updatedAliases.count >= menuBarMaxDisplayedHosts {
                updatedAliases.removeFirst()
            }
            updatedAliases.append(host.alias)
        }

        isMenuBarHostSelectionExplicit = true
        menuBarSelectedAliases = Self.normalizeMenuBarSelectedAliases(
            updatedAliases,
            selectedAliases: selectedAliases,
            limit: menuBarMaxDisplayedHosts
        )
        publishWidgetSnapshot()
        refreshNow()
    }

    func resetMenuBarHostSelection() {
        isMenuBarHostSelectionExplicit = false
        menuBarSelectedAliases = []
        userDefaults.removeObject(forKey: Self.menuBarSelectedAliasesDefaultsKey)
        publishWidgetSnapshot()
        refreshNow()
    }

    func moveHostToFront(_ host: SSHHost) {
        guard selectedAliases.contains(host.alias) else { return }
        var updatedAliases = selectedAliases.filter { $0 != host.alias }
        updatedAliases.insert(host.alias, at: 0)
        applySelectedAliases(updatedAliases)
    }

    func selectAllHosts() {
        applySelectedAliases(availableHosts.map(\.alias))
        refreshNow()
    }

    func clearSelection() {
        applySelectedAliases([])
    }

    func statusState(for host: SSHHost) -> NodeStatusState {
        statusStatesByAlias[host.alias] ?? .idle
    }

    func hostStatusSummary(for host: SSHHost) -> String {
        let state = statusState(for: host)
        if let status = state.status {
            return "CPU \(status.cpuUsageText), memory \(status.memoryUsageText), disk \(status.diskUsageText)"
        }
        if let errorMessage = state.errorMessage {
            return errorMessage
        }
        return "No data yet."
    }

    private func reloadHostsTask(triggerRefresh: Bool) async {
        do {
            let hosts = try await configService.loadHosts()
            detectedHosts = hosts
            configErrorMessage = nil
            lastHostReloadAt = Date()

            let availableAliases = Set(availableHosts.map(\.alias))
            statusStatesByAlias = statusStatesByAlias.filter { availableAliases.contains($0.key) }
            applySelectedAliases(selectedAliases)

            if triggerRefresh {
                refreshNow()
            }
        } catch {
            detectedHosts = []
            configErrorMessage = error.localizedDescription
            lastHostReloadAt = Date()
            let availableAliases = Set(availableHosts.map(\.alias))
            statusStatesByAlias = statusStatesByAlias.filter { availableAliases.contains($0.key) }
            applySelectedAliases(selectedAliases)
        }
    }

    private func applySelectedAliases(_ aliases: [String]) {
        let availableAliases = Set(availableHosts.map(\.alias))
        selectedAliases = Self.normalizeAliases(aliases, availableAliases: availableAliases)
        if isMenuBarHostSelectionExplicit {
            menuBarSelectedAliases = Self.normalizeMenuBarSelectedAliases(
                menuBarSelectedAliases,
                selectedAliases: selectedAliases,
                limit: menuBarMaxDisplayedHosts
            )
        }
        publishWidgetSnapshot()
    }

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                let interval = self.refreshIntervalSeconds
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    break
                }

                guard !Task.isCancelled else { break }
                self.refreshNow()
            }
        }
    }

    private static func normalizeRefreshInterval(_ value: Int?) -> Int {
        min(max(value ?? defaultRefreshIntervalSeconds, minimumRefreshIntervalSeconds), maximumRefreshIntervalSeconds)
    }

    private static func normalizeMenuBarMaxDisplayedHosts(_ value: Int?) -> Int {
        let rawValue = value ?? defaultMenuBarMaxDisplayedHosts
        return min(max(rawValue, minimumMenuBarMaxDisplayedHosts), maximumMenuBarMaxDisplayedHosts)
    }

    private static func normalizeAliases(_ aliases: [String], availableAliases: Set<String>) -> [String] {
        var normalized: [String] = []
        var seen = Set<String>()

        for alias in aliases where availableAliases.contains(alias) {
            if seen.insert(alias).inserted {
                normalized.append(alias)
            }
        }

        return normalized
    }

    private static func normalizeMenuBarSelectedAliases(
        _ aliases: [String],
        selectedAliases: [String],
        limit: Int
    ) -> [String] {
        let selectedAliasSet = Set(selectedAliases)
        return Array(
            uniqueAliases(aliases)
                .filter { selectedAliasSet.contains($0) }
                .prefix(limit)
        )
    }

    private static func uniqueAliases(_ aliases: [String]) -> [String] {
        var normalized: [String] = []
        var seen = Set<String>()

        for alias in aliases where seen.insert(alias).inserted {
            normalized.append(alias)
        }

        return normalized
    }

    private static func migrateLegacyDefaultsIfNeeded(into userDefaults: UserDefaults) {
        guard userDefaults === UserDefaults.standard,
              userDefaults.object(forKey: legacyDefaultsMigrationKey) == nil,
              let legacyValues = UserDefaults.standard.persistentDomain(forName: legacyBundleIdentifier),
              !legacyValues.isEmpty
        else { return }

        copyLegacyValue(from: legacyValues, to: userDefaults, forKey: refreshIntervalDefaultsKey)
        copyLegacyValue(from: legacyValues, to: userDefaults, forKey: menuBarMaxDisplayedHostsDefaultsKey)
        copyLegacyAliasArray(from: legacyValues, to: userDefaults, forKey: selectedAliasesDefaultsKey)
        copyLegacyAliasArray(from: legacyValues, to: userDefaults, forKey: menuBarSelectedAliasesDefaultsKey)
        copyLegacyAlias(from: legacyValues, to: userDefaults, forKey: legacyMenuBarAliasDefaultsKey)
        userDefaults.set(true, forKey: legacyDefaultsMigrationKey)
    }

    private static func copyLegacyValue(from legacyValues: [String: Any], to userDefaults: UserDefaults, forKey key: String) {
        guard userDefaults.object(forKey: key) == nil, let value = legacyValues[key] else { return }
        userDefaults.set(value, forKey: key)
    }

    private static func copyLegacyAliasArray(from legacyValues: [String: Any], to userDefaults: UserDefaults, forKey key: String) {
        guard userDefaults.object(forKey: key) == nil, let aliases = legacyValues[key] as? [String] else { return }
        userDefaults.set(aliases.map(migrateLegacyAlias), forKey: key)
    }

    private static func copyLegacyAlias(from legacyValues: [String: Any], to userDefaults: UserDefaults, forKey key: String) {
        guard userDefaults.object(forKey: key) == nil, let alias = legacyValues[key] as? String else { return }
        userDefaults.set(migrateLegacyAlias(alias), forKey: key)
    }

    private static func migrateLegacyAlias(_ alias: String) -> String {
        alias == legacyLocalHostAlias ? localHostAlias : alias
    }

    private var defaultMenuBarSelectedAliases: [String] {
        Array(selectedAliases.prefix(menuBarMaxDisplayedHosts))
    }

    private var effectiveMenuBarSelectedAliases: [String] {
        isMenuBarHostSelectionExplicit ? menuBarSelectedAliases : defaultMenuBarSelectedAliases
    }

    private func trimMenuBarSelectedAliasesToDisplayLimit() {
        guard isMenuBarHostSelectionExplicit,
              menuBarSelectedAliases.count > menuBarMaxDisplayedHosts else {
            return
        }

        menuBarSelectedAliases = Array(menuBarSelectedAliases.prefix(menuBarMaxDisplayedHosts))
    }

    private func persistMenuBarHostSelection() {
        guard isMenuBarHostSelectionExplicit else { return }

        userDefaults.set(
            Self.normalizeMenuBarSelectedAliases(
                menuBarSelectedAliases,
                selectedAliases: selectedAliases,
                limit: menuBarMaxDisplayedHosts
            ),
            forKey: Self.menuBarSelectedAliasesDefaultsKey
        )
    }

    private func menuBarLabel(for host: SSHHost) -> String {
        if host.isLocal {
            return "mac"
        }

        let token = host.alias
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
            .prefix(4)

        return token.isEmpty ? "host" : String(token)
    }

    private func hostsForRefresh() -> [SSHHost] {
        var orderedHosts: [SSHHost] = []
        var seenAliases = Set<String>()

        for host in selectedHosts {
            if seenAliases.insert(host.alias).inserted {
                orderedHosts.append(host)
            }
        }

        for host in menuBarHosts where seenAliases.insert(host.alias).inserted {
            orderedHosts.append(host)
        }

        return orderedHosts
    }

    private func publishWidgetSnapshot() {
        let snapshot = WidgetSnapshot(
            generatedAt: Date(),
            lastRefreshAt: lastRefreshAt,
            primaryAlias: primaryHost?.alias,
            selectedHosts: selectedHosts.map { host in
                let state = statusState(for: host)
                return WidgetHostSnapshot(
                    alias: host.alias,
                    endpointDescription: host.endpointDescription,
                    cpuUsagePercent: state.status?.cpuUsagePercent,
                    memoryUsagePercent: state.status?.memoryUsagePercent,
                    memoryUsedBytes: state.status?.memoryUsedBytes,
                    memoryTotalBytes: state.status?.memoryTotalBytes,
                    loadAverages: state.status?.loadAverages ?? [],
                    uptimeSeconds: state.status?.uptimeSeconds,
                    updatedAt: state.status?.collectedAt,
                    errorMessage: state.errorMessage
                )
            },
            configErrorMessage: configErrorMessage
        )

        localSnapshotServer.update(snapshot: snapshot)

        do {
            try WidgetSnapshotStore.save(snapshot)
        } catch {
            // Keep the local server source available even if file-based sharing fails.
        }

        #if canImport(WidgetKit)
        if #available(macOS 14.0, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: ComputerBarWidgetConstants.statusWidgetKind)
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }
}
