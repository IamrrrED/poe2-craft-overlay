using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Poe2CraftOverlay;

/// <summary>
/// Reads what the player already owns and asks the engine what to make of it.
///
/// The one rule that shapes all of it: <b>no clicks, ever</b>. Not on an item slot, not on a stash tab. A click is
/// the only input in this game that can change what the character owns - it picks an item up, and the next click
/// can put it down somewhere else or drop it on the ground. On 2026-10-25 a grid click in the inventory nearly
/// dropped an item that way, and the customer's rule since then is absolute. Reading never needed a click: hovering
/// a slot plus Ctrl+C copies the item's text, and that is the whole vocabulary here besides one inventory key press.
///
/// Every action is written to the report with a timestamp, and the report ends with an analysis of the sequence, so
/// the run can be reviewed afterwards instead of trusted.
///
/// Hard limits: at most <see cref="MaxReads"/> hovers, <see cref="TimeoutSeconds"/> seconds, a refusal without
/// POE2CRAFT_INSPECT=1, an abort when the game loses the foreground, and an abort on Escape.
/// </summary>
public static class Inspect
{
    public const int MaxReads = 40;
    public const int TimeoutSeconds = 90;
    private const int SettleMs = 140;
    private const int VK_I = 0x49;
    private const int VK_ESCAPE = 0x1B;

