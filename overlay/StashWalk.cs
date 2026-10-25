using System.Diagnostics;
using System.Text.Json;

namespace Poe2CraftOverlay;

/// <summary>
/// Walks every stash tab with the strip arrow at the right end of the tab row, and captures each page.
///
/// The method is the one the customer pointed at: the strip shows only a few tabs, the arrow scrolls it, and each tab
/// label is clickable. Labels and their coordinates come from OCR (Windows.Media.Ocr via tools/ocr.ps1) - never from a
/// coordinate someone estimated. Every capture is compared with the previous page over the panel region: an unchanged
/// panel means the click did not switch anything, and the run says so instead of quietly producing eleven copies of
/// the same page.
///
/// No item is touched: only tab labels and the arrow are clicked.
/// </summary>
public static class StashWalk
{
    private const string ExpectedTitle = "Тайник";
    private const int StripLeft = 20;
    private const int StripTop = 120;
    private const int StripWidth = 820;
    private const int StripHeight = 48;
    private const int ArrowX = 856;
    private const int ArrowY = 146;

    public sealed record Page(string Name, string Path, double PanelDiff);

    public static IReadOnlyList<Page> LastPages { get; private set; } = Array.Empty<Page>();

    private const int ListLeft = 880;
    private const int ListTop = 130;
    private const int ListWidth = 300;
    private const int ListHeight = 800;

    private static void OpenListButton() => StashTabs.ClickAt(862, 146);

