using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace Poe2CraftOverlay;

/// <summary>
/// One bounded, non-gameplay probe of the live client.
///
/// Why it exists: every check in this project either fabricates the item text or waits for a human to hover an
/// item and press Ctrl+Q. The one thing that was never verified by the program itself is "a real item under the
/// real cursor reaches the card". This closes that gap without turning the overlay into something that plays.
///
/// What it does, exhaustively:
///   * finds the game window by process name (no memory access, no injection, no overlay hooking);
///   * moves the mouse pointer over a handful of points inside the inventory panel;
///   * sends Ctrl+C (the same keys a player sends) and reads the clipboard;
///   * optionally presses "I" once to open the inventory if nothing was found;
///   * puts the cursor and the clipboard back exactly as they were.
///
/// What it never does, by construction rather than by promise:
///   * no mouse buttons at all - it cannot pick up, move, drop, sell or destroy an item;
///   * no movement, attack or skill keys - only "I" and Ctrl+C, each a fixed number of times;
///   * no loop and no repetition on success: one probe per invocation, hard timeout, a fixed attempt cap;
///   * it refuses to start unless POE2CRAFT_PROBE=1 is set explicitly, and refuses if a panel is already running
///     (two windows fighting for focus is how a probe would end up pressing keys into the wrong place).
/// </summary>
public static class ProbeCapture
{
    /// The item the last run captured, or null. The caller feeds it to the engine: a capture that never reaches
    /// the card is only half the proof.
    public static string? LastItem { get; private set; }

    public const int MaxAttempts = 12;
    public const int TimeoutSeconds = 25;
    private const int SettleMs = 150;

    private const int VK_I = 0x49;

