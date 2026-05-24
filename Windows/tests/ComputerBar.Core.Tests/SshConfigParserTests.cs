using ComputerBar.Core;

namespace ComputerBar.Core.Tests;

public sealed class SshConfigParserTests
{
    [Fact]
    public void ParseHostsIgnoresWildcardsAndNegatedPatterns()
    {
        const string config = """
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
        """;

        var hosts = SshConfigParser.ParseHosts(config);

        Assert.Equal(["dev", "staging", "prod"], hosts.Select(host => host.Alias));
        Assert.Equal("ubuntu", hosts[0].User);
        Assert.Equal("10.0.0.1", hosts[2].HostName);
    }

    [Fact]
    public void ParseHostsUsesBlockValues()
    {
        const string config = """
        Host dev
          HostName 192.168.1.30
          User ubuntu
          Port 2222
        """;

        var host = Assert.Single(SshConfigParser.ParseHosts(config));

        Assert.Equal("dev", host.Alias);
        Assert.Equal("192.168.1.30", host.HostName);
        Assert.Equal("ubuntu", host.User);
        Assert.Equal(2222, host.Port);
    }
}
