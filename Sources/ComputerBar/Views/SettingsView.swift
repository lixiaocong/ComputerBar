import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        @Bindable var model = model

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Computer Bar")
                    .font(.title2.weight(.semibold))

                Text("Monitors any mix of this Mac and remote SSH hosts. Choose which hosts to track, then choose which monitored machines appear in the compact menu bar summary.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox("Menu Bar") {
                    VStack(alignment: .leading, spacing: 10) {
                        Stepper(
                            value: $model.menuBarMaxDisplayedHosts,
                            in: AppModel.minimumMenuBarMaxDisplayedHosts ... AppModel.maximumMenuBarMaxDisplayedHosts
                        ) {
                            LabeledContent(
                                "Menu bar machines",
                                value: "\(model.menuBarMaxDisplayedHosts)"
                            )
                        }

                        Text("Controls how many selected machine rows are stacked in the fixed-width menu bar icon.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if model.hasExplicitMenuBarHostSelection {
                            Button("Use First Machines Automatically") {
                                model.resetMenuBarHostSelection()
                            }
                        }

                        if model.selectedHosts.isEmpty {
                            Text("Select at least one host below to use the menu bar summary.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                GroupBox("Refresh") {
                    VStack(alignment: .leading, spacing: 10) {
                        Stepper(
                            value: $model.refreshIntervalSeconds,
                            in: AppModel.minimumRefreshIntervalSeconds ... AppModel.maximumRefreshIntervalSeconds
                        ) {
                            LabeledContent("Refresh interval", value: "\(model.refreshIntervalSeconds) second\(model.refreshIntervalSeconds == 1 ? "" : "s")")
                        }

                        Text("Default is 1 second. Lower intervals create more SSH traffic and more remote command executions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                GroupBox("Monitored Hosts") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("SSH config", value: model.sshConfigPathDisplay)

                        if let configErrorMessage = model.configErrorMessage {
                            Text(configErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Select any mix of local and remote hosts to show in the window and widget.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: 10) {
                            Button("Reload Hosts") {
                                model.reloadHosts()
                            }

                            Button("Select All") {
                                model.selectAllHosts()
                            }
                            .disabled(model.availableHosts.isEmpty)

                            Button("Clear Selection") {
                                model.clearSelection()
                            }
                            .disabled(model.selectedHosts.isEmpty)

                            Spacer()
                        }

                        if model.detectedHosts.isEmpty, model.configErrorMessage == nil {
                            Text("No remote hosts were found in your SSH config. This Mac is still available above.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(model.availableHosts) { host in
                                    HostSelectionRow(host: host, model: model)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                HStack(spacing: 10) {
                    Button("Refresh Now") {
                        model.refreshNow()
                    }

                    if let lastRefreshAt = model.lastRefreshAt {
                        Text("Last refresh: \(lastRefreshAt.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

private struct HostSelectionRow: View {
    let host: SSHHost
    let model: AppModel

    var body: some View {
        let isSelected = model.isHostSelected(host)
        let selectionIndex = model.selectionIndex(for: host)
        let isShownInMenuBar = model.isHostShownInMenuBar(host)

        HStack(alignment: .top, spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: { isSelected },
                    set: { model.setHost(host, selected: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(host.displayName)
                        .font(.headline)

                    if isShownInMenuBar {
                        rowBadge("Menu Bar", tint: .blue)
                    }

                    if let selectionIndex {
                        rowBadge("#\(selectionIndex)", tint: .secondary)
                    }
                }

                Text(host.endpointDescription)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(model.hostStatusSummary(for: host))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(
                    "Menu Bar",
                    isOn: Binding(
                        get: { model.isHostShownInMenuBar(host) },
                        set: { model.setHost(host, shownInMenuBar: $0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(.caption)
                .disabled(!isSelected)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func rowBadge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }
}
