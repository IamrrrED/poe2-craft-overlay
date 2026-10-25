using System.Threading;
using System.Windows.Forms;

namespace Poe2CraftOverlay;

internal static class Program
{
    /// The panel, kept alive by the message loop without being shown at launch.
    public static PanelForm? PanelWindow { get; private set; }
    [STAThread]
    public static void Main(string[] args)
    {
        Log.Write("main entered");

        // Numbers are formatted with a dot everywhere in this process: on a Russian system a double
        // otherwise becomes "0,15" and the vector paths in the splash refuse to parse.
        System.Globalization.CultureInfo.DefaultThreadCurrentCulture = System.Globalization.CultureInfo.InvariantCulture;
        System.Globalization.CultureInfo.DefaultThreadCurrentUICulture = System.Globalization.CultureInfo.InvariantCulture;

        // One overlay per machine: a second launch would mean a second mushroom and a second engine.
        // The self-tests are exempt: they are short-lived processes that kill nothing, and without this
        // they cannot run while the real panel is open - which is exactly when one of them is wanted.
        var positionTest = args.Contains("--test-position");
        var liveCheck = args.Contains("--test-live");
        // The bounded game probe. It presses keys into the game, so it is never part of a normal launch: it needs
        // the flag AND POE2CRAFT_PROBE=1, and it refuses to run beside an open panel.
        var probeCapture = args.Contains("--probe-capture");
        // Geometry of the hover points without touching the game: the one part of the probe that can be checked
        // offline, and the part that decides where the cursor goes.
        var probeCandidates = args.Contains("--probe-candidates");
        var isFirstInstance = true;
        Mutex? single = null;
        if (!positionTest && !liveCheck && !probeCapture)
        {
            single = new Mutex(true, "Poe2CraftOverlay.SingleInstance", out isFirstInstance);
        }
        if (!positionTest && !probeCapture && !isFirstInstance)
        {
            if (liveCheck)
            {
                // The live check borrows the clipboard and the engine for a few seconds, so it must not
                // run beside a panel that is using both - and it must certainly not kill that panel,
                // which is what a second launch normally does.
                Log.Write("live check: a panel is already running; the check is not started");
                return;
            }
            StopOtherInstances();
            return;
        }
        single?.Dispose();

        var shot = args.Contains("--shot");
        // The position self-test runs the real form instead of the panel: the place the player drags
        // the panel to is meant to survive a hide, and that can only be checked on the window itself.
        if (positionTest)
        {
            RunPositionTest();
            return;
        }
        if (liveCheck)
        {
            RunLiveCheck();
            return;
        }
        if (probeCandidates)
        {
            // The one part of the probe that can be checked without the game: where the cursor would go.
            RunProbeCandidates(args);
            return;
        }
        if (probeCapture)
        {
            // The bounded game probe: no window of its own, a report next to the exe, and the same
            // POE2CRAFT_PROBE=1 gate the probe itself checks before touching the game.
            RunProbeCapture();
            return;
        }
        if (!shot)
        {
            // The launch indicator lives on its own thread, so its five seconds never hold up the card.
            SplashRunner.Show();
        }

        try
        {
            // System.Windows.Forms.Application.Run(form) would SHOW the form at once, which is what flashed at startup.
            // The context keeps the message loop alive while the card stays hidden until asked for.
            var panel = new PanelForm(shot);
            PanelWindow = panel;
            panel.ShowOffScreen();            // visible to WebView2, invisible to the player
            _ = panel.InitializeAsync();
            System.Windows.Forms.Application.Run(new ApplicationContext());
            Log.Write("main finished cleanly");
        }
        catch (Exception error)
        {
            Log.Write("startup failed: " + error);
            throw;
        }
    }

