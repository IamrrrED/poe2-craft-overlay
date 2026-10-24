using System.Drawing;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace Poe2CraftOverlay;

/// The crafting card, as a plain WinForms window with a WebView2 control in it.
///
/// The previous version embedded WebView2 into an Avalonia window and the browser never drew: the
/// page reported success and the window stayed empty. WinForms is the environment where WebView2 is
/// known to work on this machine - the capture agent and this overlay's own tray icon both prove it.
/// The interface itself is unchanged: the same HTML, the same engine, the same step coach.
internal sealed class PanelForm : Form
{
    private readonly WebView2 _browser = new();
    private readonly EngineClient _engine = new();
    private readonly TrayIconHost _tray = new();
    private readonly System.Windows.Forms.Timer _keys = new() { Interval = 60 };
    private readonly System.Windows.Forms.Timer _autohide = new() { Interval = 1000 };

    private bool _reallyQuit;   // set only by the tray exit: everything else just hides the panel
    private bool _clickThrough = false;   // always clickable: the panel has its own close button and is dragged by its header
    private bool _ready;
    private DateTime _revealedAt = DateTime.MinValue;
    private bool _f7, _f9, _f10;
    private bool _shotMode;
    private readonly bool _liveCheck;   // the live self-check borrows this window (see LiveCheckAsync)
    // What the player chose ("ru", "en" or "auto") and what it resolves to right now. The engine answers
    // in the resolved language, and the page draws its own chrome in it.
    private string _languageSetting = PanelLanguage.Auto;
    private string _language = PanelLanguage.English;
    private string? _clientLanguage;    // what the game client last spoke, for the "auto" setting
    // Set once the page has loaded AND the demo item has been drawn in it: the live check waits on
    // this instead of guessing how long WebView2 needs.
    private readonly TaskCompletionSource<bool> _loaded = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private Point? _placed;             // where the player left the panel; null until it is known
    private static readonly Point OffScreen = new(-32000, -32000);
    private static readonly Point OnScreen = new(200, 120);

    public PanelForm(bool shotMode, bool skipEngine = false, bool liveCheck = false)
    {
        _shotMode = shotMode;
        _liveCheck = liveCheck;

        // The language is read before anything is drawn or asked: every engine answer carries it.
        _languageSetting = PanelLanguage.Load();
        _language = PanelLanguage.Resolve(_languageSetting, null);
        Log.Write($"language: setting {_languageSetting}, speaking {_language}");

        Text = "PoE2 Craft Overlay";
        FormBorderStyle = FormBorderStyle.None;
        // The panel lives off screen until it is needed. WebView2 insists on a visible host while it
        // starts, and that is exactly what flashed on screen at launch: a "hidden" form does not work,
        // an off-screen one does. On Ctrl+Q the window simply moves to the middle of the screen.
        StartPosition = FormStartPosition.Manual;
        Location = OffScreen;
        TopMost = true;
        ShowInTaskbar = false;
        // The window can be resized now: the page is laid out in percentages, so it follows the frame.
        // A caption bar comes with it, which is also a native way out of the panel.
        FormBorderStyle = FormBorderStyle.Sizable;
        MinimumSize = new Size(760, 540);
        ClientSize = new Size(980, 740);
        TopMost = true;   // the panel stays above the game
        BackColor = Color.FromArgb(25, 25, 19);
        DoubleBuffered = true;
        // Create the window without ever putting it on screen: the handle is all the browser needs to
        // start, and showing an empty frame first is exactly what made the launch flicker.
        ShowInTaskbar = false;
        WindowState = FormWindowState.Normal;
        Opacity = 1;

        _browser.Dock = DockStyle.Fill;
        _browser.DefaultBackgroundColor = Color.FromArgb(25, 25, 19);
        Controls.Add(_browser);

        _keys.Tick += (_, _) => WatchKeys();
        // Ctrl+Q comes from the shell as well (see Hotkeys): the polled watcher cannot see keys
        // pressed in a window of a higher integrity level, which is what the game is.
        // Every hot key checks that the form is still alive: the shell keeps calling the filter after the
// panel has been disposed, and touching a disposed form threw ObjectDisposedException, which killed
// the process - and with it the engine - on the second Ctrl+Q.
Hotkeys.Install(this,
    () => { if (!IsDisposed && !Disposing) { _ = CaptureAsync(); } },
    () => { if (!IsDisposed && !Disposing) { Reveal("hotkey"); } },
    () => { if (!IsDisposed && !Disposing) { HidePanel(); } });
        // The engine is started now, at launch, on a background thread. Starting it on the first
        // capture is what made Windows show a busy cursor while the player waited for the item.
        // Skipped by the window self-test, which needs no engine: starting one there made the test hang
        // on the engine's own startup and printed its crash output into the test's own log.
        // Also skipped by the live self-check, which starts the engine itself and then waits for the
        // answer: two requests in flight at once would fight over the same request file.
        if (!skipEngine && !_liveCheck)
        {
            _ = Task.Run(async () =>
            {
            try
            {
                // The engine starts together with the agent, exactly as asked, and the mushroom stays on
                // screen until this call returns - that is the moment the start has finished.
                var warmWatch = System.Diagnostics.Stopwatch.StartNew();
                var warm = await _engine.CallAsync("prices");
                Log.Write($"engine: start finished in {warmWatch.ElapsedMilliseconds} ms (the mushroom disappears now)");
                Log.Write(warm is null ? "engine: warm-up gave no answer" : "engine: warm-up done, engine is ready");
                // closing it here made it a blink. It closes on its own timer instead.
            }
                catch (Exception error)
                {
                    Log.Write("engine: warm-up failed: " + error.Message);
                }
            });
        }
        _autohide.Tick += (_, _) => AutoHide();
        // The place the panel was left at, read once: the constructor runs before the window is
        // parked off screen, so this is the last chance to ask before the location changes.
        _placed = PanelPosition.Load();
        // Initialised explicitly by Program: a form that is never shown never raises Load.
        FormClosing += (_, e) =>
        {
            // A close that was not asked for by the tray is cancelled: the panel is hidden instead.
            // Disposing the form also disposed the engine (and deleted mcp_serve.flag), after which any
            // hot key met a disposed form and the panel looked like it had taken the engine down with it.
            if (!_reallyQuit)
            {
                e.Cancel = true;
                RememberPlace();
                Hide();
                Log.Write("panel: close cancelled, the panel is only hidden (the engine keeps running)");
                return;
            }
            RememberPlace();
            _engine.Dispose();
            _tray.Dispose();
        };
    }

    /// Shows the window where the player cannot see it: WebView2 needs a visible host to start.
    public void ShowOffScreen()
    {
        Location = OffScreen;
        Show();
        Log.Write("panel: created off screen (nothing flashes on the desktop)");
    }

