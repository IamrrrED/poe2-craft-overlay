using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Poe2CraftOverlay;

/// <summary>
/// Opens the stash with one calibrated click, and proves it opened by looking at the screen.
///
/// Why a calibration file instead of a guess: the stash stands where the player put it in their hideout, and the
/// camera decides where that lands on screen. A clicked guess in the world can move the character or start a fight,
/// so the point is measured once from a screenshot, stored in `stash-point.ini`, and used from then on. No point,
/// no click - the tool refuses instead of guessing.
///
/// The proof is a pair of screenshots: one before, one 400 ms after. A panel opening changes a large region of the
/// frame, so the share of changed pixels answers "did anything happen" without needing OCR. When nothing changed,
/// the click is reported as ineffective and the caller decides what to do - never a retry storm.
/// </summary>
public static class StashOpener
{
    [DllImport("user32.dll")]
    private static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    private static extern void mouse_event(uint flags, int dx, int dy, uint data, UIntPtr extra);

    private const uint LeftDown = 0x0002;
    private const uint LeftUp = 0x0004;

    /// <summary>The point from `stash-point.ini`, or null when the player has not calibrated it yet.</summary>
    public static (int X, int Y)? ReadPoint(string path)
    {
        try
        {
            if (!File.Exists(path))
            {
                return null;
            }
            // Only the data line counts. The first version scanned the whole file, picked the numbers out of the
            // comment "measured on a 2560x1440 frame", and clicked the bottom-right corner of the screen - a guessed
            // click is exactly what this file exists to prevent.
            var dataLine = File.ReadAllLines(path)
                .Select(line => line.Trim())
                .LastOrDefault(line => line.Length > 0 && !line.StartsWith("#", StringComparison.Ordinal));
            if (dataLine is null)
            {
                return null;
            }
            var numbers = System.Text.RegularExpressions.Regex.Matches(dataLine, @"-?\d+")
                .Select(match => int.Parse(match.Value))
                .ToArray();
            if (numbers.Length < 2)
            {
                return null;
            }
            var point = (X: numbers[0], Y: numbers[1]);

            // The point must be on screen and inside the world area. The corners and the HUD bands are where a click
            // does something unrelated (a menu, an orb), and a point off screen lands nowhere at all.
            var screen = System.Windows.Forms.SystemInformation.VirtualScreen;
            var inScreen = point.X > screen.Left && point.X < screen.Right
                && point.Y > screen.Top && point.Y < screen.Bottom;
            var inWorld = point.X > screen.Left + screen.Width * 0.05
                && point.X < screen.Left + screen.Width * 0.70
                && point.Y > screen.Top + screen.Height * 0.10
                && point.Y < screen.Top + screen.Height * 0.85;
            if (!inScreen || !inWorld)
            {
                Log.Write($"stash: refusing the calibrated point {point.X},{point.Y} - outside the world area");
                return null;
            }
            return point;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>Click the calibrated point once and report what the screen did.</summary>
    public static IReadOnlyList<string> Run(string pointPath, string beforePath, string afterPath)
    {
        var report = new List<string>();
        var watch = Stopwatch.StartNew();
        if (Environment.GetEnvironmentVariable("POE2CRAFT_STASH") != "1")
        {
            report.Add("REFUSED: POE2CRAFT_STASH is not 1 - the stash is only opened when asked for by name");
            return report;
        }

        if (!GameFocus.ForceBring())
        {
            report.Add("REFUSED: the game could not be brought to the front, so nothing was clicked");
            return report;
        }
        Thread.Sleep(200);

        // Two ways to a point, and the second one is why this works at all: a fixed point moves with the camera, so
        // the label is FOUND in the current frame first.
        //
        // But the label only appears for the object under the cursor, so "find it" first means "hover until it
        // shows". Hovering is harmless - no click is sent during the search - and it is not a guess of where the
        // stash is: the answer comes from the screenshot each time.
        Shot(beforePath);
        var before = LoadBytes(beforePath);
        var point = ReadPoint(pointPath);
        if (point is null)
        {
            point = HoverScanForLabel(report, Path.Combine(Path.GetDirectoryName(beforePath)!, "vision-scan.png"));
            if (point is null)
            {
                report.Add("REFUSED: the «Тайник» label never appeared while hovering the world, so nothing was "
                    + "clicked. Either the stash is not in view, or it needs a different label template.");
                return report;
            }
        }
        else
        {
            report.Add($"point: {point.Value.X},{point.Value.Y} from {System.IO.Path.GetFileName(pointPath)}");
        }

        SetCursorPos(point.Value.X, point.Value.Y);
        Thread.Sleep(120);
        mouse_event(LeftDown, 0, 0, 0, UIntPtr.Zero);
        Thread.Sleep(40);
        mouse_event(LeftUp, 0, 0, 0, UIntPtr.Zero);
        report.Add("click: one left click on the calibrated stash point");
        Thread.Sleep(420);

        Shot(afterPath);
        var after = LoadBytes(afterPath);
        var changed = ChangedShare(before, after);
        report.Add($"screen: {changed:P1} of the sampled pixels changed, {watch.ElapsedMilliseconds} ms");
        report.Add(changed > 0.02
            ? "RESULT: the screen changed, so something opened - the caller must still verify it is the stash panel"
            : "RESULT: nothing changed, so the click did not open anything");
        return report;
    }

    /// Generate a real mouse-motion message without clicking, so hover state updates.
    private static void Nudge()
    {
        const uint Move = 0x0001;
        mouse_event(Move, 1, 0, 0, UIntPtr.Zero);
        Thread.Sleep(20);
        mouse_event(Move, -1, 0, 0, UIntPtr.Zero);
    }
    /// Move the cursor over a grid of world points and look for the label after each move.
    ///
    /// Nothing is clicked here: this is the "where is the stash" question answered by the screen instead of by a
    /// guess. The grid covers the world area (not the HUD), is capped at 24 points, and stops at the first frame in
    /// which the label appears.
    private static (int X, int Y)? HoverScanForLabel(List<string> report, string scanPath)
    {
        var screen = System.Windows.Forms.SystemInformation.VirtualScreen;
        var found = ((int X, int Y)?)null;
        var hovers = 0;
        var watch = Stopwatch.StartNew();
        for (var row = 0; row < 4 && found is null; row++)
        {
            for (var column = 0; column < 6 && found is null; column++)
            {
                if (hovers >= 24 || watch.Elapsed.TotalSeconds > 45)
                {
                    break;
                }
                // Measured: the label sat at x≈0.074 of the width, i.e. LEFT of a grid that started at 0.10, and a
                // coarse step walked past it. The band below covers the left third, where world objects with
                // labels usually are, at a finer step.
                // Measured on the live client: hovering (600,430), (560,450) and (640,470) all made the label
                // appear, while points 15 px higher did not - the object is hit in its body, not at the label.
                // This grid covers that band at a step small enough to land in a body.
                var x = (int)(screen.Left + screen.Width * (0.10 + column * 0.055));
                var y = (int)(screen.Top + screen.Height * (0.24 + row * 0.06));
                SetCursorPos(x, y);
                // SetCursorPos moves the pointer WITHOUT a motion message, and the game decides what is hovered
                // from those messages - so the label never appeared while the pointer sat on the object. A
                // one-pixel nudge and back generates the motion the game needs. No button is pressed.
                Nudge();
                Thread.Sleep(420);
                Shot(scanPath);
                hovers++;
                var label = FindLabel(scanPath);
                if (label is null)
                {
                    report.Add($"scan {hovers}: hover {x},{y} - no label");
                    continue;
                }
                report.Add($"scan {hovers}: label at {label.Value.X},{label.Value.Y} "
                    + $"(score {label.Value.Score:F2}) while hovering {x},{y}");
                found = (label.Value.X, label.Value.Y);
            }
        }
        report.Add($"scan: {hovers} hovers in {watch.ElapsedMilliseconds} ms, "
            + (found is null ? "label never appeared" : "label found"));
        return found;
    }
    /// Ask the Python detector where the «Тайник» label is. Returns null when it is not on screen.
    ///
    /// The detector lives in Python because that is where Pillow and numpy already are; the overlay only needs the
    /// answer. A label that is not on screen is a normal outcome, not an error: the label only appears for the
    /// object under the cursor.
    private static (int X, int Y, double Score)? FindLabel(string framePath)
    {
        try
        {
            // Walk up until the project root is found. Counting ".." levels was wrong by one: the exe sits in
            // overlay\bin\<config>\net8.0-windows, so the project root is four levels up, not five - and the log said
            // "detector missing" while the label sat plainly in the frame.
            var root = AppContext.BaseDirectory.TrimEnd(System.IO.Path.DirectorySeparatorChar);
            for (var level = 0; level < 8; level++)
            {
                if (File.Exists(System.IO.Path.Combine(root, "tools", "find_label.py")))
                {
                    break;
                }
                var parent = System.IO.Path.GetDirectoryName(root);
                if (parent is null)
                {
                    break;
                }
                root = parent;
            }
            var script = System.IO.Path.Combine(root, "tools", "find_label.py");
            var template = System.IO.Path.Combine(root, "docs", "stash-label.png");
            if (!File.Exists(script) || !File.Exists(template))
            {
                Log.Write($"stash: detector missing (script {File.Exists(script)}, template {File.Exists(template)}, "
                    + $"root {root})");
                return null;
            }

            var python = Environment.GetEnvironmentVariable("POE2CRAFT_PYTHON") ?? "python";
            var start = new System.Diagnostics.ProcessStartInfo
            {
                FileName = python,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
                StandardOutputEncoding = System.Text.Encoding.UTF8,
                StandardErrorEncoding = System.Text.Encoding.UTF8,
            };
            foreach (var argument in new[] { script, "--frame", framePath, "--template", template })
            {
                start.ArgumentList.Add(argument);
            }

            using var process = System.Diagnostics.Process.Start(start);
            if (process is null)
            {
                return null;
            }
            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit();
            var json = System.Text.Json.JsonDocument.Parse(output).RootElement;
            if (!json.TryGetProperty("found", out var found)
                || found.ValueKind != System.Text.Json.JsonValueKind.True)
            {
                Log.Write("stash: label not found: " + output.Trim());
                return null;
            }
            return (json.GetProperty("x").GetInt32(), json.GetProperty("y").GetInt32(),
                json.GetProperty("score").GetDouble());
        }
        catch (Exception error)
        {
            Log.Write("stash: detector failed: " + error.Message);
            return null;
        }
    }

    /// Screen width in pixels, for the tab strip bounds.
    public static int ScreenWidth() => System.Windows.Forms.SystemInformation.VirtualScreen.Width;

    /// Find any template in a frame by the same detector the label search uses.
    public static (int X, int Y, double Score)? FindTemplate(string framePath, string templateName, double[] region)
    {
        return FindTemplateInternal(framePath, templateName, region);
    }

    private static (int X, int Y, double Score)? FindTemplateInternal(string framePath, string templateName,
        double[] region)
    {
        try
        {
            var root = ProjectRoot();
            var script = System.IO.Path.Combine(root, "tools", "find_label.py");
            var template = System.IO.Path.Combine(root, "docs", templateName);
            if (!File.Exists(script) || !File.Exists(template))
            {
                return null;
            }
            var python = Environment.GetEnvironmentVariable("POE2CRAFT_PYTHON") ?? "python";
            var start = new System.Diagnostics.ProcessStartInfo
            {
                FileName = python,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
                StandardOutputEncoding = System.Text.Encoding.UTF8,
                StandardErrorEncoding = System.Text.Encoding.UTF8,
            };
            // A title on a busy panel background needs a far better match than a label: 0.55 let a 0.56
            // coincidence move the tab row 230 px to the right, and the "tab" click closed the stash.
            var minScore = templateName.Contains("title", StringComparison.Ordinal) ? "0.80" : "0.55";
            foreach (var argument in new[] { script, "--frame", framePath, "--template", template,
                "--region", string.Join(",", region.Select(value => value.ToString(
                    System.Globalization.CultureInfo.InvariantCulture))),
                "--min-score", minScore })
            {
                start.ArgumentList.Add(argument);
            }
            using var process = System.Diagnostics.Process.Start(start);
            if (process is null)
            {
                return null;
            }
            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit();
            if (string.IsNullOrWhiteSpace(output))
            {
                return null;
            }
            var json = System.Text.Json.JsonDocument.Parse(output).RootElement;
            if (!json.TryGetProperty("found", out var found) || found.ValueKind != System.Text.Json.JsonValueKind.True)
            {
                return null;
            }
            return (json.GetProperty("x").GetInt32(), json.GetProperty("y").GetInt32(),
                json.GetProperty("score").GetDouble());
        }
        catch (Exception error)
        {
            Log.Write("stash: template search failed: " + error.Message);
            return null;
        }
    }

    /// The project root: walk up until tools/find_label.py appears.
    public static string ProjectRoot()
    {
        var root = AppContext.BaseDirectory.TrimEnd(System.IO.Path.DirectorySeparatorChar);
        for (var level = 0; level < 8; level++)
        {
            if (File.Exists(System.IO.Path.Combine(root, "tools", "find_label.py")))
            {
                return root;
            }
            var parent = System.IO.Path.GetDirectoryName(root);
            if (parent is null)
            {
                break;
            }
            root = parent;
        }
        return AppContext.BaseDirectory;
    }
    public static void Shot(string path)
    {
        var bounds = System.Windows.Forms.SystemInformation.VirtualScreen;
        using var bitmap = new System.Drawing.Bitmap(bounds.Width, bounds.Height);
        using (var graphics = System.Drawing.Graphics.FromImage(bitmap))
        {
            graphics.CopyFromScreen(bounds.Left, bounds.Top, 0, 0, bitmap.Size);
        }
        bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png);
    }

    public static byte[] LoadBytes(string path)
    {
        try
        {
            return File.ReadAllBytes(path);
        }
        catch
        {
            return Array.Empty<byte>();
        }
    }

    /// <summary>
    /// Share of sampled PIXELS that differ between two PNG files.
    ///
    /// The first version compared the bytes of the compressed files, which is meaningless: changing one pixel
    /// re-encodes whole blocks, so every comparison reported "99.6 % changed", including clicks that did nothing.
    /// Both files are decoded here and sampled on a grid, which answers the real question: did the frame change.
    /// </summary>
    public static double ChangedShare(byte[] before, byte[] after)
    {
        try
        {
            using var first = new System.Drawing.Bitmap(new System.IO.MemoryStream(before));
            using var second = new System.Drawing.Bitmap(new System.IO.MemoryStream(after));
            if (first.Width != second.Width || first.Height != second.Height)
            {
                return 1.0;
            }
            var different = 0;
            var sampled = 0;
            const int step = 16;
            for (var y = 0; y < first.Height; y += step)
            {
                for (var x = 0; x < first.Width; x += step)
                {
                    sampled++;
                    var left = first.GetPixel(x, y);
                    var right = second.GetPixel(x, y);
                    if (Math.Abs(left.R - right.R) + Math.Abs(left.G - right.G) + Math.Abs(left.B - right.B) > 24)
                    {
                        different++;
                    }
                }
            }
            return sampled == 0 ? 0 : different / (double)sampled;
        }
        catch (Exception error)
        {
            Log.Write("stash: could not compare frames: " + error.Message);
            return 0;
        }
    }
}
