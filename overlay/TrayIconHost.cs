using System.Drawing;
using System.Threading;
using System.Windows.Forms;

namespace Poe2CraftOverlay;

/// The tray menu's own words, in the panel's language.
///
/// The engine speaks whatever the panel asks for, but the tray menu is drawn by Windows, so its labels
/// have to be carried along here and replaced when the language changes.
internal sealed record TrayLabels(
    string Show,
    string Capture,
    string Language,
    string LanguageAuto,
    string LanguageRu,
    string LanguageEn,
    string Quit,
    string BalloonTitle,
    string BalloonText);

/// The tray icon, on its own thread with its own WinForms message loop.
///
/// A NotifyIcon only registers when the thread that created it keeps pumping messages for it.
/// Created from the Avalonia thread it reported success and showed nothing, which is exactly what
/// the player saw. Here the icon lives on an STA thread that runs Application.Run, so the shell
/// gets a real window to talk to.
internal sealed class TrayIconHost : IDisposable
{
    private Thread? _thread;
    private NotifyIcon? _icon;
    private ContextMenuStrip? _menu;
    private ToolStripMenuItem? _showItem;
    private ToolStripMenuItem? _captureItem;
    private ToolStripMenuItem? _languageItem;
    private ToolStripMenuItem? _autoItem;
    private ToolStripMenuItem? _russianItem;
    private ToolStripMenuItem? _englishItem;
    private ToolStripMenuItem? _quitItem;
    private SynchronizationContext? _context;
    private bool _ready;
    private volatile bool _quit;

    public void Show(Icon icon, TrayLabels labels, Action onShow, Action onCapture,
        Action onLanguageAuto, Action onLanguageRu, Action onLanguageEn, Action onQuit)
    {
        if (_thread is not null)
        {
            Log.Write("tray: already created, second icon refused");
            return;
        }
        _thread = new Thread(() =>
        {
            try
            {
                _menu = new ContextMenuStrip();
                _showItem = new ToolStripMenuItem(labels.Show, null, (_, _) => onShow());
                _captureItem = new ToolStripMenuItem(labels.Capture, null, (_, _) => onCapture());
                // Three states because "follow the game" is a real choice, not a missing value: the
                // engine reads the client's language out of the copied item.
                _autoItem = new ToolStripMenuItem(labels.LanguageAuto, null, (_, _) => onLanguageAuto());
                _russianItem = new ToolStripMenuItem(labels.LanguageRu, null, (_, _) => onLanguageRu());
                _englishItem = new ToolStripMenuItem(labels.LanguageEn, null, (_, _) => onLanguageEn());
                _languageItem = new ToolStripMenuItem(labels.Language);
                _languageItem.DropDownItems.Add(_autoItem);
                _languageItem.DropDownItems.Add(_russianItem);
                _languageItem.DropDownItems.Add(_englishItem);
                _quitItem = new ToolStripMenuItem(labels.Quit, null, (_, _) => onQuit());

                _menu.Items.Add(_showItem);
                _menu.Items.Add(_captureItem);
                _menu.Items.Add(_languageItem);
                _menu.Items.Add(new ToolStripSeparator());
                _menu.Items.Add(_quitItem);

                _icon = new NotifyIcon
                {
                    Icon = icon,
                    Text = "PoE2 Craft Overlay — Ctrl+Q захват предмета",
                    Visible = true,
                    ContextMenuStrip = _menu,
                };
                _icon.MouseClick += (_, args) =>
                {
                    if (args.Button == MouseButtons.Left)
                    {
                        onShow();
                    }
                };
                // Captured here, inside the WinForms loop: this is the thread the icon belongs to, and
                // every later call (a balloon, a menu action) has to come back to it.
                _context = SynchronizationContext.Current;
                _ready = true;
                Log.Write("tray: icon created on its own message loop");
                // ApplicationContext without a main form returns at once, so the icon was removed the
                // moment it appeared - the shell showed nothing while this log said "created". A plain
                // DoEvents loop keeps the thread alive; that is the variant verified on this machine
                // with a standalone NotifyIcon, which the player could see.
                _quit = false;
                while (!_quit)
                {
                    Application.DoEvents();
                    Thread.Sleep(40);
                }
            }
            catch (Exception error)
            {
                Log.Write("tray thread failed: " + error.Message);
            }
        })
        {
            IsBackground = true,
            Name = "PoE2 overlay tray",
        };
        _thread.SetApartmentState(ApartmentState.STA);
        _thread.Start();
        Log.Write("tray: thread started (STA with its own message loop)");
    }

    /// Replaces the menu's words, and ticks the language the player is on.
    /// Called from the panel's thread, so it hops to the tray's own one.
    public void SetLabels(TrayLabels labels, string languageSetting)
    {
        Post(() =>
        {
            if (_menu is null)
            {
                return;
            }
            if (_showItem is not null) { _showItem.Text = labels.Show; }
            if (_captureItem is not null) { _captureItem.Text = labels.Capture; }
            if (_languageItem is not null) { _languageItem.Text = labels.Language; }
            if (_autoItem is not null)
            {
                _autoItem.Text = labels.LanguageAuto;
                _autoItem.Checked = languageSetting == PanelLanguage.Auto;
            }
            if (_russianItem is not null)
            {
                _russianItem.Text = labels.LanguageRu;
                _russianItem.Checked = languageSetting == PanelLanguage.Russian;
            }
            if (_englishItem is not null)
            {
                _englishItem.Text = labels.LanguageEn;
                _englishItem.Checked = languageSetting == PanelLanguage.English;
            }
            if (_quitItem is not null) { _quitItem.Text = labels.Quit; }
            Log.Write("tray: menu labels updated for language " + languageSetting);
        });
    }

    /// A balloon is the launch signal that cannot hide in the collapsed tray area.
    public void Announce(string title, string text)
    {
        Post(() =>
        {
            try
            {
                _icon?.ShowBalloonTip(6000, title, text, ToolTipIcon.Info);
                Log.Write("tray: launch balloon shown");
            }
            catch (Exception error)
            {
                Log.Write("tray balloon failed: " + error.Message);
            }
        });
    }

    private void Post(Action action)
    {
        if (!_ready || _context is null)
        {
            // The thread may still be starting; give it a moment and try once from the caller.
            Thread.Sleep(150);
            _context?.Post(_ => action(), null);
            return;
        }
        _context.Post(_ => action(), null);
    }

    public void Dispose()
    {
        try
        {
            Post(() =>
            {
                if (_icon is not null)
                {
                    _icon.Visible = false;
                    _icon.Dispose();
                    _icon = null;
                }
                Application.ExitThread();
            });
        }
        catch
        {
            // shutting down anyway
        }
    }
}
