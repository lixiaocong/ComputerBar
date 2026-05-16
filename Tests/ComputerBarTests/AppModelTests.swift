import XCTest
@testable import ComputerBar

@MainActor
final class AppModelTests: XCTestCase {
    func testLocalHostMenuBarTitleUsesDisplayName() throws {
        let suiteName = "ComputerBar.AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(["__local__computerbar__"], forKey: "selectedAliases")

        let model = AppModel(userDefaults: defaults, startImmediately: false)

        XCTAssertEqual(model.primaryHost?.displayName, "This Mac")
        XCTAssertEqual(model.menuBarMaxDisplayedHosts, 2)
        XCTAssertEqual(model.menuBarHosts.map(\.displayName), ["This Mac"])
        XCTAssertEqual(model.menuBarAccessibilityTitle, "This Mac: waiting for first refresh.")
        XCTAssertEqual(model.menuBarStatusBars, [
            MenuBarStatusImage.Bar(label: "mac")
        ])
    }

    func testMenuBarSupportsMultipleDisplayedMachines() throws {
        let suiteName = "ComputerBar.AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(["__local__computerbar__", "ec2", "prod"], forKey: "selectedAliases")

        let model = AppModel(userDefaults: defaults, startImmediately: false)
        model.detectedHosts = [
            SSHHost(alias: "ec2", hostName: "ec2.internal", user: "ubuntu", port: 2222),
            SSHHost(alias: "prod", hostName: "prod.internal", user: "admin", port: 22),
        ]

        XCTAssertEqual(model.menuBarHosts.map(\.alias), ["__local__computerbar__", "ec2"])
        XCTAssertEqual(model.menuBarStatusBars, [
            MenuBarStatusImage.Bar(label: "mac"),
            MenuBarStatusImage.Bar(label: "ec2"),
        ])

        model.menuBarMaxDisplayedHosts = 3
        XCTAssertEqual(model.menuBarHosts.map(\.alias), ["__local__computerbar__", "ec2", "prod"])
        XCTAssertEqual(model.menuBarStatusBars, [
            MenuBarStatusImage.Bar(label: "mac"),
            MenuBarStatusImage.Bar(label: "ec2"),
            MenuBarStatusImage.Bar(label: "prod"),
        ])

        let ec2 = try XCTUnwrap(model.availableHosts.first { $0.alias == "ec2" })
        model.setHost(ec2, shownInMenuBar: false)
        XCTAssertTrue(model.hasExplicitMenuBarHostSelection)
        XCTAssertEqual(model.menuBarHosts.map(\.alias), ["__local__computerbar__", "prod"])
    }

    func testLegacySingleMenuBarHostPreferenceMigratesToExplicitSelection() throws {
        let suiteName = "ComputerBar.AppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(["__local__computerbar__", "ec2"], forKey: "selectedAliases")
        defaults.set("ec2", forKey: "menuBarAlias")

        let model = AppModel(userDefaults: defaults, startImmediately: false)
        model.detectedHosts = [
            SSHHost(alias: "ec2", hostName: "ec2.internal", user: "ubuntu", port: 2222),
        ]

        XCTAssertTrue(model.hasExplicitMenuBarHostSelection)
        XCTAssertEqual(model.menuBarHosts.map(\.alias), ["ec2"])
        XCTAssertEqual(model.menuBarStatusBars, [
            MenuBarStatusImage.Bar(label: "ec2")
        ])
    }
}
