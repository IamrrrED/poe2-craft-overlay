using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Poe2CraftOverlay;

/// <summary>
/// Reads what the player already owns and asks the engine to judge it - value-neutral by design.
///
/// The line this draws: the sweep may READ and may NAVIGATE. It may never change what the character owns, which
/// means no action that picks up, moves, sells, buys, crafts or destroys anything. Reading is hovering plus Ctrl+C.
/// Navigating is the inventory key, and - only inside a hideout, where a stray click cannot pull a monster or walk
/// the character into a pack - clicks on stash tabs and on an item in the grid, each of which merely selects or
/// moves the pointer within a panel the player already opened.
///
/// Hard limits: one sweep per invocation, at most <see cref="MaxReads"/> reads and <see cref="MaxClicks"/> clicks,
/// a hard timeout, a refusal without POE2CRAFT_INSPECT=1, a refusal while a panel is running, an abort when the
/// foreground window stops being the game, and an abort when Escape is pressed.
/// </summary>
public static class Inspect
{
    public const int MaxReads = 40;
    public const int MaxClicks = 8;
    public const int TimeoutSeconds = 90;
    private const int SettleMs = 140;

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
    private static extern void mouse_event(uint flags, int dx, int dy, uint data, UIntPtr extra);

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

    private const uint LeftDown = 0x0002;
    private const uint LeftUp = 0x0004;
    private const int VK_I = 0x49;
    private const int VK_ESCAPE = 0x1B;

    public sealed record Read(string Text, string Name, int Attempt);

    public static IReadOnlyList<Read> LastReads { get; private set; } = Array.Empty<Read>();
    public static ZoneInfo? LastZone { get; private set; }

    /// <summary>Where the sweep looks for items: equipped slots and the inventory grid, right side then left.</summary>
    public static IReadOnlyList<(int X, int Y)> ReadPoints(int left, int top, int width, int height)
    {
        var points = new List<(int, int)>();
        if (width < 320 || height < 240)
        {
            return points;
        }

        double[][] regions =
        {
            new[] { 0.70, 0.86, 0.10, 0.26 },
            new[] { 0.68, 0.86, 0.40, 0.58 },
            new[] { 0.14, 0.30, 0.10, 0.26 },
            new[] { 0.14, 0.32, 0.40, 0.58 },
        };
        foreach (var region in regions)
        {
            double[] xs = { region[0], (region[0] + region[1]) / 2, region[1] };
            double[] ys = { region[2], (region[2] + region[3]) / 2, region[3] };
            foreach (var fractionY in ys)
            {
                foreach (var fractionX in xs)
                {
                    points.Add((left + (int)Math.Round(width * fractionX), top + (int)Math.Round(height * fractionY)));
                    if (points.Count >= MaxReads)
                    {
                        return points;
                    }
                }
            }
        }
        return points;
    }

    /// <summary>
    /// Is this point on the panel and outside the world? A click in the world can move the character or pull a
    /// monster; inside the panel it can only select a slot or a tab. The inventory occupies the left or the right
    /// sixth of the screen, and its grid sits between 20 % and 62 % of the height.
    /// </summary>
    public static bool IsPanelPoint(int x, int y, int left, int top, int width, int height)
    {
        var fractionX = (x - left) / (double)width;
        var fractionY = (y - top) / (double)height;
        var onRight = fractionX >= 0.66 && fractionX <= 0.99;
        var onLeft = fractionX >= 0.02 && fractionX <= 0.34;
        return (onRight || onLeft) && fractionY >= 0.08 && fractionY <= 0.64;
    }

    /// <summary>
    /// The only clicks the sweep may make: the stash tab strip.
    ///
    /// Grid clicks were removed on 2026-10-25 after one nearly dropped an item: a click on a slot picks the item up,
    /// and the second click that was meant to put it back can land on empty ground and drop it. A tab click cannot
    /// move an item - it switches which page is shown - so it stays, and nothing else does.
    /// </summary>
    public static IReadOnlyList<(int X, int Y, bool IsGrid)> ClickPoints(int left, int top, int width, int height)
    {
        var points = new List<(int X, int Y, bool IsGrid)>();
        if (width < 320 || height < 240)
        {
            return points;
        }
        // Tab strip of the right-hand panel: the row the tabs live on, measured on a live client. `false` means
        // "not a grid click" and is asserted in the runner: no grid click may ever exist again.
        double[] tabXs = { 0.74, 0.80, 0.86 };
        foreach (var fractionX in tabXs)
        {
            points.Add((left + (int)Math.Round(width * fractionX), top + (int)Math.Round(height * 0.115), false));
        }
        return points;
    }

