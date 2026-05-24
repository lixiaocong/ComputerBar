namespace ComputerBar.Core;

public enum SshConfigLoadErrorKind
{
    MissingConfig,
    UnreadableConfig,
    NoHostsFound
}

public sealed class SshConfigLoadException(
    SshConfigLoadErrorKind kind,
    string path,
    Exception? innerException = null)
    : Exception(BuildMessage(kind, path, innerException), innerException)
{
    public SshConfigLoadErrorKind Kind { get; } = kind;
    public string PathValue { get; } = path;

    private static string BuildMessage(SshConfigLoadErrorKind kind, string path, Exception? innerException) => kind switch
    {
        SshConfigLoadErrorKind.MissingConfig => $"Could not find SSH config at {path}.",
        SshConfigLoadErrorKind.UnreadableConfig => $"Could not read {path}: {innerException?.Message ?? "unknown error"}",
        SshConfigLoadErrorKind.NoHostsFound => $"No concrete Host aliases were found in {path}.",
        _ => $"Could not load SSH config at {path}."
    };
}

public sealed class SshConfigService(string? configFile = null) : IHostConfigService
{
    public string ConfigFile { get; } = configFile ?? ComputerBarPaths.DefaultSshConfigFile;

    public async Task<IReadOnlyList<ComputerHost>> LoadHostsAsync(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(ConfigFile))
        {
            throw new SshConfigLoadException(SshConfigLoadErrorKind.MissingConfig, ConfigFile);
        }

        string contents;
        try
        {
            contents = await File.ReadAllTextAsync(ConfigFile, cancellationToken);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            throw new SshConfigLoadException(SshConfigLoadErrorKind.UnreadableConfig, ConfigFile, ex);
        }

        var hosts = SshConfigParser.ParseHosts(contents);
        if (hosts.Count == 0)
        {
            throw new SshConfigLoadException(SshConfigLoadErrorKind.NoHostsFound, ConfigFile);
        }

        return hosts;
    }
}

public static class SshConfigParser
{
    public static IReadOnlyList<string> ParseAliases(string contents) =>
        ParseHosts(contents).Select(host => host.Alias).ToArray();

    public static IReadOnlyList<ComputerHost> ParseHosts(string contents)
    {
        var hosts = new List<ComputerHost>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var aliases = new List<string>();
        string? hostName = null;
        string? user = null;
        int? port = null;

        void CommitBlock()
        {
            foreach (var alias in aliases)
            {
                if (!seen.Add(alias))
                {
                    continue;
                }

                hosts.Add(new ComputerHost(alias, hostName ?? alias, user, port));
            }
        }

        foreach (var rawLine in contents.Split(["\r\n", "\n"], StringSplitOptions.None))
        {
            var line = TrimInlineComment(rawLine).Trim();
            if (line.Length == 0)
            {
                continue;
            }

            var parts = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 0)
            {
                continue;
            }

            var key = parts[0];
            if (key.Equals("Host", StringComparison.OrdinalIgnoreCase))
            {
                CommitBlock();
                aliases = parts.Skip(1)
                    .TakeWhile(token => !token.StartsWith('#'))
                    .Where(IsConcreteAlias)
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .ToList();
                hostName = null;
                user = null;
                port = null;
                continue;
            }

            if (aliases.Count == 0 || parts.Length < 2)
            {
                continue;
            }

            var value = string.Join(" ", parts.Skip(1)).Trim();
            switch (key.ToLowerInvariant())
            {
                case "hostname":
                    if (hostName is null && value.Length > 0)
                    {
                        hostName = value;
                    }
                    break;
                case "user":
                    if (user is null && value.Length > 0)
                    {
                        user = value;
                    }
                    break;
                case "port":
                    if (port is null && int.TryParse(value, out var parsedPort))
                    {
                        port = parsedPort;
                    }
                    break;
            }
        }

        CommitBlock();
        return hosts;
    }

    private static string TrimInlineComment(string line)
    {
        for (var index = 0; index < line.Length; index++)
        {
            if (line[index] == '#' && (index == 0 || char.IsWhiteSpace(line[index - 1])))
            {
                return line[..index];
            }
        }

        return line;
    }

    private static bool IsConcreteAlias(string alias)
    {
        if (string.IsNullOrWhiteSpace(alias))
        {
            return false;
        }

        return !alias.StartsWith('!')
            && !alias.Contains('*')
            && !alias.Contains('?');
    }
}
