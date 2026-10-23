using System.IO;

namespace Poe2CraftOverlay;

/// A plain file log. The overlay is usually the only thing on screen, so what it did has to be
/// readable afterwards: without it, "the window did not appear" cannot be told apart from "the
/// window appeared and did nothing".
internal static class Log
{
    private static readonly string Path = System.IO.Path.Combine(AppContext.BaseDirectory, "overlay.log");

    public static void Write(string message)
    {
        try
        {
            File.AppendAllText(Path, $"[{DateTime.Now:HH:mm:ss}] {message}{Environment.NewLine}");
        }
        catch
        {
            // a log that throws is worse than a missing line
        }
    }
}