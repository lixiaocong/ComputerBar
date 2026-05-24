using System;
using System.IO;
using ComputerBar.Core;

namespace ComputerBar.Windows;

internal static class ShellLog
{
    private static readonly object Gate = new();
    private static readonly string LogFile = Path.Combine(ComputerBarPaths.Default.RootDirectory, "shell.log");

    public static void Write(string message)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LogFile)!);
            lock (Gate)
            {
                File.AppendAllText(LogFile, $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}");
            }
        }
        catch
        {
        }
    }

    public static void Write(Exception exception, string message) =>
        Write($"{message}: {exception}");
}