    private static bool LooksLikeTabList(string text)
    {
        foreach (var marker in new[] { "RITUAL", "MAPS", "FRAGMENTS", "GEMS", "DELIRIUM", "EXPEDITION", "RUNES" })
        {
            if (text.Contains(marker, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }

    private static bool EnsureListOpen(string outDir, List<string> report)
    {
        var frame = Path.Combine(outDir, "walk-check.png");
        for (var attempt = 0; attempt < 4; attempt++)
        {
            StashOpener.Shot(frame);
            var text = OcrText(frame, ListLeft, ListTop, ListWidth, ListHeight);
            if (LooksLikeTabList(text) && ReadRows(frame, ListLeft, ListTop, ListWidth, ListHeight).Count > 0)
            {
                return true;
            }
            if (!EnsureForeground(out _))
            {
                Thread.Sleep(200);
            }
            OpenListButton();
            Thread.Sleep(700);
        }
        return false;
    }
    /// The game must be the foreground window at the moment of a click, or the click lands in another window.
    /// Measured: a scripted run clicked the harness window's menu («Application Edit») and the stash never changed,
    /// which looked like "the tab row does not switch" for a long time.
    private static bool EnsureForeground(out string reason)
    {
        reason = "";
        var window = GameFocus.FindGameWindow();
        if (window == IntPtr.Zero)
        {
            reason = "the game window was not found";
            return false;
        }
        if (GameFocus.IsForeground(window))
        {
            return true;
        }
        if (!GameFocus.ForceBring())
        {
            reason = "the game could not be brought to the front";
            return false;
        }
        Thread.Sleep(220);
        if (!GameFocus.IsForeground(window))
        {
            reason = "another window kept the focus";
            return false;
        }
        return true;
    }
    private const int LeftArrowX = 26;
    private const int RightArrowX = 798;

    /// Click one of the strip arrows, refusing when the game is not the foreground window: a click then lands in
    /// another application, which is what made earlier runs look like "the arrow does nothing".
    private static bool ClickArrow(int x, out string reason)
    {
        if (!EnsureForeground(out reason))
        {
            return false;
        }
        StashTabs.ClickAt(x, ArrowY);
        return true;
    }
    public static IReadOnlyList<string> Run(string outDir, int maxTabs)
    {
        var report = new List<string>();
        if (Environment.GetEnvironmentVariable("POE2CRAFT_STASH") != "1")
        {
            report.Add("REFUSED: POE2CRAFT_STASH is not 1 - the stash is only walked when asked for by name");
            return report;
        }
        if (!GameFocus.ForceBring())
        {
            report.Add("REFUSED: the game could not be brought to the front");
            return report;
        }
        Thread.Sleep(300);

        var probe = Path.Combine(outDir, "walk-open.png");

        // The stash toggles, so it is opened only when the title is NOT readable. Everything happens in this one
        // process: a separate script loses the foreground between calls, and then the clicks land in whatever window is
        // on top - which is exactly why earlier walks captured the same page ten times.
        for (var attempt = 0; attempt < 2; attempt++)
        {
            if (!EnsureForeground(out var focusReason))
            {
                report.Add($"REFUSED: {focusReason}");
                return report;
            }
            StashOpener.Shot(probe);
            var current = OcrText(probe, 240, 70, 300, 70);
            if (current.Contains(ExpectedTitle, StringComparison.Ordinal))
            {
                report.Add("panel: open (title read by OCR)");
                break;
            }
            report.Add($"panel: closed (read «{current.Trim()}»), looking for the stash label");
            var opened = StashOpener.Run(Path.Combine(outDir, "walk-point.ini"),
                Path.Combine(outDir, "walk-before.png"), probe);
            foreach (var line in opened)
            {
                report.Add("open: " + line);
            }
            Thread.Sleep(400);
        }
        StashOpener.Shot(probe);
        if (!OcrText(probe, 240, 70, 300, 70).Contains(ExpectedTitle, StringComparison.Ordinal))
        {
            report.Add("REFUSED: the stash panel is still not on screen");
            return report;
        }

        var pages = new List<Page>();
        var previousPanel = Array.Empty<byte>();
        var visited = new HashSet<string>(StringComparer.Ordinal);
        var index = 0;

        // The strip walks left and right with two arrows at its ends, measured on the live client:
        //   left arrow  at 22..30,147  - clicking it shifted the labels from RAZLOM|BEZDNA|GEMS to
        //                               EXPEDITION|RAZLOM|BEZDNA, then to FRAGMENTS|RUNES|EXPEDITION;
        //   right arrow at 850,147     - inactive while the strip sits at its right end, which is why every earlier
        //                               test of "the arrow does not scroll" was wrong: there was nothing to scroll to.
        // So the walk first goes to the left end, then click every label it can see and step right with the arrow.
        for (var step = 0; step < 12; step++)
        {
            if (!ClickArrow(LeftArrowX, out var leftReason))
            {
                report.Add("stop: " + leftReason);
                break;
            }
            Thread.Sleep(320);
        }
        report.Add("strip: moved to the left end");

        var idlePasses = 0;
        var scrolls = 0;
        while (index < maxTabs && scrolls <= 12 && idlePasses < 2)
        {
            var stripFrame = Path.Combine(outDir, $"walk-strip-{scrolls}.png");
            StashOpener.Shot(stripFrame);
            var labels = ReadRows(stripFrame, StripLeft, StripTop, StripWidth, StripHeight);
            report.Add($"strip pass {scrolls}: {labels.Count} labels read");
            var clicked = 0;

            foreach (var label in labels)
            {
                if (index >= maxTabs)
                {
                    break;
                }
                var name = Clean(label.Text);
                if (name.Length == 0 || visited.Contains(name))
                {
                    continue;
                }
                visited.Add(name);
                if (!EnsureForeground(out var focusReason))
                {
                    report.Add($"stop: {focusReason} - a click now would land in another window");
                    return report;
                }
                StashTabs.ClickAt(label.X, label.Y);
                Thread.Sleep(620);
                index++;
                clicked++;
                var path = Path.Combine(outDir, $"tab-{index:d2}-{name}.png");
                StashOpener.Shot(path);
                var panel = PanelCrop(path);
                var diff = previousPanel.Length == 0 ? -1 : MeanDiff(previousPanel, panel);
                previousPanel = panel;
                pages.Add(new Page(name, path, diff));
                report.Add($"tab {index} «{name}» at {label.X},{label.Y}: "
                    + (diff < 0 ? "first page" : $"panel diff {diff:F1}"));
            }

            idlePasses = clicked == 0 ? idlePasses + 1 : 0;

            // The right arrow sits just past the last visible label, so its position moves with the strip. It is
            // searched by trying a few offsets and keeping the one that actually changes the labels - the same
            // "verify, do not assume" rule as everywhere else here.
            var before = string.Join("|", labels.Select(label => Clean(label.Text)).OrderBy(name => name));
            var advanced = false;
            if (labels.Count > 0)
            {
                var rightmost = labels.Max(label => label.X);
                foreach (var offset in new[] { RightArrowX - rightmost })
                {
                    if (!ClickArrow(rightmost + offset, out var rightReason))
                    {
                        report.Add("stop: " + rightReason);
                        break;
                    }
                    Thread.Sleep(480);
                    var checkFrame = Path.Combine(outDir, $"walk-check-{scrolls}.png");
                    StashOpener.Shot(checkFrame);
                    var now = ReadRows(checkFrame, StripLeft, StripTop, StripWidth, StripHeight);
                    var after = string.Join("|", now.Select(label => Clean(label.Text)).OrderBy(name => name));
                    report.Add($"arrow: tried offset {offset} at {rightmost + offset},{ArrowY}");
                    if (after.Length > 0 && after != before)
                    {
                        advanced = true;
                        report.Add("arrow: the labels moved, so this offset is the right arrow");
                        break;
                    }
                }
            }
            scrolls++;
            if (!advanced)
            {
                report.Add("strip: no offset advanced the strip - the right end is reached");
                idlePasses = 2;
            }
        }

        LastPages = pages;
        var changed = pages.Count(page => page.PanelDiff > 1.0);
        report.Add($"RESULT: {pages.Count} pages captured, {changed} of them differ from the previous page");
        if (pages.Count > 1 && changed == 0)
        {
            report.Add("WARNING: no page differed - the clicks did not switch tabs, so these captures are duplicates");
        }
        return report;
    }

    /// <summary>Lines with their click centres inside a region of the frame, read by OCR.</summary>
    private static List<(string Text, int X, int Y)> ReadRows(string frame, int left, int top, int width, int height)
    {
        var rows = new List<(string, int, int)>();
        var json = RunOcr(frame, left, top, width, height);
        if (json is null)
        {
            return rows;
        }
        foreach (var line in json.Value.GetProperty("lines").EnumerateArray())
        {
            var text = line.GetProperty("text").GetString() ?? "";
            var h = line.GetProperty("h").GetInt32();
            var w = line.GetProperty("w").GetInt32();
            if (h < 10 || w < 6)
            {
                continue;
            }
            rows.Add((text, left + line.GetProperty("x").GetInt32() + w / 2,
                top + line.GetProperty("y").GetInt32() + h / 2));
        }
        return rows;
    }

    private static JsonElement? RunOcr(string frame, int left, int top, int width, int height)
    {
        try
        {
            var root = StashOpener.ProjectRoot();
            var script = Path.Combine(root, "tools", "ocr.ps1");
            if (!File.Exists(script))
            {
                Log.Write("walk: ocr.ps1 not found under " + root);
                return null;
            }
            var start = new ProcessStartInfo
            {
                FileName = "powershell",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
                StandardOutputEncoding = System.Text.Encoding.UTF8,
                StandardErrorEncoding = System.Text.Encoding.UTF8,
            };
            foreach (var argument in new[]
            {
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-Path", frame,
                "-Left", left.ToString(), "-Top", top.ToString(),
                "-Width", width.ToString(), "-Height", height.ToString(),
            })
            {
                start.ArgumentList.Add(argument);
            }
            using var process = Process.Start(start);
            if (process is null)
            {
                return null;
            }
            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit();
            var jsonLine = output.Split('\n')
                .LastOrDefault(line => line.TrimStart().StartsWith("{", StringComparison.Ordinal));
            if (string.IsNullOrWhiteSpace(jsonLine))
            {
                Log.Write("walk: ocr produced no JSON: " + output.Trim());
                return null;
            }
            return JsonDocument.Parse(jsonLine).RootElement.Clone();
        }
        catch (Exception error)
        {
            Log.Write("walk: ocr failed: " + error.Message);
            return null;
        }
    }

    private static string OcrText(string frame, int left, int top, int width, int height)
    {
        var json = RunOcr(frame, left, top, width, height);
        if (json is null)
        {
            return "";
        }
        var parts = new List<string>();
        foreach (var line in json.Value.GetProperty("lines").EnumerateArray())
        {
            parts.Add(line.GetProperty("text").GetString() ?? "");
        }
        return string.Join(" ", parts);
    }

    private static string Clean(string text)
    {
        var builder = new System.Text.StringBuilder();
        foreach (var character in text)
        {
            builder.Append(char.IsLetterOrDigit(character) ? character : ' ');
        }
        return string.Join("", builder.ToString().Split(' ', StringSplitOptions.RemoveEmptyEntries));
    }

    private static byte[] PanelCrop(string path)
    {
        try
        {
            using var bitmap = new System.Drawing.Bitmap(path);
            using var crop = bitmap.Clone(new System.Drawing.Rectangle(60, 270, 760, 700), bitmap.PixelFormat);
            using var stream = new MemoryStream();
            crop.Save(stream, System.Drawing.Imaging.ImageFormat.Png);
            return stream.ToArray();
        }
        catch
        {
            return Array.Empty<byte>();
        }
    }

    /// Mean absolute difference of two PNG crops, compared as PIXELS.
    ///
    /// The first version sampled the compressed bytes, and a PNG re-encodes whole blocks when one pixel changes - so
    /// every pair of pages looked different and eleven copies of the same page were reported as eleven tabs. The
    /// images are decoded and sampled on a grid here, which is the only way this number means anything.
    private static double MeanDiff(byte[] first, byte[] second)
    {
        try
        {
            using var a = new System.Drawing.Bitmap(new MemoryStream(first));
            using var b = new System.Drawing.Bitmap(new MemoryStream(second));
            if (a.Width != b.Width || a.Height != b.Height)
            {
                return 255;
            }
            double total = 0;
            var count = 0;
            for (var y = 0; y < a.Height; y += 9)
            {
                for (var x = 0; x < a.Width; x += 9)
                {
                    var left = a.GetPixel(x, y);
                    var right = b.GetPixel(x, y);
                    total += Math.Abs(left.R - right.R) + Math.Abs(left.G - right.G) + Math.Abs(left.B - right.B);
                    count++;
                }
            }
            return count == 0 ? 0 : total / count / 3.0;
        }
        catch (Exception error)
        {
            Log.Write("walk: could not compare pages: " + error.Message);
            return 0;
        }
    }
}