    /// A second launch stops the running overlay instead of only complaining.
    //
    // The tray icon is not reliable on every machine, so launching again is the way out. This runs
    // before anything is shown, so the player never sees a message about it.
    private static void StopOtherInstances()
    {
        foreach (var other in System.Diagnostics.Process.GetProcessesByName("Poe2CraftOverlay"))
        {
            if (other.Id != Environment.ProcessId)
            {
                try { other.Kill(); Log.Write("second launch: stopped the running overlay"); }
                catch (Exception error) { Log.Write("second launch: could not stop it: " + error.Message); }
            }
        }
        // The engine is headless now (PoE2 Craft Engine.exe, no windows at all), so stopping it here
        // no longer costs a flash on the next start - the reason it used to be kept alive.
        foreach (var engine in System.Diagnostics.Process.GetProcessesByName("PoE2 Craft Engine"))
        {
            try { engine.Kill(); Log.Write("second launch: stopped the engine"); }
            catch (Exception error) { Log.Write("second launch: engine not stopped: " + error.Message); }
        }
        var dir = new System.IO.DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !System.IO.File.Exists(System.IO.Path.Combine(dir.FullName, "src", "Mcp", "api.lua")))
        {
            dir = dir.Parent;
        }
        if (dir is not null)
        {
            foreach (var stale in new[] { "mcp_serve.flag", "mcp_serve_request.lua" })
            {
                var path = System.IO.Path.Combine(dir.FullName, "src", stale);
                try { if (System.IO.File.Exists(path)) { System.IO.File.Delete(path); Log.Write("second launch: cleared " + stale); } }
                catch { }
            }
        }
    }

    /// Checks that a moved panel comes back where it was left, on the real window.
    // The customer reported the panel returning to its default place after being moved, while the log
    // showed the position file being written and read correctly - so the remaining suspect was the
    // window itself: whether Show() after Hide() honours a Location set while the window was hidden.
    // That cannot be settled by reading the code, so this moves the window, hides it, brings it back
    // and compares. Exit code 0 means the place survived, 2 means it did not.
    private static void RunPositionTest()
    {
        var start = new System.Drawing.Point(360, 260);
        // No engine: this test is about the window, and starting the engine here made it hang on the
        // engine's own startup and mixed the engine's output into the test's log.
        var form = new PanelForm(false, skipEngine: true);
        form.ShowOffScreen();
        form.MoveTo(start);
        form.HideForTest("test-move");
        var back = form.RevealAt("test-reveal");
        var same = back.X == start.X && back.Y == start.Y;
        var line = $"position test: left at {start.X},{start.Y}, came back at {back.X},{back.Y} - "
            + (same ? "OK" : "MISMATCH");
        Log.Write(line);
        System.Console.WriteLine(line);
        // A second cycle, because the first one runs while the window handle is still settling.
        form.HideForTest("test-move-2");
        var again = form.RevealAt("test-reveal-2");
        var sameAgain = again.X == start.X && again.Y == start.Y;
        var line2 = $"position test: second cycle came back at {again.X},{again.Y} - "
            + (sameAgain ? "OK" : "MISMATCH");
        Log.Write(line2);
        System.Console.WriteLine(line2);
        form.Dispose();
        Environment.Exit(same && sameAgain ? 0 : 2);
    }

    /// The live self-check: the real window, the real engine, the real capture path.
    //
    // Everything else in this project can be checked without looking at a screen - the Lua tests run in
    // the shipping host, the page is rendered headless by Chrome - but neither answers "does the panel
    // window itself draw the card". That needs a WebView2 window on a desktop, so it is a mode of this
    // executable: it asserts on the live DOM, keeps two pictures as evidence and exits with 0 or 1.
    // It writes live-check.txt next to the exe, because a WinExe has no console to print to.
    /// Print the hover points for a window of this size, without the game and without moving the cursor.
    private static void RunProbeCandidates(string[] args)
    {
        var numbers = args.Where(a => int.TryParse(a, out _)).Select(int.Parse).ToArray();
        var width = numbers.Length > 0 ? numbers[0] : 1920;
        var height = numbers.Length > 1 ? numbers[1] : 1080;
        var lines = new List<string> { $"window: 0,0 {width}x{height}" };
        foreach (var (x, y) in ProbeCapture.Candidates(0, 0, width, height))
        {
            lines.Add($"{x},{y}");
        }
        lines.Add($"points: {ProbeCapture.Candidates(0, 0, width, height).Count}");
        try
        {
            System.IO.File.WriteAllLines(System.IO.Path.Combine(AppContext.BaseDirectory, "probe-candidates.txt"),
                lines, new System.Text.UTF8Encoding(false));
        }
        catch (Exception error)
        {
            Log.Write("probe candidates: " + error.Message);
        }
        foreach (var line in lines)
        {
            Log.Write("probe candidates: " + line);
        }
    }
    /// The bounded probe: writes its report next to the exe and to the log, and creates no window of its own.
    private static void RunProbeCapture()
    {
        Log.Write("probe: start");
        var report = ProbeCapture.Run();
        foreach (var line in report)
        {
            Log.Write("probe: " + line);
        }
        try
        {
            var path = System.IO.Path.Combine(AppContext.BaseDirectory, "probe-report.txt");
            System.IO.File.WriteAllLines(path, report, new System.Text.UTF8Encoding(false));
            Log.Write("probe: report written to " + path);
        }
        catch (Exception error)
        {
            Log.Write("probe: could not write the report: " + error.Message);
        }
    }
    private static void RunLiveCheck()
    {
        var form = new PanelForm(false, liveCheck: true);
        form.ShowOffScreen();
        var loop = new ApplicationContext();
        // Posted before the loop starts, so it runs as soon as the loop pumps: the browser needs a
        // message loop to draw, and the checks await it, so the UI thread must never be blocked.
        form.BeginInvoke(new Action(async () =>
        {
            var code = 1;
            try
            {
                code = await form.LiveCheckAsync();
            }
            catch (Exception error)
            {
                Log.Write("live check: unexpected failure: " + error);
            }
            Log.Write($"live check: finished with code {code}");
            form.ShutdownForTest();
            Environment.Exit(code);
        }));
        System.Windows.Forms.Application.Run(loop);
    }
}

/// Runs the mushroom splash on a background STA thread and shuts that mini application down when it
/// closes, so the panel keeps its own, ordinary message loop.
internal static class SplashRunner
{
    public static void Show()
    {
        var thread = new Thread(() =>
        {
            try
            {
                // Avalonia is NOT started on purpose: running it is what produced the dark windows
                // flashing at launch, before and after the mushroom. The splash itself is the same
                // thing. The mushroom is a plain WinForms form, so the only window it adds is the
                // mushroom itself.
                Log.Write("splash: showing the mushroom (WinForms)");
                SplashForm.ShowBriefly();
            }
            catch (Exception error)
            {
                Log.Write("splash thread failed: " + error.Message);
            }
        })
        {
            IsBackground = true,
            Name = "PoE2 overlay splash",
        };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
    }
}