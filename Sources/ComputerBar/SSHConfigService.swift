import Foundation

enum SSHConfigLoadError: LocalizedError {
    case missingConfig(URL)
    case unreadableConfig(URL, underlying: Error)
    case noHostsFound(URL)

    var errorDescription: String? {
        switch self {
        case let .missingConfig(url):
            return "Could not find SSH config at \(NSString(string: url.path).abbreviatingWithTildeInPath)."
        case let .unreadableConfig(url, underlying):
            return "Could not read \(NSString(string: url.path).abbreviatingWithTildeInPath): \(underlying.localizedDescription)"
        case let .noHostsFound(url):
            return "No concrete Host aliases were found in \(NSString(string: url.path).abbreviatingWithTildeInPath)."
        }
    }
}

struct SSHConfigService {
    let configURL: URL

    init(configURL: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ssh/config")) {
        self.configURL = configURL
    }

    func loadHosts() async throws -> [SSHHost] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: configURL.path) else {
            throw SSHConfigLoadError.missingConfig(configURL)
        }

        let contents: String
        do {
            contents = try String(contentsOf: configURL, encoding: .utf8)
        } catch {
            throw SSHConfigLoadError.unreadableConfig(configURL, underlying: error)
        }

        let aliases = SSHConfigParser.parseAliases(from: contents)
        guard !aliases.isEmpty else {
            throw SSHConfigLoadError.noHostsFound(configURL)
        }

        var hosts: [SSHHost] = []
        for alias in aliases {
            hosts.append(await resolve(alias: alias))
        }

        return hosts
    }

    private func resolve(alias: String) async -> SSHHost {
        do {
            let output = try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
                arguments: ["-G", alias],
                timeout: 3
            )

            guard output.exitCode == 0 else {
                return SSHHost(alias: alias, hostName: alias, user: nil, port: nil)
            }

            return SSHConfigParser.parseResolvedHost(alias: alias, output: output.stdout)
        } catch {
            return SSHHost(alias: alias, hostName: alias, user: nil, port: nil)
        }
    }
}

enum SSHConfigParser {
    static func parseAliases(from contents: String) -> [String] {
        var aliases: [String] = []
        var seen = Set<String>()

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let parts = line.split(whereSeparator: \.isWhitespace)
            guard let first = parts.first, first.lowercased() == "host" else { continue }

            for token in parts.dropFirst() {
                let alias = String(token)
                if alias.hasPrefix("#") {
                    break
                }
                guard isConcreteAlias(alias) else { continue }
                if seen.insert(alias).inserted {
                    aliases.append(alias)
                }
            }
        }

        return aliases
    }

    static func parseResolvedHost(alias: String, output: String) -> SSHHost {
        var hostName: String?
        var user: String?
        var port: Int?

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let parts = rawLine.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { continue }

            let key = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

            switch key {
            case "hostname":
                if hostName == nil, !value.isEmpty {
                    hostName = value
                }
            case "user":
                if user == nil, !value.isEmpty {
                    user = value
                }
            case "port":
                if port == nil {
                    port = Int(value)
                }
            default:
                continue
            }
        }

        return SSHHost(
            alias: alias,
            hostName: hostName ?? alias,
            user: user,
            port: port
        )
    }

    private static func isConcreteAlias(_ alias: String) -> Bool {
        guard !alias.isEmpty else { return false }
        guard !alias.hasPrefix("!") else { return false }
        guard !alias.contains("*"), !alias.contains("?") else { return false }
        return true
    }
}
