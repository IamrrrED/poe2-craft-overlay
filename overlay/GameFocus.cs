using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace Poe2CraftOverlay;

/// Puts the game back in the foreground before an injected Ctrl+C.
///
/// Dragging or resizing the panel hands it the focus, so the injected keys were delivered to the panel
/// instead of the game: the clipboard stayed empty and the card never changed. Bringing the game forward
/// first makes the copy land where it belongs.
///
/// The window is looked for in two ways, in this order:
///   1. by its own window class (POEWindowClass) or its exact title. This asks the desktop, not the
///      process list, so it keeps working where the process list is restricted - it was exactly the case
///      that produced "no game window found" while the game's window was on screen;
///   2. by process name, through Process.MainWindowHandle and then the process's largest visible window.
/// Whichever found it, the log names the window and the foreground that resulted: "the panel did not
/// capture" has to be answerable from the log alone, not from a guess about which half failed.
internal static class GameFocus
{
    private const int SW_RESTORE = 9;
    private const uint GW_OWNER = 4;

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr window, int command);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr window);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr window, uint command);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr window, out Rect rect);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr window, StringBuilder text, int count);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr window, StringBuilder text, int count);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    private delegate bool EnumWindowsProc(IntPtr window, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    // The window class the game creates, and the titles both games use. The class is the reliable half;
    // the title is there for a build that renames the class, and it must match exactly so that a browser
    // tab about the game cannot be mistaken for the game.
    private const string GameWindowClass = "POEWindowClass";
    private static readonly string[] GameTitles = { "Path of Exile 2", "Path of Exile" };

    private static readonly string[] Names =
    {
        "PathOfExileSteam", "PathOfExile_x64Steam", "PathOfExile2", "PathOfExile", "PathOfExile_x64",
    };

    /// Returns true when a game window is in front, either because it already was or because it was raised.
    public static bool Bring()
    {
        // The desktop first: no process access needed, and it is what works when the process list is
        // restricted. Reported honestly at the end if it finds nothing.
        var window = LargestWindow(IsGameWindow, out var candidates);
        Log.Write(candidates > 0
            ? $"focus: the game's window was found by its class/title among {candidates} candidates"
            : "focus: no window of class " + GameWindowClass + " and no exact game title on the desktop");
        window = window == IntPtr.Zero ? FromProcesses() : window;
        if (window == IntPtr.Zero)
        {
            Log.Write("focus: no game window found (neither by window class nor by process, names tried: "
                + string.Join(", ", Names) + ")");
            return false;
        }
        if (GetForegroundWindow() == window)
        {
            Log.Write($"focus: the game was already in front ({Describe(window)})");
            return true;   // already in front: nothing to do, and no flicker
        }
        ShowWindow(window, SW_RESTORE);
        var raised = SetForegroundWindow(window);
        // The window that ended up in front is the evidence: a raised flag on its own cannot be told
        // apart from "the game was restored but another window kept the focus".
        Log.Write(raised
            ? $"focus: the game was brought to the front ({Describe(window)})"
            : $"focus: the game refused to come forward ({Describe(window)}); "
                + $"the foreground is {Describe(GetForegroundWindow())}");
        return raised;
    }

    /// The game's window handle, found exactly the way the hotkey path finds it: by window class or exact
    /// title on the desktop first, then by the known process names. The probe asks this instead of looking up a
    /// process name of its own - the Steam build is called PathOfExileSteam, and a probe that guessed wrong
    /// reported "the game window was not found" while the game sat in front of it.
    public static IntPtr FindGameWindow()
    {
        var window = LargestWindow(IsGameWindow, out _);
        return window == IntPtr.Zero ? FromProcesses() : window;
    }
    /// The game's window as text, or "" when there is none. Read by the live check: the process list can
    /// be restricted in ways the desktop is not, so "the game is running" is answered by the window.
    public static string DescribeGameWindow()
    {
        var window = LargestWindow(IsGameWindow, out _);
        return window == IntPtr.Zero ? "" : Describe(window);
    }

    /// The old way: ask each known game process for its main window, then for its largest visible one.
    private static IntPtr FromProcesses()
    {
        foreach (var name in Names)
        {
            foreach (var process in Process.GetProcessesByName(name))
            {
                var window = CandidateWindow(process, name);
                if (window != IntPtr.Zero)
                {
                    return window;
                }
            }
        }
        return IntPtr.Zero;
    }

    /// The window to raise: the one Windows calls the process's main window, or - when that reports
    /// nothing - the largest visible top-level window the process owns.
    private static IntPtr CandidateWindow(Process process, string name)
    {
        IntPtr main;
        int id;
        try
        {
            main = process.MainWindowHandle;
            id = process.Id;
        }
        catch (Exception error)
        {
            // A process that cannot be inspected at all is worth one line, not a crash in a hot key.
            Log.Write($"focus: {name} could not be inspected: {error.Message}");
            return IntPtr.Zero;
        }

        if (main != IntPtr.Zero)
        {
            return main;
        }

        var found = LargestVisibleWindow(id, out var seen, out _);
        Log.Write($"focus: {name} pid {id} reported no main window; {seen} top-level windows, "
            + (found == IntPtr.Zero ? "none visible and usable" : $"using the largest ({Describe(found)})"));
        return found;
    }

    private static bool IsGameWindow(IntPtr window)
    {
        if (!IsWindowVisible(window) || GetWindow(window, GW_OWNER) != IntPtr.Zero)
        {
            return false;
        }
        var builder = new StringBuilder(256);
        if (GetClassName(window, builder, builder.Capacity) > 0
            && string.Equals(builder.ToString(), GameWindowClass, StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }
        builder.Clear();
        if (GetWindowText(window, builder, builder.Capacity) > 0)
        {
            var title = builder.ToString();
            foreach (var wanted in GameTitles)
            {
                if (string.Equals(title, wanted, StringComparison.Ordinal))
                {
                    return true;
                }
            }
        }
        return false;
    }

    /// The largest visible top-level window that matches, and how many matched.
    private static IntPtr LargestWindow(Func<IntPtr, bool> wanted, out int candidates)
    {
        var best = IntPtr.Zero;
        var bestArea = 0;
        var matched = 0;
        EnumWindows((window, _) =>
        {
            if (!wanted(window) || !GetWindowRect(window, out var rect))
            {
                return true;
            }
            matched++;
            var width = rect.Right - rect.Left;
            var height = rect.Bottom - rect.Top;
            if (width <= 0 || height <= 0 || width * height <= bestArea)
            {
                return true;
            }
            bestArea = width * height;
            best = window;
            return true;
        }, IntPtr.Zero);
        candidates = matched;
        return best;
    }

    private static IntPtr LargestVisibleWindow(int processId, out int seen, out int biggestArea)
    {
        var best = IntPtr.Zero;
        var bestArea = 0;
        var counted = 0;
        EnumWindows((window, _) =>
        {
            GetWindowThreadProcessId(window, out var owner);
            if (owner != (uint)processId)
            {
                return true;
            }
            counted++;
            // Owned windows are popups and tool windows, never the game itself.
            if (!IsWindowVisible(window) || GetWindow(window, GW_OWNER) != IntPtr.Zero)
            {
                return true;
            }
            if (!GetWindowRect(window, out var rect))
            {
                return true;
            }
            var width = rect.Right - rect.Left;
            var height = rect.Bottom - rect.Top;
            if (width <= 0 || height <= 0 || width * height <= bestArea)
            {
                return true;
            }
            bestArea = width * height;
            best = window;
            return true;
        }, IntPtr.Zero);
        seen = counted;
        biggestArea = bestArea;
        return best;
    }

    /// "pid 17764 'Path of Exile 2'": enough to tell one window from another in a log line.
    private static string Describe(IntPtr window)
    {
        if (window == IntPtr.Zero)
        {
            return "nothing";
        }
        GetWindowThreadProcessId(window, out var processId);
        var title = new StringBuilder(160);
        GetWindowText(window, title, title.Capacity);
        return $"pid {processId} '{title}'";
    }
}
