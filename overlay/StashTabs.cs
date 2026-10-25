using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Poe2CraftOverlay;

/// <summary>
/// Clicks through the stash tabs that are already on screen, and proves each click by comparing frames.
///
/// This is the safe half of the clicking question: a tab is not an item, so pressing it cannot pick anything up,
/// sell it or drop it. Everything else stays forbidden - the grid is never clicked.
///
/// The strip is located from the panel title: the «Тайник» title is matched first (score above 0.9 on a live
/// client), and the tab row sits just under it. That is why no screen coordinate is hard-coded: the panel is found
/// in the current frame, and the tabs follow from where it actually is.
///
/// Limits: one pass, at most <see cref="MaxTabs"/> tab clicks, a hard timeout, and an abort the moment the stash
/// panel stops being on screen.
/// </summary>
public static class StashTabs
{
    public const int MaxTabs = 5;
    public const int TimeoutSeconds = 40;

    [DllImport("user32.dll")]
    private static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    private static extern void mouse_event(uint flags, int dx, int dy, uint data, UIntPtr extra);

    private const uint LeftDown = 0x0002;
    private const uint LeftUp = 0x0004;
    private const uint Move = 0x0001;

    /// <summary>Tab candidate positions, derived from the title's position in the current frame.</summary>
    /// <param name="titleX">Centre X of the panel title, in frame pixels.</param>
    /// <param name="titleY">Centre Y of the panel title, in frame pixels.</param>
    public static IReadOnlyList<(int X, int Y)> TabStrip(int titleX, int titleY, int frameWidth)
    {
        var points = new List<(int X, int Y)>();
        // The tab row sits about 40 px under the title's centre; the strip runs from the panel's left edge (the
        // title is centred over a panel about 800 px wide) to the right of the last tab.
        var rowY = titleY + 41;
        var left = Math.Max(8, titleX - 355);
        var step = 96;
        for (var index = 0; index < MaxTabs; index++)
        {
            var x = left + 30 + index * step;
            if (x > frameWidth - 8)
            {
                break;
            }
            points.Add((x, rowY));
        }
        return points;
    }

    /// One click at a screen point, preceded by a motion nudge so the game registers the pointer. Used by the walk:
    /// a tab is not an item, so this cannot pick anything up.
    public static void ClickAt(int x, int y)
    {
        SetCursorPos(x, y);
        mouse_event(Move, 1, 0, 0, UIntPtr.Zero);
        Thread.Sleep(25);
        mouse_event(Move, -1, 0, 0, UIntPtr.Zero);
        Thread.Sleep(110);
        mouse_event(LeftDown, 0, 0, 0, UIntPtr.Zero);
        Thread.Sleep(45);
        mouse_event(LeftUp, 0, 0, 0, UIntPtr.Zero);
    }
    public static IReadOnlyList<string> Run(string outDir)
    {
        var report = new List<string>();
        var watch = Stopwatch.StartNew();
        if (Environment.GetEnvironmentVariable("POE2CRAFT_STASH") != "1")
        {
            report.Add("REFUSED: POE2CRAFT_STASH is not 1 - tabs are only clicked when asked for by name");
            return report;
        }
        if (!GameFocus.ForceBring())
        {
            report.Add("REFUSED: the game could not be brought to the front");
            return report;
        }
        Thread.Sleep(250);

        var before = Path.Combine(outDir, "tabs-before.png");
        StashOpener.Shot(before);
        var title = StashOpener.FindTemplate(before, "stash-title.png", new[] { 0.0, 0.0, 0.35, 0.25 });
        if (title is null)
        {
            report.Add("REFUSED: the stash panel title was not found, so the stash is not open");
            return report;
        }
        report.Add($"panel: title at {title.Value.X},{title.Value.Y} (score {title.Value.Score:F2})");

        var previous = StashOpener.LoadBytes(before);
        var clicked = 0;
        foreach (var (x, y) in TabStrip(title.Value.X, title.Value.Y, StashOpener.ScreenWidth()))
        {
            if (clicked >= MaxTabs || watch.Elapsed.TotalSeconds > TimeoutSeconds)
            {
                break;
            }
            SetCursorPos(x, y);
            // A motion message so the game sees the pointer arrive; no button yet.
            mouse_event(Move, 1, 0, 0, UIntPtr.Zero);
            Thread.Sleep(30);
            mouse_event(Move, -1, 0, 0, UIntPtr.Zero);
            Thread.Sleep(120);
            mouse_event(LeftDown, 0, 0, 0, UIntPtr.Zero);
            Thread.Sleep(40);
            mouse_event(LeftUp, 0, 0, 0, UIntPtr.Zero);
            clicked++;
            Thread.Sleep(320);

            var after = Path.Combine(outDir, $"tabs-tab{clicked}.png");
            StashOpener.Shot(after);
            var now = StashOpener.LoadBytes(after);
            var changed = StashOpener.ChangedShare(previous, now);
            previous = now;
            report.Add($"tab {clicked}: clicked {x},{y} -> {changed:P1} of the frame changed");

            // The panel must survive every click; if the title is gone, something other than a tab was hit.
            if (StashOpener.FindTemplate(after, "stash-title.png", new[] { 0.0, 0.0, 0.35, 0.25 }) is null)
            {
                report.Add("ABORT: the stash panel is no longer on screen after that click");
                break;
            }
        }

        report.Add($"RESULT: {clicked} tab clicks in {watch.ElapsedMilliseconds} ms (cap {MaxTabs} / {TimeoutSeconds} s)");
        return report;
    }
}