    [DllImport("user32.dll")]
    private static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT point);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr window, out RECT rect);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern void keybd_event(byte virtualKey, byte scanCode, uint flags, UIntPtr extra);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public sealed record Read(string Text, string Name, int Attempt, string Where);

    /// <summary>Every action, in order, with the millisecond it happened. This is what makes a run reviewable.</summary>
    public sealed record Action(int AtMs, string What);

    public static IReadOnlyList<Read> LastReads { get; private set; } = Array.Empty<Read>();
    public static IReadOnlyList<Action> LastActions { get; private set; } = Array.Empty<Action>();
    public static ZoneInfo? LastZone { get; private set; }

    /// <summary>
    /// Hover points: equipped slots and the inventory grid, right side then left. Same regions the capture probe
    /// measured on a live 2560x1440 client - hovering is safe, so the sweep may be generous here.
    /// </summary>
    public static IReadOnlyList<(int X, int Y, string Where)> HoverPoints(int left, int top, int width, int height)
    {
        var points = new List<(int, int, string)>();
        if (width < 320 || height < 240)
        {
            return points;
        }

        (string Where, double X0, double X1, double Y0, double Y1)[] regions =
        {
            ("equipment right", 0.70, 0.86, 0.10, 0.26),
            ("inventory right", 0.68, 0.86, 0.40, 0.58),
            ("equipment left", 0.14, 0.30, 0.10, 0.26),
            ("inventory left", 0.14, 0.32, 0.40, 0.58),
        };
        foreach (var region in regions)
        {
            double[] xs = { region.X0, (region.X0 + region.X1) / 2, region.X1 };
            double[] ys = { region.Y0, (region.Y0 + region.Y1) / 2, region.Y1 };
            foreach (var fractionY in ys)
            {
                foreach (var fractionX in xs)
                {
                    points.Add((left + (int)Math.Round(width * fractionX), top + (int)Math.Round(height * fractionY),
                        region.Where));
                    if (points.Count >= MaxReads)
                    {
                        return points;
                    }
                }
            }
        }
        return points;
    }

    /// <summary>Run one sweep and return the report lines. Never throws.</summary>
    /// <param name="allowClicks">Accepted and ignored: clicks were removed from the sweep by rule (see the class
    /// comment), and the parameter stays so an older call site keeps compiling.</param>
    public static IReadOnlyList<string> Run(bool allowClicks = false)
    {
        var report = new List<string>();
        var actions = new List<Action>();
        var watch = Stopwatch.StartNew();
        void Act(string what)
        {
            actions.Add(new Action((int)watch.ElapsedMilliseconds, what));
            Log.Write($"inspect: [{watch.ElapsedMilliseconds,5} ms] {what}");
        }

        if (Environment.GetEnvironmentVariable("POE2CRAFT_INSPECT") != "1")
        {
            report.Add("REFUSED: POE2CRAFT_INSPECT is not 1 - the sweep only runs when asked for by name");
            return report;
        }

        var window = GameFocus.FindGameWindow();
        if (window == IntPtr.Zero)
        {
            report.Add("REFUSED: the game window was not found");
            return report;
        }
        if (!GetWindowRect(window, out var rect))
        {
            report.Add("REFUSED: the game window has no rectangle");
            return report;
        }
        var width = rect.Right - rect.Left;
        var height = rect.Bottom - rect.Top;
        report.Add($"game: window {rect.Left},{rect.Top} {width}x{height}");

        // The zone is informational now: clicks are gone, but knowing where the character stands explains what a
        // sweep can see (a hideout with the stash open shows more than a map with nothing open).
        var logPath = ZoneFromLog.Find();
        var zone = logPath is null ? null : ZoneFromLog.Read(logPath);
        LastZone = zone;
        report.Add(zone is null ? "zone: unknown (log not found)" : "zone: " + zone.Describe());

        var savedCursor = default(POINT);
        GetCursorPos(out savedCursor);
        var savedClipboard = ContainsText() ? Clipboard.GetText() : null;
        var reads = new List<Read>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var attempts = 0;
        var emptyHovers = 0;
        var aborted = "";
        Act($"foreground the game window {rect.Left},{rect.Top} {width}x{height}");
        Act("clicks: none, by rule - this sweep cannot pick up, move or drop anything");

        try
        {
            // Raise the game and BELIEVE ITS ANSWER. Sending keys while another window holds the focus would type
            // into that window - the first run aborted on its own foreground check having sent nothing, which is
            // the right outcome for the wrong reason: it never asked for the focus properly.
            if (!GameFocus.Bring())
            {
                aborted = "the game refused to come to the front, so nothing was sent";
                Act("abort: the game could not be focused");
            }
            else
            {
                Thread.Sleep(150);
            }

            void HoverPass(string stage)
            {
                foreach (var (x, y, where) in HoverPoints(rect.Left, rect.Top, width, height))
                {
                    if (attempts >= MaxReads || watch.Elapsed.TotalSeconds > TimeoutSeconds)
                    {
                        Act($"stop: {(attempts >= MaxReads ? "read cap" : "time cap")} reached");
                        return;
                    }
                    if (GetForegroundWindow() != window)
                    {
                        aborted = "the game stopped being the foreground window";
                        return;
                    }
                    if ((Native.GetAsyncKeyState(VK_ESCAPE) & 0x8000) != 0)
                    {
                        aborted = "Escape was pressed";
                        return;
                    }

                    attempts++;
                    SetCursorPos(x, y);
                    Thread.Sleep(SettleMs);
                    InputSender.CtrlC();
                    Thread.Sleep(SettleMs);
                    var text = Clipboard.GetText();
                    if (!ProbeCapture.LooksLikeItem(text))
                    {
                        emptyHovers++;
                        Act($"hover {x},{y} ({where}, {stage}): nothing");
                        continue;
                    }
                    if (!seen.Add(text!))
                    {
                        Act($"hover {x},{y} ({where}, {stage}): «{ProbeCapture.ItemName(text)}» already read");
                        continue;
                    }
                    reads.Add(new Read(text!, ProbeCapture.ItemName(text), attempts, where));
                    Act($"hover {x},{y} ({where}, {stage}): read «{reads[^1].Name}» ({text!.Length} characters)");
                }
            }

            if (aborted.Length == 0)
            {
                HoverPass("panels as they were");
            }
            if (aborted.Length == 0 && reads.Count == 0 && watch.Elapsed.TotalSeconds < TimeoutSeconds)
            {
                // A key, not a click: `I` toggles the inventory and cannot move an item.
                keybd_event((byte)VK_I, 0x17, 0, UIntPtr.Zero);
                Thread.Sleep(30);
                keybd_event((byte)VK_I, 0x17, 0x0002, UIntPtr.Zero);
                Act("key I: nothing was readable, pressed once (it opens the inventory, or closes it if it was open)");
                Thread.Sleep(320);
                HoverPass("after I");
            }
        }
        catch (Exception error)
        {
            aborted = error.Message;
        }
        finally
        {
            SetCursorPos(savedCursor.X, savedCursor.Y);
            Act($"cursor put back to {savedCursor.X},{savedCursor.Y}");
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
                Act("clipboard put back");
            }
            catch (Exception error)
            {
                Act("clipboard could not be put back: " + error.Message);
            }
        }

        LastReads = reads;
        LastActions = actions;
        if (aborted.Length > 0)
        {
            report.Add("ABORTED: " + aborted);
        }

        // The sequence, verbatim: what happened, in order, before any conclusion about it.
        report.Add("sequence:");
        foreach (var action in actions)
        {
            report.Add($"  [{action.AtMs,5} ms] {action.What}");
        }

        // And the analysis, kept separate so the raw sequence above can contradict it.
        var byRegion = reads.GroupBy(read => read.Where).ToDictionary(group => group.Key, group => group.Count());
        report.Add("analysis:");
        report.Add($"  hovers: {attempts} in {watch.ElapsedMilliseconds} ms, of which {emptyHovers} found nothing");
        report.Add($"  items read: {reads.Count}" + (reads.Count > 0
            ? " (" + string.Join(", ", byRegion.Select(pair => $"{pair.Key}: {pair.Value}")) + ")"
            : ""));
        if (reads.Count == 0)
        {
            report.Add("  why: no item under any hover point - the panels are most likely closed, or the character "
                + "carries and stores nothing that the regions cover");
        }
        else if (emptyHovers > attempts / 2)
        {
            report.Add($"  note: {emptyHovers} of {attempts} hover points were empty, so the regions cover more "
                + "empty space than items; the points could be tightened around the grid");
        }
        report.Add($"limits: {MaxReads} hovers / {TimeoutSeconds} s / no clicks at all");
        return report;
    }

    private static bool ContainsText()
    {
        try
        {
            return Clipboard.ContainsText();
        }
        catch
        {
            return false;
        }
    }
}