    public async Task InitializeAsync()
    {
        try
        {
            var userData = Path.Combine(AppContext.BaseDirectory, "webview2-data");
            Directory.CreateDirectory(userData);
            // Timings, so the busy cursor can be pinned on a step instead of guessed at.
            var watch = System.Diagnostics.Stopwatch.StartNew();
            var environment = await CoreWebView2Environment.CreateAsync(null, userData);
            Log.Write($"init: webview environment ready in {watch.ElapsedMilliseconds} ms");
            await _browser.EnsureCoreWebView2Async(environment);
            Log.Write($"init: webview controller ready in {watch.ElapsedMilliseconds} ms");
            _browser.CoreWebView2.Settings.AreDevToolsEnabled = false;
            _browser.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
            _browser.CoreWebView2.Settings.IsStatusBarEnabled = false;
            // The page carries its own close button and asks for the window to hide through it.
            _browser.CoreWebView2.WebMessageReceived += (_, args) =>
            {
                try
                {
            // The page asks the window to move while the mouse drags its top strip: the browser covers
            // the whole form, so the form itself never sees those mouse events.
            if (args.TryGetWebMessageAsString() is string drag && drag.StartsWith("drag:", StringComparison.Ordinal))
            {
                var parts = drag.Split(':');
                if (parts.Length == 3 && int.TryParse(parts[1], out var dx) && int.TryParse(parts[2], out var dy))
                {
                    Location = new Point(Location.X + dx, Location.Y + dy);
                    // Written as the panel is dragged, not only when it is hidden: a crash or a kill
                    // would otherwise lose the place the player chose.
                    PanelPosition.Save(Location, "drag");
                }
            }
                // The page used to carry its own close button and asked the window to hide through it.
                // The control is gone - the form's title bar has the ordinary one - but the message is
                // still honoured, so an older copy of the page cannot leave the player without a way out.
                else if (args.TryGetWebMessageAsString() is string linkMessage
                    && linkMessage.StartsWith("link:", StringComparison.Ordinal))
                {
                    // The card offers the trade search it built. Opening it in the same WebView would replace
                    // the panel, so the default browser takes it: the query is long and the player wants it
                    // next to the panel, not instead of it.
                    var target = linkMessage.Substring("link:".Length);
                    if (target.StartsWith("https://www.pathofexile.com/", StringComparison.OrdinalIgnoreCase))
                    {
                        try
                        {
                            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(target)
                            {
                                UseShellExecute = true,
                            });
                            Log.Write("panel: trade search opened in the browser");
                        }
                        catch (Exception error)
                        {
                            Log.Write("panel: could not open the trade search: " + error.Message);
                        }
                    }
                    else
                    {
                        Log.Write("panel: refused to open a link that is not the trade site");
                    }
                }
                else if (args.TryGetWebMessageAsString() == "close")
                {
                    Log.Write("panel: close asked for by the page");
                    HidePanel("page");
                }
                // The player picked a stage (кампания / ранний эндгейм / эндгейм). The stage decides which
                // methods are worth spending on, so the item is analysed again with it instead of the page
                // filtering on its own - the engine is the single source for that judgement.
                else if (args.TryGetWebMessageAsString() is string stageMessage
                    && stageMessage.StartsWith("stage:", StringComparison.Ordinal))
                {
                    var chosen = stageMessage.Substring("stage:".Length);
                    Log.Write("panel: stage chosen by the page: " + chosen);
                    _ = SetStageAsync(chosen);
                }
                // The player's situation, sent by the page once and remembered: SSF or trade, how much currency
            // there is, and whether the item is for wearing or for sale. The engine re-answers with it.
            else if (args.TryGetWebMessageAsString() is string contextMessage
                && contextMessage.StartsWith("context:", StringComparison.Ordinal))
            {
                foreach (var pair in contextMessage.Substring("context:".Length).Split(';'))
                {
                    var parts = pair.Split('=', 2);
                    if (parts.Length != 2)
                    {
                        continue;
                    }
                    switch (parts[0])
                    {
                        case "mode":
                            _mode = parts[1] == "ssf" ? "ssf" : "trade";
                            break;
                        case "goal":
                            _goal = parts[1] == "wear" ? "wear" : "sell";
                            break;
                        case "budget":
                            double.TryParse(parts[1], System.Globalization.NumberStyles.Float,
                                System.Globalization.CultureInfo.InvariantCulture, out _budgetChaos);
                            break;
                    }
                }
                Log.Write("panel: context = " + _mode + "/" + _goal + "/" + _budgetChaos.ToString(
                    System.Globalization.CultureInfo.InvariantCulture));
                if (!string.IsNullOrEmpty(_lastItemText))
                {
                    _ = ShowItemAsync(_lastItemText);
                }
            }
            // "Is this true?" - the page sends the claim, the engine answers from its own rules, and the
                // verdict goes back to the page. The page never decides on its own what is true.
                else if (args.TryGetWebMessageAsString() is string claimMessage
                    && claimMessage.StartsWith("claim:", StringComparison.Ordinal))
                {
                    var claim = claimMessage.Substring("claim:".Length);
                    Log.Write("panel: claim check asked: " + claim);
                    _ = CheckClaimAsync(claim);
                }
                // "Is crafting this cheaper than buying it?" The player supplies the market price he just
                // looked up; the engine supplies the craft cost it can compute. The comparison happens in the
                // engine so the page cannot invent either side of it.
                else if (args.TryGetWebMessageAsString() is string buyMessage
                    && buyMessage.StartsWith("buy:", StringComparison.Ordinal))
                {
                    var price = buyMessage.Substring("buy:".Length);
                    Log.Write("panel: craft-vs-buy asked at " + price);
                    _ = CompareBuyAsync(price);
                }
                // Ask the live trade site instead of asking the player. Same comparison, the price looked up
                // by the program: same base, same modifiers, median of the priced listings.
                else if (args.TryGetWebMessageAsString() == "autoprice")
                {
                    Log.Write("panel: auto market price asked");
                    _ = AutoPriceAsync();
                }
                // The player picked a language in the page. The host owns the setting (and has to re-ask
                // the engine for its own text), so the page only asks; the answer arrives as setLanguage.
                else if (args.TryGetWebMessageAsString() is string languageMessage
                    && languageMessage.StartsWith("lang:", StringComparison.Ordinal))
                {
                    Log.Write("panel: language asked by the page: " + languageMessage.Substring("lang:".Length));
                    _ = SetLanguageSettingAsync(languageMessage.Substring("lang:".Length));
                }
            }
            catch (Exception error)
            {
                Log.Write("panel: page message failed: " + error.Message);
            }
        };
            _browser.CoreWebView2.NavigationCompleted += async (_, e) =>
            {
                Log.Write($"panel: page loaded (success {e.IsSuccess})");
                _ready = true;
                // The page's own chrome has to know the language before it draws the first card.
                await RunAsync($"window.setLanguage('{_language}')");
                await LoadSampleAsync();
                // "Loaded" means the window has the engine's answer on screen, not merely that the
                // browser finished fetching the page: the live check waits for the card itself.
                _loaded.TrySetResult(e.IsSuccess);
                if (_shotMode)
                {
                    await Task.Delay(1200);
                    SaveShot();
                }
            };
            var page = Path.Combine(AppContext.BaseDirectory, "Ui", "panel.html");
            Log.Write("panel: navigating to " + page);
            Log.Write($"init: navigating at {watch.ElapsedMilliseconds} ms");
            _browser.CoreWebView2.Navigate(new Uri(page).AbsoluteUri);
        }
        catch (Exception error)
        {
            Log.Write("panel: browser failed: " + error.Message);
        }

        ApplyClickThrough();
        // The tray icon needs a shell of the player's own: the check is a diagnostic, not a launch, and
        // an icon left behind by a five-second check would be a mystery the next morning.
        if (!_liveCheck)
        {
            ShowTray();
        }
        // left a second icon behind next to the real one. ShowTray above is the one that stays.
        _keys.Start();
        // Auto hide is deliberately off: the card is meant to stay on screen while crafting.
        // _autohide.Start();

