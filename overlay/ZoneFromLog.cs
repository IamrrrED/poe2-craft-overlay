using System.Text;
using System.Text.RegularExpressions;

namespace Poe2CraftOverlay;

/// <summary>
/// Which zone the character is in, read from the game's own log.
///
/// The log is the only honest source: the overlay cannot read game memory, and a screenshot cannot be parsed for
/// "am I in a hideout". Two lines carry what is needed:
///   * `Generating level 65 area "HideoutShoreline" with seed 1` - the internal area code, language independent;
///   * `[SCENE] Set Source [Убежище на берегу]` - the localised name, kept as a cross-check and for the message.
///
/// The area code is the reliable half: a hideout is any area whose code contains "Hideout" (HideoutShoreline,
/// HideoutMines, HideoutTree...), while maps, towns and campaign areas never do.
/// </summary>
public sealed record ZoneInfo(string AreaCode, string AreaName, DateTime? At, bool IsHideout, string Source)
{
    public TimeSpan? Age => At is null ? null : DateTime.Now - At.Value;

    public string Describe()
    {
        var age = Age is null ? "unknown age" : $"{Age.Value.TotalMinutes:F0} min old";
        return $"zone «{AreaName}» ({AreaCode}), {(IsHideout ? "hideout" : "not a hideout")}, {age}";
    }
}

public static class ZoneFromLog
{
    private const int TailBytes = 2 * 1024 * 1024;

    private static readonly Regex AreaLine = new(
        @"^(?<stamp>\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}).*Generating level \d+ area ""(?<code>[^""]+)""",
        RegexOptions.Compiled);

    private static readonly Regex SceneLine = new(
        @"^(?<stamp>\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}).*\[SCENE\] Set Source \[(?<name>[^\]]+)\]",
        RegexOptions.Compiled);

    /// <summary>
    /// The game's log, found from the running process first (the Steam build sits anywhere the player installed it)
    /// and from the usual documents folder as a fallback.
    /// </summary>
    public static string? Find()
    {
        foreach (var process in System.Diagnostics.Process.GetProcessesByName("PathOfExileSteam")
            .Concat(System.Diagnostics.Process.GetProcessesByName("PathOfExile2"))
            .Concat(System.Diagnostics.Process.GetProcessesByName("PathOfExile")))
        {
            try
            {
                var path = process.MainModule?.FileName;
                if (string.IsNullOrEmpty(path))
                {
                    continue;
                }
                var candidate = Path.Combine(Path.GetDirectoryName(path)!, "logs", "Client.txt");
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }
            catch
            {
                // A process whose module cannot be read is skipped: the documents fallback still exists.
            }
        }

        var documents = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
            "My Games", "Path of Exile 2", "logs", "Client.txt");
        return File.Exists(documents) ? documents : null;
    }

    /// <summary>Parse the last zone change out of the log at this path.</summary>
    public static ZoneInfo? Read(string logPath)
    {
        try
        {
            var tail = ReadTail(logPath, TailBytes);
            if (string.IsNullOrEmpty(tail))
            {
                return null;
            }

            string? code = null;
            string? name = null;
            DateTime? codeAt = null;
            DateTime? nameAt = null;

            foreach (var line in tail.Split('\n'))
            {
                var area = AreaLine.Match(line);
                if (area.Success)
                {
                    code = area.Groups["code"].Value;
                    codeAt = ParseStamp(area.Groups["stamp"].Value);
                    continue;
                }
                var scene = SceneLine.Match(line);
                if (scene.Success)
                {
                    name = scene.Groups["name"].Value;
                    nameAt = ParseStamp(scene.Groups["stamp"].Value);
                }
            }

            if (code is null && name is null)
            {
                return null;
            }

            // The code decides when it is present; the name is the cross-check and the human-readable half.
            var looksHideout = (code ?? "").Contains("Hideout", StringComparison.OrdinalIgnoreCase)
                || (name ?? "").Contains("убежищ", StringComparison.OrdinalIgnoreCase)
                || (name ?? "").Contains("hideout", StringComparison.OrdinalIgnoreCase);
            return new ZoneInfo(code ?? "?", name ?? "?", codeAt ?? nameAt, looksHideout,
                code is not null ? "area code" : "scene name");
        }
        catch
        {
            return null;
        }
    }

    /// <summary>Read the last bytes of a file without loading 70 MB of chat into memory.</summary>
    private static string ReadTail(string path, int bytes)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        var length = stream.Length;
        var start = Math.Max(0, length - bytes);
        stream.Seek(start, SeekOrigin.Begin);
        using var reader = new StreamReader(stream, Encoding.UTF8);
        var text = reader.ReadToEnd();
        // Only a read that STARTED mid-file has a half-cut first line. Dropping it unconditionally threw away the
        // very line the parser looks for in a short file - a fixture, or a session that has just started.
        if (start == 0)
        {
            return text;
        }
        var firstBreak = text.IndexOf('\n');
        return firstBreak >= 0 ? text[(firstBreak + 1)..] : text;
    }

    private static DateTime? ParseStamp(string value)
    {
        return DateTime.TryParseExact(value, "yyyy/MM/dd HH:mm:ss",
            System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.None, out var stamp)
            ? stamp
            : null;
    }
}
