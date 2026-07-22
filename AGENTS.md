# Computer Bar

## Summary

Computer Bar is a macOS menu bar app plus WidgetKit extension for monitoring remote Linux hosts over SSH.

Core behavior:
- Reads `~/.ssh/config` for the host list.
- Allows multi-select host monitoring.
- Shows compact CPU, memory, optional Linux swap, and disk usage for selected hosts in the menu bar.
- Opens a panel that shows one column per selected host.
- Refreshes in the background on the configured interval. Default is `1s`.
- Ships with a desktop widget that renders the latest stored snapshot.

## Main Components

- `Sources/ComputerBar/AppModel.swift`
  Central state model for host loading, polling, selection, menu bar text, and widget snapshot publishing.

- `Sources/ComputerBar/SSHConfigService.swift`
  Loads aliases from `~/.ssh/config` and resolves host details.

- `Sources/ComputerBar/SSHMonitorService.swift`
  Runs the remote Linux metric collection over SSH and parses CPU, memory, optional swap, disk, load, and uptime.

- `Sources/ComputerBar/Views/MenuBarView.swift`
  Popover UI for host details and selection-driven layout.

- `Sources/ComputerBar/Views/SettingsView.swift`
  Settings UI, including refresh interval.

- `Sources/ComputerBar/ComputerBarStatusController.swift`
  Owns the NSStatusItem and keeps the menu bar item stable.

- `Sources/ComputerBarWidget/ComputerBarWidget.swift`
  Widget timeline/provider and widget rendering.

- `Sources/ComputerBarShared/WidgetSnapshotStore.swift`
  Shared snapshot encoding, persistence, and lookup rules for app and widget.

- `Sources/ComputerBar/LocalSnapshotServer.swift`
  Small localhost HTTP server used as an additional live snapshot source while the app is running.

## Current UX/Behavior Notes

- The menu bar does not show a visible `Refreshing…` state. Refresh stays silent in the background.
- The menu bar title uses a stable width template so the item does not jitter as numbers change.
- The popover grows with its content but remains capped to avoid oversized windows.
- Single-host popovers are centered instead of being left-biased.
- The Linux metric command was rewritten to avoid non-portable `awk` usage.

## Widget Snapshot Flow

The app and widget share snapshots through paths each process is entitled to access:

1. App-group files under `CP22VZ6846.com.computerbar.app.shared`
2. Legacy `~/Library/Application Support/ComputerBar/widget-snapshot.json`
3. Read-only legacy paths inside the widget's own sandbox
4. Localhost fallback from `LocalSnapshotServer` on port `61337`

The host app must never write to `~/Library/Containers/com.computerbar.app.widget` or open an
unentitled legacy App Group. Current macOS versions treat that as another app's protected data and
show an App Data permission prompt. Shared app-group `UserDefaults` is also intentionally avoided;
the file channel is asynchronous and does not block startup.

Important file:
- `Sources/ComputerBarShared/WidgetSnapshotStore.swift`

Important operational detail:
- If the widget ever gets stuck on old state, remove and re-add the widget after launching the latest app build.

## Build

Build script:
- `scripts/build-app.sh`

Build flow:
- Generates icons
- Generates the Xcode project with `xcodegen`
- Builds the app and widget extension
- Re-signs the `.appex`
- Re-signs the final `.app`

The install script prefers an Apple Development identity with a stable Team ID. Do not replace it
with a self-signed identity for routine local installs; changing the designated identity makes macOS
treat rebuilt copies as a different app and can trigger permission prompts again.

Common commands:

```bash
swift test
./scripts/build-app.sh
```

Output bundle:

```bash
build/ComputerBar.app
```

## Install

Use a clean replace when updating the installed app. Do not merge-copy over an older bundle.

Preferred install flow:

```bash
rm -rf /Applications/ComputerBar.app
cp -R build/ComputerBar.app /Applications/
open -a /Applications/ComputerBar.app
```

Reason:
- A plain overwrite can leave an old embedded widget extension in place, which can make widget debugging misleading.

## Troubleshooting

If the widget shows `No Snapshot Yet`:

1. Confirm the app is actually running.
2. Rebuild with `./scripts/build-app.sh`.
3. Clean-replace `/Applications/ComputerBar.app`.
4. Launch the new app once.
5. Remove and re-add the widget.

Snapshot files commonly used during debugging:

```text
~/Library/Application Support/ComputerBar/widget-snapshot.json
~/Library/Group Containers/CP22VZ6846.com.computerbar.app.shared/widget-snapshot.json
~/Library/Group Containers/CP22VZ6846.com.computerbar.app.shared/Library/Application Support/ComputerBar/widget-snapshot.json
```
