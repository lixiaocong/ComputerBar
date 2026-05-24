using System.Text.Json;
using System.Text.Json.Serialization;

namespace ComputerBar.Core;

public sealed record ComputerBarPathSet(string RootDirectory)
{
    public string SettingsFile => Path.Combine(RootDirectory, "settings.json");
}

public static class ComputerBarPaths
{
    public static ComputerBarPathSet Default { get; } = new(
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "ComputerBar"));

    public static string DefaultSshConfigFile => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".ssh",
        "config");
}

public sealed class JsonSettingsStore(ComputerBarPathSet? paths = null) : ISettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = JsonOptionsFactory.Create();
    private readonly ComputerBarPathSet _paths = paths ?? ComputerBarPaths.Default;

    public async Task<ComputerBarSettings> LoadAsync(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(_paths.SettingsFile))
        {
            return ComputerBarSettings.Default;
        }

        await using var stream = File.OpenRead(_paths.SettingsFile);
        var settings = await JsonSerializer.DeserializeAsync<ComputerBarSettings>(
            stream,
            JsonOptions,
            cancellationToken);
        return (settings ?? ComputerBarSettings.Default).Normalized();
    }

    public async Task SaveAsync(ComputerBarSettings settings, CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(_paths.RootDirectory);
        var normalized = settings.Normalized();
        var tempFile = _paths.SettingsFile + ".tmp";
        await using (var stream = File.Create(tempFile))
        {
            await JsonSerializer.SerializeAsync(stream, normalized, JsonOptions, cancellationToken);
        }

        File.Move(tempFile, _paths.SettingsFile, overwrite: true);
    }
}

internal static class JsonOptionsFactory
{
    public static JsonSerializerOptions Create()
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web)
        {
            WriteIndented = true
        };
        options.Converters.Add(new JsonStringEnumConverter());
        return options;
    }
}