    /// <summary>Run one sweep and return the report lines. Never throws.</summary>
    public static IReadOnlyList<string> Run(bool allowClicks)
    {
        var report = new List<string>();
        var watch = Stopwatch.StartNew();
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

        // The zone decides whether clicks are allowed at all: in a hideout a stray click cannot start a fight.
        var logPath = ZoneFromLog.Find();
        var zone = logPath is null ? null : ZoneFromLog.Read(logPath);
        LastZone = zone;
        var inHideout = zone?.IsHideout == true;
        var clicksAllowed = allowClicks && inHideout;
        report.Add(zone is null
            ? "zone: unknown (the log was not found), so clicks stay disabled"
            : "zone: " + zone.Describe());
        if (allowClicks && !inHideout)
        {
            report.Add("clicks REFUSED: clicks are only allowed inside a hideout");
        }

        GetCursorPos(out var savedCursor);
        var savedClipboard = ContainsText() ? Clipboard.GetText() : null;
        var reads = new List<Read>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var attempts = 0;
        var clicks = 0;
        var aborted = "";

        try
        {
            SetForegroundWindow(window);
            Thread.Sleep(250);

            // Read first, press keys only if that found nothing. The inventory key is a TOGGLE: pressing it when
            // the panel is already open closes it, and the first version of this sweep did exactly that and then
            // found no items at all in 36 attempts while the items were sitting behind a closed panel.
            void ReadPass(string stage)
            {
                foreach (var (x, y) in ReadPoints(rect.Left, rect.Top, width, height))
                {
                    if (attempts >= MaxReads || watch.Elapsed.TotalSeconds > TimeoutSeconds)
                    {
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
                    if (!ProbeCapture.LooksLikeItem(text) || !seen.Add(text!))
                    {
                        continue;
                    }
                    reads.Add(new Read(text!, ProbeCapture.ItemName(text), attempts));
                    report.Add($"read: «{reads[^1].Name}» at {x},{y} ({text!.Length} characters, {stage}, attempt {attempts})");
                }
            }

            ReadPass("panels as they were");
            if (reads.Count == 0 && watch.Elapsed.TotalSeconds < TimeoutSeconds)
            {
                PressKey(VK_I, 0x17);
                report.Add("inventory: nothing was readable, so I was pressed once (it opens the panel, or closes it "
                    + "if it was already open)");
                Thread.Sleep(320);
                ReadPass("after I");
            }

            if (clicksAllowed)
            {
                foreach (var (x, y, isGrid) in ClickPoints(rect.Left, rect.Top, width, height))
                {
                    if (clicks >= MaxClicks || watch.Elapsed.TotalSeconds > TimeoutSeconds)
                    {
                        break;
                    }
                    if (GetForegroundWindow() != window)
                    {
                        aborted = "the game stopped being the foreground window";
                        break;
                    }
                    // Nothing in this loop may ever touch a slot. The check is not decoration: on 2026-10-25 a grid
                    // click picked an item up and the click meant to put it back nearly dropped it on the ground.
                    if (isGrid)
                    {
                        report.Add($"click REFUSED at {x},{y}: grid clicks are forbidden (an item can be dropped)");
                        continue;
                    }
                    if (!IsPanelPoint(x, y, rect.Left, rect.Top, width, height))
                    {
                        report.Add($"click REFUSED at {x},{y}: that point is in the world, not in a panel");
                        continue;
                    }

                    SetCursorPos(x, y);
                    Thread.Sleep(90);
                    ClickOnce();
                    clicks++;
                    Thread.Sleep(240);
                    report.Add($"click: tab {x},{y} (hideout only; tabs cannot move an item)");
                }
            }
        }
        catch (Exception error)
        {
            aborted = error.Message;
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

        LastReads = reads;
        if (aborted.Length > 0)
        {
            report.Add("ABORTED: " + aborted);
        }
        report.Add($"RESULT: {reads.Count} unique items read in {attempts} attempts, {clicks} clicks, "
            + $"{watch.ElapsedMilliseconds} ms");
        report.Add($"limits: {MaxReads} reads / {MaxClicks} clicks / {TimeoutSeconds} s; clicks "
            + (clicksAllowed ? "enabled (hideout, panel points only)"
                : inHideout ? "disabled by the caller" : "disabled (not in a hideout)"));
        return report;
    }

    private static void ClickOnce()
    {
        mouse_event(LeftDown, 0, 0, 0, UIntPtr.Zero);
        Thread.Sleep(40);
        mouse_event(LeftUp, 0, 0, 0, UIntPtr.Zero);
    }

    private static void PressKey(int virtualKey, byte scanCode)
    {
        const uint KeyUp = 0x0002;
        keybd_event((byte)virtualKey, scanCode, 0, UIntPtr.Zero);
        Thread.Sleep(30);
        keybd_event((byte)virtualKey, scanCode, KeyUp, UIntPtr.Zero);
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