        if (_shotMode)
        {
            Reveal("shot");         // stays on screen, otherwise the picture shows the desktop behind it
        }
        else if (_liveCheck)
        {
            // The check shows the panel itself when it takes the pictures; showing it here would put
            // it on the desktop before there is anything worth looking at.
            Log.Write("panel: live check, initialised and hidden");
        }
        else
        {
            // Plain Hide, not HidePanel: the window is parked off screen here, and the position just
            // read from the file must not be overwritten with that parking spot.
            Hide();                 // the card appears on capture, not at launch
            Log.Write("panel ready and hidden: Ctrl+Q captures the item");
        }
    }

    /// Ends the live check without leaving its engine process behind.
    /// Also does not touch the saved position: a diagnostic must not move the player's panel.
    public void ShutdownForTest()
    {
        _engine.Dispose();
        _tray.Dispose();
    }

    private void ShowTray()
    {
        try
        {
            // The mushroom file is a large multi-size ICO, and NotifyIcon accepts some of those
            // silently: the icon registers and draws nothing. Anything that goes wrong while loading
            // it now falls back to a system icon, and the log says which one was used, so the next
            // run tells us whether the file or the shell is to blame.
            var iconPath = Path.Combine(AppContext.BaseDirectory, "Ui", "mushroom.ico");
            Icon icon;
            string iconSource;
            try
            {
                icon = File.Exists(iconPath) ? new Icon(iconPath) : SystemIcons.Application;
                iconSource = File.Exists(iconPath) ? "mushroom.ico" : "system (файла нет)";
            }
            catch (Exception error)
            {
                icon = SystemIcons.Application;
                iconSource = "system (ошибка загрузки: " + error.Message + ")";
            }
            Log.Write("tray: icon source = " + iconSource + ", size = " + icon.Width + "x" + icon.Height);
            _tray.Show(icon, TrayLabelsFor(_language), RevealFromTray, CaptureFromTray,
                () => _ = SetLanguageSettingAsync(PanelLanguage.Auto),
                () => _ = SetLanguageSettingAsync(PanelLanguage.Russian),
                () => _ = SetLanguageSettingAsync(PanelLanguage.English),
                QuitFromTray);
            _tray.SetLabels(TrayLabelsFor(_language), _languageSetting);
            _tray.Announce(Messages.Get(_language, "trayStartTitle"), Messages.Get(_language, "trayStartText"));
        }
        catch (Exception error)
        {
            Log.Write("tray setup failed: " + error.Message);
        }
    }

    /// The tray menu's words in the panel's language.
    private static TrayLabels TrayLabelsFor(string language) => new(
        Messages.Get(language, "trayShow"),
        Messages.Get(language, "trayCapture"),
        Messages.Get(language, "trayLanguage"),
        Messages.Get(language, "trayLanguageAuto"),
        Messages.Get(language, "trayLanguageRu"),
        Messages.Get(language, "trayLanguageEn"),
        Messages.Get(language, "trayQuit"),
        Messages.Get(language, "trayStartTitle"),
        Messages.Get(language, "trayStartText"));

    /// One host sentence as a JavaScript string literal, in the panel's language.
    private string EngineErrorScript(string key) =>
        System.Text.Json.JsonSerializer.Serialize(Messages.Get(_language, key));

    // ---- engine -------------------------------------------------------------------------------

    /// The player chose a language (page or tray): remember it, tell the page and the tray, re-ask the
    /// engine. The engine builds its cards in one language, so switching is a new analysis, not a re-draw.
    /// @param setting "auto" (follow the game client), "ru" or "en"
    public async Task SetLanguageSettingAsync(string setting)
    {
        var wanted = setting == PanelLanguage.Russian || setting == PanelLanguage.English
            ? setting
            : PanelLanguage.Auto;
        _languageSetting = wanted;
        PanelLanguage.Save(wanted);
        var resolved = PanelLanguage.Resolve(wanted, _clientLanguage);
        var changed = resolved != _language;
        _language = resolved;
        Log.Write($"language: the player chose {wanted}, speaking {_language}" + (changed ? " (changed)" : ""));
        _tray.SetLabels(TrayLabelsFor(_language), _languageSetting);
        await RunAsync($"window.setLanguage('{_language}')");
        if (changed && !string.IsNullOrEmpty(_lastItemText))
        {
            await ShowItemAsync(_lastItemText, fromGame: false);
        }
    }

    /// In "auto" the panel speaks the language of the game client, and the copied text is where that
    /// language shows: the same evidence the engine's own detection uses. A pinned language never moves.
    private void FollowClientLanguage(string itemText)
    {
        _clientLanguage = PanelLanguage.FromItemText(itemText);
        if (_languageSetting != PanelLanguage.Auto)
        {
            return;
        }
        var resolved = PanelLanguage.Resolve(_languageSetting, _clientLanguage);
        if (resolved == _language)
        {
            return;
        }
        _language = resolved;
        Log.Write("language: following the game client, now " + _language);
        _ = RunAsync($"window.setLanguage('{_language}')");
    }

    /// Loads the demo item. It is ours, not the player's, so it must not decide the panel's language.
    private async Task LoadSampleAsync()
    {
        var sample = Path.Combine(_engine.Root, "samples", "rare_gloves.txt");
        if (File.Exists(sample))
        {
            await ShowItemAsync(File.ReadAllText(sample), fromGame: false);
        }
    }

    // The last captured item, kept so the stage switch can re-analyse it without asking the player to
    // copy the item again: choosing "кампания" is a question about THIS item, not a new capture.
    private string? _lastItemText;
    private string? _lastReportJson;

    /// Re-analyse the current item for a stage the player picked.
    /// The stage decides which methods are worth spending on, so switching it must re-ask the engine.
    public async Task SetStageAsync(string stage)
    {
        if (string.IsNullOrEmpty(_lastItemText))
        {
            return;
        }
        _stage = stage;
        await ShowItemAsync(_lastItemText);
    }

    private string _stage = "";

    // How the player actually crafts: in trade or SSF, how much currency they are willing to spend, and
    // whether the item is for wearing or for sale. Kept here so the engine can answer like a person.
    private string _mode = "trade";
    private string _goal = "sell";
    private double _budgetChaos = 0;

    /// Ask the engine whether a claim about crafting is true, and show the verdict.
    /// Kept in C# so the page cannot answer from its own copy of the rules: the engine stays the single source.
    public async Task CheckClaimAsync(string claim)
    {
        var answer = await _engine.CallAsync("check_claim",
            new Dictionary<string, object?> { ["text"] = claim, ["lang"] = _language });
        await RunAsync($"window.showClaimAnswer({answer?.ToJsonString() ?? "null"})");
    }

    /// Find tools/market_price.js without assuming where the app was launched from.
    /// It is not copied into the build output: the market scripts need mcp-market/lib next to them, so they stay
    /// in the repository and are located by walking up from either the binary or the working directory.
    private static string? FindMarketScript()
    {
        foreach (var start in new[] { AppContext.BaseDirectory, Environment.CurrentDirectory })
        {
            var directory = new DirectoryInfo(start);
            for (var depth = 0; depth < 6 && directory is not null; depth++)
            {
                var candidate = Path.Combine(directory.FullName, "tools", "market_price.js");
                if (File.Exists(candidate))
                {
                    return candidate;
                }
                directory = directory.Parent;
            }
        }
        return null;
    }

    /// Price the few modifiers worth hunting, not the whole item.
    ///
    /// Each wanted modifier is priced with the existing market script: one search for "this base with this
    /// modifier", median of the priced listings - the same honest number the craft-vs-buy card uses. It runs in
    /// the background so the card is never blocked by the trade site, one request per modifier (at most five),
    /// and every failure is reported per modifier instead of being hidden: "no listings" and "not checked" are
    /// different answers and the panel says which one it has.
    public async Task PriceModsAsync()
    {
        if (string.IsNullOrEmpty(_lastItemText) || string.IsNullOrEmpty(_lastReportJson))
        {
            return;
        }

        var script = FindMarketScript();
        if (script is null)
        {
            return;
        }

        List<string> texts = new();
        try
        {
            using var report = System.Text.Json.JsonDocument.Parse(_lastReportJson);
            if (report.RootElement.TryGetProperty("modPool", out var pool)
                && pool.TryGetProperty("wanted", out var wanted)
                && wanted.ValueKind == System.Text.Json.JsonValueKind.Array)
            {
                foreach (var entry in wanted.EnumerateArray())
                {
                    if (entry.TryGetProperty("bestText", out var text)
                        && text.ValueKind == System.Text.Json.JsonValueKind.String)
                    {
                        var value = text.GetString();
                        if (!string.IsNullOrWhiteSpace(value))
                        {
                            texts.Add(value!);
                        }
                    }
                }
            }
        }
        catch (Exception error)
        {
            Log.Write("panel: mod prices could not read the pool: " + error.Message);
            return;
        }
        if (texts.Count == 0)
        {
            return;
        }
        if (texts.Count > 5)
        {
            texts = texts.GetRange(0, 5);
        }

        // The base, the host and the league come from the engine: it parses the item, and a Russian query must
        // go to the Russian host, exactly like the item price does.
        var spec = await _engine.CallAsync("market_query", new Dictionary<string, object?>
        {
            ["item_text"] = _lastItemText,
            ["lang"] = _language,
        });
        if (spec is null)
        {
            return;
        }

        var results = new List<Dictionary<string, object?>>();
        foreach (var text in texts)
        {
            var payload = new Dictionary<string, object?>
            {
                ["base"] = spec["base"]?.ToString(),
                ["mods"] = new[] { new Dictionary<string, object?> { ["text"] = text } },
                ["lang"] = _language,
            };
            var host = spec["tradeHost"]?.ToString();
            if (!string.IsNullOrEmpty(host))
            {
                payload["tradeHost"] = host;
            }
            var league = spec["league"]?.ToString();
            if (!string.IsNullOrEmpty(league))
            {
                payload["league"] = league;
            }

            var answer = await RunMarketAsync(script, payload);
            var row = new Dictionary<string, object?> { ["text"] = text };
            if (answer is null)
            {
                row["state"] = "unreadable";
            }
            else
            {
                var body = answer.Value;
                row["state"] = body.TryGetProperty("ok", out var ok)
                    && ok.ValueKind == System.Text.Json.JsonValueKind.True
                        ? "priced"
                        : "refused";
                // The script answers in chaos and calls the field "medianChaos" (the item price path reads the
                // same one), so the panel converts nothing and shows the number the market gave.
                if (body.TryGetProperty("medianChaos", out var median)
                    && median.ValueKind == System.Text.Json.JsonValueKind.Number)
                {
                    row["median"] = median.GetDouble();
                    row["currency"] = _language == "en" ? "chaos" : "хаоса";
                }
                if (body.TryGetProperty("priced", out var priced)
                    && priced.ValueKind == System.Text.Json.JsonValueKind.Number)
                {
                    row["priced"] = priced.GetInt32();
                }
                if (body.TryGetProperty("currency", out var currency))
                {
                    row["currency"] = currency.ToString();
                }
                if (body.TryGetProperty("url", out var url))
                {
                    row["url"] = url.ToString();
                }
                if (body.TryGetProperty("reasonRu", out var reason))
                {
                    row["reason"] = reason.ToString();
                }
            }
            results.Add(row);
        }

        Log.Write("panel: mod prices ready for " + results.Count + " modifiers");
        await RunAsync("window.applyModPrices("
            + System.Text.Json.JsonSerializer.Serialize(new Dictionary<string, object?> { ["results"] = results })
            + ")");
    }

    /// One market-script call, shared by the item price and the modifier prices.
    private static async Task<System.Text.Json.JsonElement?> RunMarketAsync(string script,
        Dictionary<string, object?> payload)
    {
        try
        {
            var node = Environment.GetEnvironmentVariable("POE2CRAFT_NODE") ?? "node";
            var start = new System.Diagnostics.ProcessStartInfo
            {
                FileName = node,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
                StandardOutputEncoding = System.Text.Encoding.UTF8,
                StandardErrorEncoding = System.Text.Encoding.UTF8,
            };
            start.ArgumentList.Add(script);
            using var process = System.Diagnostics.Process.Start(start);
            if (process is null)
            {
                return null;
            }
            await process.StandardInput.WriteAsync(
                System.Text.Json.JsonSerializer.Serialize(payload));
            process.StandardInput.Close();
            var output = await process.StandardOutput.ReadToEndAsync();
            await process.WaitForExitAsync();
            using var document = System.Text.Json.JsonDocument.Parse(output);
            return document.RootElement.Clone();
        }
        catch (Exception error)
        {
            Log.Write("panel: market call failed: " + error.Message);
            return null;
        }
    }
    /// Price the item on the live trade site and compare it with the craft cost.
    /// The engine decides WHAT to ask (it parses the item); the node script asks it; the engine compares.
    public async Task AutoPriceAsync()
    {
        if (string.IsNullOrEmpty(_lastItemText))
        {
            await RunAsync("window.showBuyVerdict(null)");
            return;
        }

        var script = FindMarketScript();
        if (script is null)
        {
            await RunAsync("window.showBuyVerdict({\"text\":"
                + System.Text.Json.JsonSerializer.Serialize(Messages.Get(_language, "marketScriptMissing")) + "})");
            return;
        }

        var spec = await _engine.CallAsync("market_query", new Dictionary<string, object?>
        {
            ["item_text"] = _lastItemText,
            ["lang"] = _language,
        });
        if (spec is null)
        {
            await RunAsync("window.showBuyVerdict({\"text\":"
                + System.Text.Json.JsonSerializer.Serialize(Messages.Get(_language, "marketQueryFailed")) + "})");
            return;
        }

        string output;
        try
        {
            var node = Environment.GetEnvironmentVariable("POE2CRAFT_NODE") ?? "node";
            var start = new System.Diagnostics.ProcessStartInfo
            {
                FileName = node,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
                // The market helper answers in UTF-8 (its labels are Russian). Without this, .NET decodes the
                // child's stdout with the system ANSI code page and every Russian label reached the card as
                // mojibake: "Совпадение: Р¡ЅСР¡Р¡РѕРѕС‚РєР° ...". The bytes were always right; the reading was not.
                StandardOutputEncoding = System.Text.Encoding.UTF8,
                StandardErrorEncoding = System.Text.Encoding.UTF8,
            };
            start.ArgumentList.Add(script);
            using var process = System.Diagnostics.Process.Start(start);
            if (process is null)
            {
                throw new InvalidOperationException("node не запустился");
            }
            await process.StandardInput.WriteAsync(spec.ToJsonString());
            process.StandardInput.Close();
            output = await process.StandardOutput.ReadToEndAsync();
            await process.WaitForExitAsync();
        }
        catch (Exception error)
        {
            Log.Write("panel: market price failed: " + error.Message);
            await RunAsync("window.showBuyVerdict({\"text\":"
                + System.Text.Json.JsonSerializer.Serialize(Messages.Get(_language, "marketNoNode")) + "})");
            return;
        }

        System.Text.Json.JsonElement parsed;
        try
        {
            parsed = System.Text.Json.JsonDocument.Parse(output).RootElement.Clone();
        }
        catch (Exception error)
        {
            Log.Write("panel: market price returned unreadable JSON: " + error.Message);
            await RunAsync("window.showBuyVerdict({\"text\":"
                + System.Text.Json.JsonSerializer.Serialize(Messages.Get(_language, "marketUnreadable")) + "})");
            return;
        }

        if (!parsed.TryGetProperty("ok", out var ok) || ok.ValueKind != System.Text.Json.JsonValueKind.True)
        {
            // A refused request is not a mystery: the market library knows whether the trade site is on
            // cooldown and how much of the hourly budget is left, so the panel can say which it is.
            var reason = parsed.TryGetProperty("reason", out var why) ? why.GetString() : null;
            var seconds = parsed.TryGetProperty("cooldownSeconds", out var wait)
                && wait.ValueKind == System.Text.Json.JsonValueKind.Number ? wait.GetInt32() : 0;
            string message;
            if (seconds > 0)
            {
                message = Messages.Get(_language, "marketCooldown", seconds);
            }
            else
            {
                message = Messages.Get(_language, "marketRefused",
                    Messages.MarketReason(_language, reason ?? Messages.Get(_language, "marketNoReason")));
                // When the base is not a real one, the payload carries near matches. A refusal that names
                // alternatives can be acted on; "unknown item base type" cannot.
                if (parsed.TryGetProperty("suggestions", out var near)
                    && near.ValueKind == System.Text.Json.JsonValueKind.Array
                    && near.GetArrayLength() > 0)
                {
                    var names = new List<string>();
                    foreach (var entry in near.EnumerateArray())
                    {
                        var name = entry.GetString();
                        if (!string.IsNullOrEmpty(name))
                        {
                            names.Add(name);
                        }
                    }
                    if (names.Count > 0)
                    {
                        message += Messages.Get(_language, "marketSuggestions", string.Join(", ", names));
                    }
                }
            }
            await RunAsync($"window.showBuyVerdict({{\"text\":{System.Text.Json.JsonSerializer.Serialize(message)}}})");
            Log.Write("panel: market price refused: " + (reason ?? "?") + $", wait {seconds}s");
            return;
        }

        if (!parsed.TryGetProperty("medianChaos", out var median) || median.ValueKind != System.Text.Json.JsonValueKind.Number)
        {
            await RunAsync("window.showBuyVerdict({\"text\":"
                + System.Text.Json.JsonSerializer.Serialize(Messages.Get(_language, "marketNoMedian")) + "})");
            return;
        }

        var price = median.GetDouble();
        // The search URL travels with the number, so the card can offer the very query that produced it.
        var marketUrl = parsed.TryGetProperty("url", out var tradeLink) ? tradeLink.GetString() : null;
        var verdict = await _engine.CallAsync("craft_or_buy", new Dictionary<string, object?>
        {
            ["item_text"] = _lastItemText,
            ["buy_price"] = price,
            ["source"] = "market",
            ["market_url"] = marketUrl,
            ["lang"] = _language,
        });
        var listings = parsed.TryGetProperty("priced", out var counted) ? counted.GetInt32() : 0;
        var total = parsed.TryGetProperty("total", out var found) ? found.GetInt32() : 0;
        var matched = parsed.TryGetProperty("matchedLabel", out var label) ? label.GetString() : null;
        var note = Messages.Get(_language, "marketMedian", listings, total);
        // Say WHICH filter produced the price. An exact-match number and a "one prefix, one suffix, -20%"
        // number answer different questions, and hiding the difference would overstate the comparison.
        if (!string.IsNullOrEmpty(matched))
        {
            note += Messages.Get(_language, "marketMatch", matched);
        }
        // The market library caches trade responses for two minutes, so looking at the same item twice may
        // cost nothing. Saying so stops a player from assuming every click spends the hourly budget - and it
        // is the reason a repeat answer can look unchanged.
        if (parsed.TryGetProperty("cachedForSeconds", out var ttl)
            && ttl.ValueKind == System.Text.Json.JsonValueKind.Number)
        {
            note += Messages.Get(_language, "marketCached", ttl.GetInt32());
        }
        // Say when the hourly budget is running low, so the next click is not a surprise.
        if (parsed.TryGetProperty("quota", out var quota)
            && quota.TryGetProperty("remaining", out var remaining)
            && remaining.ValueKind == System.Text.Json.JsonValueKind.Number
            && remaining.GetInt32() <= 30)
        {
            note += Messages.Get(_language, "marketQuota", remaining.GetInt32());
        }
        await RunAsync($"window.showBuyVerdict({verdict?.ToJsonString() ?? "null"},"
            + $"{System.Text.Json.JsonSerializer.Serialize(note)})");
        Log.Write($"panel: market price {price:0.0000} chaos, {listings} listings of {total}");
    }

    /// Compare the computed craft cost with a market price the player typed in.
    /// The price is the player's, the cost is the engine's, and the arithmetic is the engine's too.
    public async Task CompareBuyAsync(string price)
    {
        if (string.IsNullOrEmpty(_lastItemText) || !decimal.TryParse(price, out var value))
        {
            await RunAsync("window.showBuyVerdict(null)");
            return;
        }
        var verdict = await _engine.CallAsync("craft_or_buy", new Dictionary<string, object?>
        {
            ["item_text"] = _lastItemText,
            ["buy_price"] = value,
            ["lang"] = _language,
        });
        await RunAsync($"window.showBuyVerdict({verdict?.ToJsonString() ?? "null"})");
    }

    private async Task ShowItemAsync(string itemText, bool fromGame = true)
    {
        _lastItemText = itemText;
        if (fromGame)
        {
            FollowClientLanguage(itemText);
        }
        var args = new Dictionary<string, object?> { ["item_text"] = itemText, ["lang"] = _language };
        if (!string.IsNullOrEmpty(_stage))
        {
            args["stage"] = _stage;
        }
        var analysis = await _engine.CallAsync("analyze_item", args);
        if (analysis is null)
        {
            await RunAsync("window.showEngineError(" + EngineErrorScript("noEngineAnswer") + ")");
            return;
        }
        var client = await _engine.CallAsync("item_lines",
            new Dictionary<string, object?> { ["item_text"] = itemText, ["lang"] = _language });
        var report = await _engine.CallAsync("craft_step",
            new Dictionary<string, object?>
            {
                ["item_text"] = itemText,
                ["lang"] = _language,
                // The player's own situation: what every human crafter asks before advising. Null/absent
                // values keep the previous behaviour, so an old page or a fresh install still works.
                ["mode"] = _mode,
                ["goal"] = _goal,
                ["budget_chaos"] = _budgetChaos > 0 ? _budgetChaos : (object?)null,
            });
        var guide = await _engine.CallAsync("crafting_guide",
            new Dictionary<string, object?> { ["lang"] = _language });
        // Kept so the background price pass can read the modifier pool without asking the engine again.
        _lastReportJson = report?.ToJsonString();
        await RunAsync($"window.showCoach({report?.ToJsonString() ?? "null"}, {analysis.ToJsonString()}, "
            + $"{client?.ToJsonString() ?? "null"}, {guide?.ToJsonString() ?? "null"})");
        Log.Write("panel: card updated");
    }

    private Task RunAsync(string script) =>
        _ready ? _browser.CoreWebView2.ExecuteScriptAsync(script).ContinueWith(_ => { }) : Task.CompletedTask;

    // ---- capture ------------------------------------------------------------------------------

    /// The clipboard can hand back null, so this answers for a missing text as well as an empty one.
    private static bool LooksLikeItem(string? text)
    {
        return !string.IsNullOrWhiteSpace(text)
            && (text.Contains("Rarity:", StringComparison.Ordinal)
                || text.Contains("Item Class:", StringComparison.Ordinal)
                || text.Contains("Редкость:", StringComparison.Ordinal)
                || text.Contains("Класс предмета:", StringComparison.Ordinal));
    }

    private async Task CaptureAsync() => await CaptureCoreAsync(sendKeys: true);

    /// The capture, with the game-facing half removable.
    ///
    /// Everything after "read the clipboard" is the same code either way, so the live check can run the
    /// real clipboard path - the emptiness test, the "is this an item" test, the reveal, the engine
    /// call, the card, src\last_item.txt - without pressing keys into a game that may not be running.
    private async Task CaptureCoreAsync(bool sendKeys)
    {
        try
        {
            var captureWatch = System.Diagnostics.Stopwatch.StartNew();
            var before = Native.GetClipboardSequenceNumber();
            uint after;
            // The panel may own the focus after being dragged or resized, and then Ctrl+C lands in it.
            // Handing the focus back to the game first is what makes a single Ctrl+Q work every time.
            if (sendKeys)
            {
                GameFocus.Bring();
                InputSender.CtrlC();
                await Task.Delay(170);
                after = Native.GetClipboardSequenceNumber();
                Log.Write($"capture timing: Ctrl+C sent and waited, {captureWatch.ElapsedMilliseconds} ms");
            }
            else
            {
                // The clipboard already holds what the game would have put there.
                after = before;
                Log.Write("capture(live check): clipboard read without pressing anything in the game");
            }
            var itemText = Clipboard.GetText();
            // Only Ctrl+Q is asked of the player. The game ignores injected keys now and then, so the
            // copy is repeated until the clipboard holds an item instead of a stray line of text. The
            // pauses are short on purpose: six slow attempts add up to two seconds of waiting with the
            // game's own busy cursor on screen when there is nothing to copy at all.
            for (var attempt = 0; sendKeys && attempt < 6 && !LooksLikeItem(itemText); attempt++)
            {
                await Task.Delay(60);
                InputSender.CtrlC();
                await Task.Delay(140);
                after = Native.GetClipboardSequenceNumber();
                itemText = Clipboard.GetText();
                Log.Write($"capture: retry {attempt + 1}, {itemText?.Length ?? 0} characters");
            }
            Log.Write($"capture: clipboard sequence {before} -> {after}, {itemText?.Length ?? 0} characters");
            // When no item arrived the card is left exactly as it is: showing an error in its place made
            // the panel look like it had emptied itself a couple of seconds after it opened.
            if (!LooksLikeItem(itemText))
            {
                Log.Write($"capture: no item in the clipboard ({itemText?.Length ?? 0} characters), the card is untouched");
                return;
            }
            Log.Write($"capture timing: clipboard read, {captureWatch.ElapsedMilliseconds} ms");
            if (string.IsNullOrWhiteSpace(itemText))
            {
                await RunAsync("window.showEngineError(" + EngineErrorScript("clipboardEmpty") + ")");
                return;
            }
            // The sequence only says whether the game copied something new. When it did not change - the
            // game ignores injected keys - the clipboard often still holds the item the player copied
            // a moment earlier, so the text itself decides. Without this the panel threw away good
            // data and stayed empty with an explanation that was not true.
            if (before == after && !LooksLikeItem(itemText))
            {
                await RunAsync("window.showEngineError(" + EngineErrorScript("captureRefused") + ")");
                return;
            }
            Log.Write($"capture timing: checks passed, {captureWatch.ElapsedMilliseconds} ms");
            Reveal("capture");
            await ShowItemAsync(itemText);

            // The text is kept for diagnosis, and the clipboard is emptied afterwards: a stale entry
            // left over from the previous capture is what once made the next one look like the game
            // had copied nothing at all.
            try
            {
                var keep = System.IO.Path.Combine(_engine.Root, "src", "last_item.txt");
                System.IO.File.WriteAllText(keep, itemText, new System.Text.UTF8Encoding(false));
                Clipboard.Clear();
                Log.Write("capture: saved to src\\last_item.txt, clipboard cleared");
            }
            catch (Exception error)
            {
                Log.Write("capture: tidy up failed: " + error.Message);
            }
            Log.Write($"capture timing: engine answered and card built, {captureWatch.ElapsedMilliseconds} ms");
        }
        catch (Exception error)
        {
            Log.Write("capture failed: " + error.Message);
        }
    }

    /// Reveals the panel so it can be checked, and returns where it ended up.
    //
    // Used by the position self-test: the place the player drags the panel to is meant to survive a
    // hide, and that is a property of this form rather than of the file, so it is checked on the form.
    public Point RevealAt(string why)
    {
        Reveal(why);
        return Location;
    }

    /// Hides the panel the same way a capture does, remembering the place first.
    public void HideForTest(string why = "test")
    {
        HidePanel(why);
    }

    /// Moves the panel, which is what a drag ends up doing.
    public void MoveTo(Point where)
    {
        Location = where;
    }

    // ---- live self-check ----------------------------------------------------------------------

    // What the check answers: the question headless rendering cannot. A page rendered by Chrome in a
    // temp folder proves the HTML is valid; it does not prove that THIS window, with THIS WebView2
    // runtime, draws the card the engine sent. So the check runs the real form, the real engine and the
    // real clipboard path, asserts on the live DOM, and keeps two pictures as evidence.

    /// Runs the check and returns 0 when every assertion held, 1 otherwise.
    public async Task<int> LiveCheckAsync()
    {
        var report = new List<string>();
        var failures = 0;

        void Check(string name, bool ok, string detail = "")
        {
            report.Add((ok ? "OK   " : "FAIL ") + name + (detail.Length == 0 ? "" : " (" + detail + ")"));
            if (!ok)
            {
                failures++;
            }
        }
        void Note(string name, string detail) =>
            report.Add("INFO " + name + (detail.Length == 0 ? "" : " (" + detail + ")"));

        var lastItemPath = Path.Combine(_engine.Root, "src", "last_item.txt");
        var samplePath = Path.Combine(_engine.Root, "samples", "rare_gloves.txt");
        var sourcePage = Path.Combine(_engine.Root, "overlay", "Ui", "panel.html");
        var builtPage = Path.Combine(AppContext.BaseDirectory, "Ui", "panel.html");

        // The player's clipboard, the last capture and the craft memory all belonged to the player
        // before this ran: all three are borrowed here and handed back in the finally block.
        var savedItem = File.Exists(lastItemPath) ? File.ReadAllText(lastItemPath) : null;
        var savedClipboard = ClipboardText();
        var memoryPath = Path.Combine(_engine.Root, "src", "craft_memory.lua");
        var savedMemory = File.Exists(memoryPath) ? File.ReadAllText(memoryPath) : null;
        try
        {
            var watch = System.Diagnostics.Stopwatch.StartNew();
            // How many processes this program can see, at each step. Not decoration: a program started
            // from a sandboxed working directory has been observed to see 17 of 334, which is exactly how
            // the game's window went missing, and this line says whether that is the situation here.
            Note("процессов до запуска движка", VisibleProcesses().ToString());
            // The engine first, on its own: the constructor's background warm-up is off in this mode so
            // that two requests can never be in flight at once.
            var prices = await _engine.CallAsync("prices");
            Check("движок запустился и ответил", prices is not null, $"{watch.ElapsedMilliseconds} мс");
            Note("процессов после запуска движка", VisibleProcesses().ToString());

            await InitializeAsync();
            Note("процессов после запуска WebView2", VisibleProcesses().ToString());
            var pageArrived = await Task.WhenAny(_loaded.Task, Task.Delay(30000)) == _loaded.Task && _loaded.Task.Result;
            Check("страница загрузилась в живом окне", pageArrived, $"{watch.ElapsedMilliseconds} мс");

            // The build copies Ui\** next to the exe, and a page edited without a rebuild is exactly the
            // bug that once looked like "the fix changed nothing". The window must run the edited page.
            Check("окно открыло свежую копию страницы", SameBytes(sourcePage, builtPage), builtPage);

            await Task.Delay(500);   // layout, the bundled font, the icons
            var sampleText = File.Exists(samplePath) ? File.ReadAllText(samplePath) : "";
            var sampleName = ItemName(sampleText);
            var sampleCard = await ReadDomTextAsync("step-view");
            Check("в живом окне нарисована карточка демо-предмета",
                sampleCard.Length > 40 && (sampleName.Length == 0 || sampleCard.Contains(sampleName)),
                $"{sampleCard.Length} символов, имя «{sampleName}»");

            // The capture half: the same path Ctrl+Q takes, minus the keys sent into the game.
            var captureFrom = File.Exists(lastItemPath) ? lastItemPath : samplePath;
            var itemText = File.ReadAllText(captureFrom);
            var itemName = ItemName(itemText);
            Check("предмет для захвата опознаётся как предмет игры", LooksLikeItem(itemText), Path.GetFileName(captureFrom));

            Clipboard.SetText(itemText);
            await CaptureCoreAsync(sendKeys: false);
            await Task.Delay(700);

            var capturedCard = await ReadDomTextAsync("step-view");
            Check("захват перерисовал карточку на этот предмет",
                itemName.Length > 0 && capturedCard.Contains(itemName), $"имя «{itemName}»");
            // The demo card must be GONE, otherwise "the card contains the item" would also hold for a
            // page that never repainted after the sample.
            Check("карточка перестала быть демо-предметом",
                sampleName.Length == 0 || itemName == sampleName || !capturedCard.Contains(sampleName),
                $"имя «{sampleName}»");
            Check("карточка после захвата не пустая", capturedCard.Length > 40, $"{capturedCard.Length} символов");
            var league = (await ReadDomTextAsync("league")).Trim();
            Check("лига в шапке собрана из ответа движка", league.Length > 0, league);

            var written = File.Exists(lastItemPath) ? File.ReadAllText(lastItemPath) : null;
            Check("последний захват записан в src\\last_item.txt",
                written is not null && Normalise(written) == Normalise(itemText), "текст совпадает");

            // Whether the game can be reached at all is the second half of "the panel captures": the
            // injection is useless if the window is not found, and that is exactly what the panel once
            // logged while the game sat on screen. Reported, not asserted: the check must also pass on a
            // machine where the game is not running.
            Note("процессов видно", VisibleProcesses().ToString());
            var gameWindow = GameFocus.DescribeGameWindow();
            Note("окно игры", gameWindow.Length == 0 ? "не найдено" : gameWindow);

            // The switch, end to end - the one path the headless page checks cannot cover, because it
            // crosses three things: the page asks, the host remembers and answers, the engine is asked
            // again in the other language. The player's own setting is put back afterwards.
            var originalSetting = _languageSetting;
            var target = _language == "ru" ? "en" : "ru";
            var cardBefore = await ReadDomTextAsync("step-view");
            await RunAsync($"chooseLanguage('{target}')");
            await Task.Delay(1200);
            var cardAfter = await ReadDomTextAsync("step-view");
            Check("переключатель в шапке переключает язык карточки",
                _language == target && cardAfter.Length > 40 && cardAfter != cardBefore,
                $"стало {_language}, {cardBefore.Length} -> {cardAfter.Length} символов");
            Check("выбор языка записан в файл", PanelLanguage.Load() == target, PanelLanguage.Load());
            await SetLanguageSettingAsync(originalSetting);
            await Task.Delay(600);

            // The pictures. PrintWindow on a WebView2 window is known to come back blank sometimes, so it
            // is reported, not asserted; the screen copy is exactly what the player would see.
            Reveal("live-check");
            await Task.Delay(800);
            var windowShot = WindowShot.CaptureDetailed(Handle,
                Path.Combine(AppContext.BaseDirectory, "live-window.png"), fromScreen: false);
            var screenShot = WindowShot.CaptureDetailed(Handle,
                Path.Combine(AppContext.BaseDirectory, "live-screen.png"), fromScreen: true);
            Note("снимок окна (PrintWindow)", windowShot.Message);
            Note("снимок экрана", screenShot.Message);
            Check("окно действительно нарисовано на экране",
                screenShot.Colours >= 24 && screenShot.DominantShare < 0.99,
                $"{screenShot.Colours} цветов, главный цвет занимает {screenShot.DominantShare:P1}");
        }
        catch (Exception error)
        {
            report.Add("FAIL живая проверка упала: " + error.Message);
            failures++;
            Log.Write("live check: threw " + error);
        }
        finally
        {
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
            }
            catch (Exception error)
            {
                Log.Write("live check: could not hand the clipboard back: " + error.Message);
            }
            try
            {
                if (savedItem is null)
                {
                    if (File.Exists(lastItemPath))
                    {
                        File.Delete(lastItemPath);
                    }
                }
                else
                {
                    File.WriteAllText(lastItemPath, savedItem, new System.Text.UTF8Encoding(false));
                }
            }
            catch (Exception error)
            {
                Log.Write("live check: could not hand src\\last_item.txt back: " + error.Message);
            }
            // The capture path writes the craft memory, exactly as a real capture does. A check that left
            // the player's memory pointing at a test item would put a lie in the next card, so it goes back
            // the way it was found (or away, if it was not there).
            try
            {
                if (savedMemory is null)
                {
                    if (File.Exists(memoryPath))
                    {
                        File.Delete(memoryPath);
                    }
                }
                else
                {
                    File.WriteAllText(memoryPath, savedMemory, new System.Text.UTF8Encoding(false));
                }
            }
            catch (Exception error)
            {
                Log.Write("live check: could not hand src\\craft_memory.lua back: " + error.Message);
            }
        }

        report.Insert(0, failures == 0
            ? "ЖИВАЯ ПРОВЕРКА ПРОЙДЕНА: настоящее окно WebView2 нарисовало карточку, присланную движком"
            : $"ЖИВАЯ ПРОВЕРКА НЕ ПРОЙДЕНА: не прошло проверок — {failures}");
        report.Insert(1, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} · {AppContext.BaseDirectory}");
        var reportPath = Path.Combine(AppContext.BaseDirectory, "live-check.txt");
        try
        {
            File.WriteAllLines(reportPath, report, new System.Text.UTF8Encoding(false));
        }
        catch (Exception error)
        {
            Log.Write("live check: could not write live-check.txt: " + error.Message);
        }
        foreach (var line in report)
        {
            Log.Write("live check: " + line);
        }
        return failures == 0 ? 0 : 1;
    }

    /// How many processes this program can see right now.
    /// Needed because the answer is not a constant: the panel once saw 24 of 342 while the same machine
    /// from the same user showed all of them, and that is why it could not find the game's window.
    private static int VisibleProcesses()
    {
        try
        {
            return System.Diagnostics.Process.GetProcesses().Length;
        }
        catch (Exception error)
        {
            Log.Write("process count failed: " + error.Message);
            return -1;
        }
    }

    /// What the live page actually contains, read back from the DOM.
    private async Task<string> ReadDomTextAsync(string elementId)
    {
        if (_browser.CoreWebView2 is null)
        {
            return "";
        }
        try
        {
            var script = $"document.getElementById('{elementId}').innerText";
            var json = await _browser.CoreWebView2.ExecuteScriptAsync(script);
            if (string.IsNullOrEmpty(json) || json == "null")
            {
                return "";
            }
            return System.Text.Json.JsonSerializer.Deserialize<string>(json) ?? "";
        }
        catch (Exception error)
        {
            Log.Write($"live check: reading '{elementId}' from the page failed: {error.Message}");
            return "";
        }
    }

    /// The name of a copied item: the first line below the rarity line.
    private static string ItemName(string itemText)
    {
        var lines = itemText.Split('\n');
        for (var index = 0; index + 1 < lines.Length; index++)
        {
            var line = lines[index].Trim();
            if (!line.StartsWith("Rarity:", StringComparison.Ordinal) && !line.StartsWith("Редкость:", StringComparison.Ordinal))
            {
                continue;
            }
            for (var next = index + 1; next < lines.Length; next++)
            {
                var name = lines[next].Trim();
                if (name.Length > 0)
                {
                    return name;
                }
            }
        }
        return "";
    }

    /// The clipboard line ending is CRLF and a file may keep LF: the text is the same item either way.
    private static string Normalise(string text) => text.Replace("\r\n", "\n");

    private static string? ClipboardText()
    {
        try
        {
            return Clipboard.ContainsText() ? Clipboard.GetText() : null;
        }
        catch
        {
            return null;
        }
    }

    private static bool SameBytes(string left, string right)
    {
        try
        {
            return File.Exists(left) && File.Exists(right)
                && File.ReadAllBytes(left).AsSpan().SequenceEqual(File.ReadAllBytes(right));
        }
        catch
        {
            return false;
        }
    }

    // ---- window behaviour ---------------------------------------------------------------------

    private void Reveal(string why)
    {
        // Comes back from off screen: no flash, because the window was already rendering.
        // A position the player chose wins over the default corner, but only when it is still on a
        // monitor: a stale or parked position would show the panel where nobody can see it, which is
        // what made it look as if the panel had disappeared for good after the game was minimised.
        var wanted = _shotMode ? CenterOfScreen() : (_placed ?? OnScreen);
        if (!PanelPosition.IsVisiblePlace(wanted) && _placed.HasValue)
        {
            // The remembered place is not fully usable. Clamp it rather than replacing it with the
            // default corner: a panel left half off an edge is a normal thing to do, and snapping it to
            // the default is what reads as "the panel forgot where I put it".
            var clamped = PanelPosition.ClampToScreen(wanted, Size);
            Log.Write(string.Format("panel: remembered place {0},{1} is not fully visible, clamping to {2},{3}",
                wanted.X, wanted.Y, clamped.X, clamped.Y));
            wanted = clamped;
            _placed = clamped;
        }
        else if (!PanelPosition.IsVisiblePlace(wanted))
        {
            Log.Write(string.Format("panel: place {0},{1} is not on any screen, using the default",
                wanted.X, wanted.Y));
            wanted = OnScreen;
            _placed = null;
        }
        Location = wanted;
        Show();
        TopMost = true;
        BringToFront();
        _revealedAt = DateTime.UtcNow;
        Log.Write($"panel shown ({why}) at {Location.X},{Location.Y}; visible {Visible}, state {WindowState}");
        // Does anything move the window AFTER it is shown? The place is written on hide, so a window that
        // drifts right after Show() would be remembered at the drifted position while the player saw a
        // different one - the log has to answer that, not a guess.
        var shownAt = Location;
        BeginInvoke(new Action(() =>
        {
            if (IsDisposed || Disposing)
            {
                return;
            }
            if (Location != shownAt)
            {
                Log.Write(string.Format(
                    "panel: the window moved on its own from {0},{1} to {2},{3} after being shown ({4})",
                    shownAt.X, shownAt.Y, Location.X, Location.Y, why));
            }
        }));
    }

    /// Hides the panel and remembers where it was. Every path that hides the card goes through here,
    /// so the place the player chose survives the next capture.
    private void HidePanel(string why = "")
    {
        RememberPlace();
        Hide();
        if (why != "")
        {
            Log.Write($"panel hidden ({why})");
        }
    }

    /// Remembers where the panel is, called wherever it stops being visible.
    private void RememberPlace()
    {
        if (!Visible)
        {
            return;
        }
        // Visible is not enough on its own: the window stays visible while it is parked off screen,
        // and saving that parking spot is what made the panel come back out of sight. PanelPosition
        // refuses such a place itself, so both halves agree on what counts as a real position.
        _placed = Location;
        PanelPosition.Save(Location, "hide");
    }

    private Point CenterOfScreen()
    {
        var area = Screen.PrimaryScreen?.WorkingArea ?? new Rectangle(0, 0, 1920, 1080);
        return new Point((area.Width - Width) / 2 + area.Left, (area.Height - Height) / 2 + area.Top);
    }

    private void AutoHide()
    {
        // Auto hiding is gone on purpose: the card stays on screen while crafting and leaves only when
        // the player closes it with the button in its corner.
    }

    /// WS_EX_TRANSPARENT and nothing else: WebView2 draws in an ordinary window, so the layered style
    /// that broke it before is never applied.
    private void ApplyClickThrough()
    {
        var style = Native.GetWindowLong(Handle, Native.GwlExStyle);
        style = _clickThrough
            ? (style | Native.WsExTransparent) & ~Native.WsExLayered
            : (style & ~Native.WsExTransparent) & ~Native.WsExLayered;
        Native.SetWindowLong(Handle, Native.GwlExStyle, style);
        Log.Write($"panel: click-through {(_clickThrough ? "on" : "off")}");
    }

    private void WatchKeys()
    {
        var f7 = (Native.GetAsyncKeyState(Native.VkF7) & 0x8000) != 0;
        if (f7 && !_f7) { if (Visible) { HidePanel("F7"); } else { Reveal("F7"); } }
        _f7 = f7;

        var f9 = (Native.GetAsyncKeyState(Native.VkF9) & 0x8000) != 0;
        if (f9 && !_f9) { _clickThrough = !_clickThrough; ApplyClickThrough(); }
        _f9 = f9;

        var f10 = (Native.GetAsyncKeyState(Native.VkF10) & 0x8000) != 0;
        if (f10 && !_f10) { Log.Write("quit requested with F10"); Close(); }
        _f10 = f10;

        // Ctrl+Q is handled by the shell hot key alone. The polled watcher used to fire it as well, so
        // one press started two captures that fought over the same window - the log showed "Ctrl+Q
        // pressed" twice, and the second one found the form already disposed.
    }

    /// The panel never activates: it must not steal the game's focus.
    protected override bool ShowWithoutActivation => true;

    public void RevealFromTray() => BeginInvoke(new Action(() => Reveal("tray")));
    public void CaptureFromTray() => BeginInvoke(new Action(() => _ = CaptureAsync()));
    public void QuitFromTray() => BeginInvoke(new Action(() =>
    {
        // Closing the form alone left the agent alive when the exit came from the tray menu, so the
        // process is ended explicitly after the form has disposed the engine and the tray icon.
        Log.Write("tray: quit requested, closing the agent and the engine");
        _reallyQuit = true;
        Close();
        System.Windows.Forms.Application.ExitThread();
        Environment.Exit(0);
    }));

    private void SaveShot()
    {
        var folder = AppContext.BaseDirectory;
        Log.Write("shot: " + WindowShot.Capture(Handle, Path.Combine(folder, "shot-window.png"), fromScreen: false));
        Log.Write("shot: " + WindowShot.Capture(Handle, Path.Combine(folder, "shot-screen.png"), fromScreen: true));
        Close();
    }
}
