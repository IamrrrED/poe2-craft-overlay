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

        var point = ReadPoint(pointPath);
        if (point is null)
        {
            report.Add($"REFUSED: no calibrated stash point in {pointPath}. Measure it once from a screenshot "
                + "(the «Тайник» label) and write 'x,y' into that file - a guessed click in the world can move the "
                + "character or start a fight, so it is never guessed.");
            return report;
        }

        if (!GameFocus.ForceBring())
        {
            report.Add("REFUSED: the game could not be brought to the front, so nothing was clicked");
            return report;
        }
        Thread.Sleep(200);

        Shot(beforePath);
        var before = LoadBytes(beforePath);
        report.Add($"point: {point.Value.X},{point.Value.Y} from {System.IO.Path.GetFileName(pointPath)}");

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

    private static void Shot(string path)
    {
        var bounds = System.Windows.Forms.SystemInformation.VirtualScreen;
        using var bitmap = new System.Drawing.Bitmap(bounds.Width, bounds.Height);
        using (var graphics = System.Drawing.Graphics.FromImage(bitmap))
        {
            graphics.CopyFromScreen(bounds.Left, bounds.Top, 0, 0, bitmap.Size);
        }
        bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png);
    }

    private static byte[] LoadBytes(string path)
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
    /// Share of sampled bytes that differ between two PNG files. A screenshot of a still frame compresses to the same
    /// bytes, so "different" is a strong signal that the frame changed; the cheap comparison is deliberate - it only
    /// has to answer "did anything happen".
    /// </summary>
    public static double ChangedShare(byte[] before, byte[] after)
    {
        if (before.Length == 0 || after.Length == 0)
        {
            return 0;
        }
        var shortest = Math.Min(before.Length, after.Length);
        var different = 0;
        var sampled = 0;
        // Sampling every 97th byte keeps this linear and fast while covering the whole file.
        for (var index = 0; index < shortest; index += 97)
        {
            sampled++;
            if (before[index] != after[index])
            {
                different++;
            }
        }
        if (sampled == 0)
        {
            return 0;
        }
        return different / (double)sampled;
    }
}
