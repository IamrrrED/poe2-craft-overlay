using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Poe2CraftOverlay;

/// <summary>
/// Reads what is inside the open stash page by hovering, without knowing the grid layout.
///
/// Why a census instead of cell coordinates: a grid can be measured, but every measurement is tied to one resolution
/// and one UI scale, and a wrong pitch silently reads the gaps between cells. Hovering has no such problem - the game
/// copies whatever is under the pointer - so the reader walks a lattice fine enough to hit every cell at least once,
/// reads with Ctrl+C, and keeps the distinct items. The price is coverage: the run stops at a cap, and the report says
/// how many positions were visited out of how many the panel offers. Partial coverage that is stated beats full
/// coverage that is assumed.
///
/// No clicks: this class has no mouse-button call at all. Nothing can be picked up, moved or dropped.
/// </summary>
public static class StashReader
{
    public const int MaxHovers = 60;
    public const int TimeoutSeconds = 90;
    public const int IdleStop = 12;
    private const int SettleMs = 130;

    [DllImport("user32.dll")]
    private static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    private static extern void mouse_event(uint flags, int dx, int dy, uint data, UIntPtr extra);

    private const uint Move = 0x0001;

    public sealed record Found(string Text, string Name, int AtX, int AtY);

    public static IReadOnlyList<Found> LastFound { get; private set; } = Array.Empty<Found>();

    /// <summary>The lattice of hover points, derived from the panel rectangle the title gives.</summary>
    public static IReadOnlyList<(int X, int Y)> Lattice(int panelLeft, int panelTop, int panelWidth, int panelHeight,
        int step)
    {
        var points = new List<(int X, int Y)>();
        // Start half a step inside the panel and skip the tab row at the top.
        for (var y = panelTop + 90; y < panelTop + panelHeight - 10; y += step)
        {
            for (var x = panelLeft + step; x < panelLeft + panelWidth - 10; x += step)
            {
                points.Add((x, y));
            }
        }
        return points;
    }

    public static IReadOnlyList<string> Run(string outDir)
    {
        var report = new List<string>();
        var watch = Stopwatch.StartNew();
        if (Environment.GetEnvironmentVariable("POE2CRAFT_STASH") != "1")
        {
            report.Add("REFUSED: POE2CRAFT_STASH is not 1 - the stash is only read when asked for by name");
            return report;
        }
        if (!GameFocus.ForceBring())
        {
            report.Add("REFUSED: the game could not be brought to the front");
            return report;
        }
        Thread.Sleep(250);

        var frame = Path.Combine(outDir, "read-before.png");
        StashOpener.Shot(frame);
        var title = StashOpener.FindTemplate(frame, "stash-title.png", new[] { 0.0, 0.0, 0.35, 0.25 });
        if (title is null)
        {
            report.Add("REFUSED: the stash panel title was not found, so the stash is not open");
            return report;
        }
        report.Add($"panel: title at {title.Value.X},{title.Value.Y} (score {title.Value.Score:F2})");

        // The panel is anchored by its title: it is centred over a panel about 720 px wide and hangs below it.
        var panelLeft = Math.Max(0, title.Value.X - 360);
        var panelTop = Math.Max(0, title.Value.Y - 40);
        const int panelWidth = 720;
        // Measured on the live frame: the stash page runs from the tab row down to the search box, about 900 px
        // at this resolution. 620 px cut most of the grid away, and the sweep hovered empty space above it.
        const int panelHeight = 900;
        // A step smaller than a cell: the cell is about 50-70 px at these resolutions, so 32 px cannot miss one.
        var lattice = Lattice(panelLeft, panelTop, panelWidth, panelHeight, 48);
        report.Add($"lattice: {lattice.Count} positions over the panel "
            + $"({panelLeft},{panelTop} {panelWidth}x{panelHeight}, step 48)");

        var found = new List<Found>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var hovered = 0;
        var idle = 0;
        var savedClipboard = Clipboard.ContainsText() ? Clipboard.GetText() : null;
        var savedCursor = default(POINT);
        GetCursorPos(out savedCursor);
        try
        {
            foreach (var (x, y) in lattice)
            {
                if (hovered >= MaxHovers || watch.Elapsed.TotalSeconds > TimeoutSeconds
                    || (found.Count > 0 && idle >= IdleStop))
                {
                    break;
                }
                hovered++;
                SetCursorPos(x, y);
                mouse_event(Move, 1, 0, 0, UIntPtr.Zero);
                Thread.Sleep(20);
                mouse_event(Move, -1, 0, 0, UIntPtr.Zero);
                Thread.Sleep(SettleMs);
                InputSender.CtrlC();
                Thread.Sleep(SettleMs);
                var text = Clipboard.GetText();
                if (!ProbeCapture.LooksLikeItem(text))
                {
                    idle++;
                    continue;
                }
                if (!seen.Add(text!))
                {
                    continue;
                }
                idle = 0;
                found.Add(new Found(text!, ProbeCapture.ItemName(text), x, y));
                report.Add($"read: «{found[^1].Name}» at {x},{y} ({text!.Length} characters)");
            }
        }
        catch (Exception error)
        {
            report.Add("FAIL: " + error.Message);
        }
        finally
        {
            SetCursorPos(savedCursor.X, savedCursor.Y);
            try
            {
                if (savedClipboard is null)
                {
                    Clipboard.Clear();
                }
                else
                {
                    Clipboard.SetText(savedClipboard);
                }
                report.Add("clipboard and cursor put back");
            }
            catch (Exception error)
            {
                report.Add("clipboard could not be put back: " + error.Message);
            }
        }

        LastFound = found;
        var coverage = lattice.Count == 0 ? 0 : hovered / (double)lattice.Count;
        report.Add($"RESULT: {found.Count} distinct items in {hovered} hovers "
            + $"({coverage:P0} of the {lattice.Count} lattice positions), {watch.ElapsedMilliseconds} ms");
        if (coverage < 0.9)
        {
            report.Add("note: coverage is partial - raise the cap or run again after switching the page");
        }
        return report;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT point);
}
