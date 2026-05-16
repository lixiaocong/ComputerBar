import XCTest
@testable import ComputerBar

final class SSHConfigParserTests: XCTestCase {
    func testParseAliasesIgnoresWildcardsAndNegatedPatterns() {
        let config = """
        Host *
            ServerAliveInterval 60

        Host dev staging
            User ubuntu

        Host !prod
            User nobody

        Host jump-* qa?
            Port 2222

        Host prod # inline comment
            HostName 10.0.0.1
        """

        XCTAssertEqual(SSHConfigParser.parseAliases(from: config), ["dev", "staging", "prod"])
    }

    func testParseResolvedHostUsesResolvedValues() {
        let output = """
        host dev
        hostname 192.168.1.30
        user ubuntu
        port 2222
        """

        let host = SSHConfigParser.parseResolvedHost(alias: "dev", output: output)

        XCTAssertEqual(host.alias, "dev")
        XCTAssertEqual(host.hostName, "192.168.1.30")
        XCTAssertEqual(host.user, "ubuntu")
        XCTAssertEqual(host.port, 2222)
    }
}