    [DllImport("user32.dll")]
    private static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT point);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr window, out RECT rect);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr window);

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

    /// <summary>
    /// Hover points inside the inventory panel, as fractions of the client area.
    ///
    /// The inventory occupies the left third of the screen and its grid starts below the header; these nine points
    /// sit inside that region and are spread out so that a non-default resolution still lands on some slots. The
    /// list is a pure function of the window size, which is what makes it testable without the game running.
    /// </summary>
    public static IReadOnlyList<(int X, int Y)> Candidates(int left, int top, int width, int height)
    {
        var points = new List<(int, int)>();
        if (width < 320 || height < 240)
        {
            return points;
        }

        // Where the panel actually is: measured from a screenshot of a live 2560x1440 session, where the inventory
        // and the equipped items sit in the right quarter of the screen (the first version of this list assumed
        // the left third and found nothing at all). Both layouts are covered because the player can move the
        // panel: right side first, then the mirrored left side.
        double[][] regions =
        {
            // equipped items (weapon, body, rings, boots): reliable targets, an item is always worn
            new[] { 0.70, 0.86, 0.12, 0.26 },
            // the inventory grid itself
            new[] { 0.68, 0.86, 0.40, 0.58 },
            // the same two regions mirrored, for a left-hand layout
            new[] { 0.14, 0.30, 0.12, 0.26 },
            new[] { 0.14, 0.32, 0.40, 0.58 },
        };

        foreach (var region in regions)
        {
            double[] xs = { region[0], (region[0] + region[1]) / 2, region[1] };
            double[] ys = { region[2], region[3] };
            foreach (var fractionY in ys)
            {
                foreach (var fractionX in xs)
                {
                    var x = left + (int)Math.Round(width * fractionX);
                    var y = top + (int)Math.Round(height * fractionY);
                    points.Add((x, y));
                    if (points.Count >= MaxAttempts)
                    {
                        return points;
                    }
                }
            }
        }

        return points;
    }
    /// <summary>Run one probe and return the report lines. Never throws: a probe that crashes is worse than one that says why it could not run.</summary>
    public static IReadOnlyList<string> Run()
    {
        var report = new List<string>();
        var watch = Stopwatch.StartNew();
        if (Environment.GetEnvironmentVariable("POE2CRAFT_PROBE") != "1")
        {
            report.Add("REFUSED: POE2CRAFT_PROBE is not 1 - the probe only runs when asked for by name");
            return report;
        }

        // The same finder the hotkey uses: window class or exact title on the desktop, then the known process
        // names. Looking up a process name of its own was wrong - the Steam build is called PathOfExileSteam, and
        // the first run reported "the game window was not found" while the game sat in front of it.
        var window = GameFocus.FindGameWindow();
        if (window == IntPtr.Zero)
        {
            report.Add("REFUSED: the game window was not found, so there is nothing to hover");
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

        var points = Candidates(rect.Left, rect.Top, width, height);
        if (points.Count == 0)
        {
            report.Add("REFUSED: the game window is too small to place an inventory probe");
            return report;
        }
        report.Add($"candidates: {points.Count} points inside the inventory panel");

        var savedClipboard = ClipboardContainsText() ? Clipboard.GetText() : null;
        GetCursorPos(out var savedCursor);
        var attempts = 0;
        string? item = null;
        var openedInventory = false;
        try
        {
            SetForegroundWindow(window);
            Thread.Sleep(250);
            foreach (var pass in new[] { 0, 1 })
            {
                if (pass == 1)
                {
                    // The player may have left the inventory closed. One press of "I" opens it; if it was open
                    // already this closes it, which the report states rather than hides.
                    PressKey(VK_I, 0x17);
                    openedInventory = true;
                    Thread.Sleep(300);
                    report.Add("inventory: pressed I once to make sure the panel is open");
                }

                foreach (var (x, y) in points)
                {
                    if (attempts >= MaxAttempts || watch.Elapsed.TotalSeconds > TimeoutSeconds)
                    {
                        break;
                    }
                    attempts++;
                    SetCursorPos(x, y);
                    Thread.Sleep(SettleMs);
                    InputSender.CtrlC();
                    Thread.Sleep(SettleMs);
                    var text = Clipboard.GetText();
                    if (!LooksLikeItem(text))
                    {
                        continue;
                    }
                    item = text;
                    report.Add($"item: found on attempt {attempts} at {x},{y} ({text.Length} characters)");
                    break;
                }

                if (item is not null || watch.Elapsed.TotalSeconds > TimeoutSeconds)
                {
                    break;
                }
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

        if (item is null)
        {
            report.Add($"RESULT: no item under any of the {attempts} probed points"
                + (openedInventory ? " (inventory toggled once)" : ""));
        }
        else
        {
            LastItem = item;
            var name = ItemName(item);
            report.Add($"RESULT: captured «{name}» in {attempts} attempts, {watch.ElapsedMilliseconds} ms");
        }
        report.Add($"probe: {attempts} attempts, {watch.ElapsedMilliseconds} ms, cap {MaxAttempts} attempts / {TimeoutSeconds} s");
        return report;
    }

    private static void PressKey(int virtualKey, byte scanCode)
    {
        const uint KeyUp = 0x0002;
        keybd_event((byte)virtualKey, scanCode, 0, UIntPtr.Zero);
        Thread.Sleep(30);
        keybd_event((byte)virtualKey, scanCode, KeyUp, UIntPtr.Zero);
    }

    private static bool ClipboardContainsText()
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

    /// <summary>Same test the capture path uses: the game's own header, in either language.</summary>
    public static bool LooksLikeItem(string? text)
    {
        return !string.IsNullOrWhiteSpace(text)
            && (text.Contains("Rarity:", StringComparison.Ordinal)
                || text.Contains("Item Class:", StringComparison.Ordinal)
                || text.Contains("Редкость:", StringComparison.Ordinal)
                || text.Contains("Класс предмета:", StringComparison.Ordinal));
    }

    /// <summary>The item's name line: the second non-empty line, which is how both clients print it.</summary>
    public static string ItemName(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return "";
        }
        var lines = text!.Replace("\r", "").Split('\n');
        var seenRarity = false;
        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            if (trimmed.Length == 0 || trimmed == "--------")
            {
                continue;
            }
            if (!seenRarity && (trimmed.StartsWith("Rarity:", StringComparison.Ordinal)
                || trimmed.StartsWith("Редкость:", StringComparison.Ordinal)))
            {
                seenRarity = true;
                continue;
            }
            if (seenRarity)
            {
                return trimmed;
            }
        }
        return "";
    }
}
