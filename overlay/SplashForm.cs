using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Threading;
using System.Windows.Forms;

namespace Poe2CraftOverlay;

/// The launch indicator: the mushroom picture from Ui/mushroom.png, with a drawn mushroom standing in
/// when that file is missing.
///
/// The picture is a detailed illustration, so it gets a gentle hop and nothing else: squeezing it
/// (which the drawn mushroom does) only smears the fine texture. The window is sized to the picture,
/// and the transparency key is dark on purpose - it is an exact match, so the anti aliased edge keeps
/// a rim of it, and a dark rim reads as an outline instead of the magenta one it used to be. The
/// window never activates, so it cannot steal the game's focus.
///
/// The per pixel version of this (a layered window with UpdateLayeredWindow) was built and abandoned:
/// on this machine that call answers ERROR_GEN_FAILURE (31) for every source surface - a GDI+ bitmap
/// selected into a memory context and a 32bpp top-down DIB section alike - while
/// SetLayeredWindowAttributes is accepted, so layered windows themselves are not blocked. Until that
/// is understood, the transparency key is what works. See docs/SESSION-HANDOFF.md.
internal sealed class SplashForm : Form
{
    private const int KeyR = 18, KeyG = 13, KeyB = 12;

    /// Where the mushroom stands inside the window. The frame is drawn around this point.
    private const float AnchorX = 90f;
    private const float AnchorY = 107f;

    /// The picture is drawn at its own size, centred on the anchor. These mirror the file produced by
    /// tools/make_indicator.py (TARGET_WIDTH there), trimmed before it is saved, so a change there
    /// means a change here. Halved on request: it was 320x380 in a 360x420 window.
    private const float ArtWidth = 160f;
    private const float ArtHeight = 190f;

    /// The hop, in pixels. The window has room: (220 - 190) / 2 = 15.
    private const double HopAmplitude = 4.0;

    private readonly System.Windows.Forms.Timer _tick = new() { Interval = 33 };
    private readonly System.Windows.Forms.Timer _close = new() { Interval = 5000 };
    private double _phase;

    private static SplashForm? _open;
    private static Image? _art;
    private static bool _artProbed;

    private SplashForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.CenterScreen;
        TopMost = true;
        ShowInTaskbar = false;
        BackColor = Color.FromArgb(KeyR, KeyG, KeyB);
        TransparencyKey = BackColor;
        ClientSize = new Size(180, 220);
        DoubleBuffered = true;

        _tick.Tick += (_, _) => { _phase += 0.14; Invalidate(); };
        _close.Tick += (_, _) => { _close.Stop(); _tick.Stop(); Close(); };
    }

    protected override bool ShowWithoutActivation => true;

    /// Closes the mushroom early. Kept for callers that want it gone before its five seconds are up.
    public static void CloseNow()
    {
        var open = _open;
        if (open is null || open.IsDisposed)
        {
            return;
        }
        try
        {
            open.BeginInvoke(new Action(open.Close));
        }
        catch
        {
            // already closing
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        // The hop is shared; the sway and the squash belong to the drawing only.
        var bounce = (float)(Math.Sin(_phase) * HopAmplitude);

        // The artwork, when it is there, replaces the drawn mushroom entirely rather than being layered
        // over it: two mushrooms in one window would read as a smudge.
        var art = Art();
        if (art is not null)
        {
            g.TranslateTransform(AnchorX, AnchorY - bounce);
            g.DrawImage(art, -ArtWidth / 2f, -ArtHeight / 2f, ArtWidth, ArtHeight);
            return;
        }

        var lean = (float)(Math.Sin(_phase * 0.7) * 3.0);
        var squash = 1f + (float)(Math.Sin(_phase) * 0.06);
        g.TranslateTransform(AnchorX + lean, AnchorY - bounce);
        g.ScaleTransform(1f / squash, squash);

        // The drawing is smaller than the picture, so it is scaled up to fill the same window.
        const float drawnScale = 1.15f;
        g.ScaleTransform(drawnScale, drawnScale);

        // One silhouette, two colours. The whole shape is one path, so there is no seam between cap and
        // stem, but filling it with a single brush painted the stem red as well. The cap goes on first,
        // then the stem is painted inside the silhouette - still one solid outline, now with a light
        // stem and a red cap.
        using (var body = new GraphicsPath())
        using (var stemShape = RoundedRect(new RectangleF(-17, -16, 34, 82), 14))
        {
            body.AddEllipse(new RectangleF(-62, -74, 124, 82));   // the dome
            body.AddPath(stemShape, false);                      // the stem

            using (var cap = new LinearGradientBrush(new RectangleF(-62, -74, 124, 82),
                       Color.FromArgb(255, 228, 72, 56), Color.FromArgb(255, 172, 32, 26), 90f))
            {
                g.FillPath(cap, body);
            }

            var saved = g.Save();
            // Clipped to the stem's own rounded shape rather than to the whole silhouette: clipped to
            // the silhouette, the fill rectangle runs up into the dome and turns its middle pale. The
            // rectangle itself is taller than the stem on purpose - the stem's rounded top is what
            // decides where the light colour stops, so no band of the key colour can show between cap
            // and stem.
            g.SetClip(stemShape);
            using (var stem = new LinearGradientBrush(new RectangleF(-17, -16, 34, 82),
                       Color.FromArgb(255, 253, 250, 242), Color.FromArgb(255, 208, 198, 176), 90f))
            {
                g.FillRectangle(stem, -17, -30, 34, 100);
            }
            g.Restore(saved);
        }

        // Spots on the dome.
        using (var spot = new SolidBrush(Color.FromArgb(240, 255, 250, 240)))
        {
            g.FillEllipse(spot, -40, -58, 19, 14);
            g.FillEllipse(spot, 12, -64, 16, 12);
            g.FillEllipse(spot, -10, -42, 13, 10);
            g.FillEllipse(spot, 32, -38, 11, 9);
        }

        // A soft highlight that breathes with the bounce - light, not a shadow.
        using (var gloss = new SolidBrush(Color.FromArgb(120, 255, 255, 255)))
        {
            var size = 20f + (float)(Math.Sin(_phase * 1.6) * 2.0);
            g.FillEllipse(gloss, -46, -62, size, size * 0.65f);
        }

        // Face on the stem: eyes blink and the pupils wander, the smile widens with the bounce.
        using (var ink = new SolidBrush(Color.FromArgb(255, 74, 52, 44)))
        {
            var blink = Math.Sin(_phase * 0.9) > 0.93;
            var eyeH = blink ? 2f : 9f;
            g.FillEllipse(ink, -12, 10, 8, eyeH);
            g.FillEllipse(ink, 4, 10, 8, eyeH);
            if (!blink)
            {
                var look = (float)(Math.Sin(_phase * 0.45) * 2.0);
                using (var white = new SolidBrush(Color.FromArgb(235, 255, 255, 255)))
                {
                    g.FillEllipse(white, -10f + look, 11.5f, 2.8f, 2.8f);
                    g.FillEllipse(white, 6f + look, 11.5f, 2.8f, 2.8f);
                }
            }
            var smile = new RectangleF(-11, 24, 22, 7f + (float)(Math.Sin(_phase) * 2.0));
            using (var pen = new Pen(ink, 2.6f))
            {
                g.DrawArc(pen, smile, 20, 140);
            }
        }
    }

    /// The mushroom artwork, read once and kept for the life of the process. A missing file is not an
    /// error: the drawn mushroom stands in, so a build without the picture still shows something.
    private static Image? Art()
    {
        if (_art is not null || _artProbed)
        {
            return _art;
        }

        _artProbed = true;
        try
        {
            var path = Path.Combine(AppContext.BaseDirectory, "Ui", "mushroom.png");
            if (!File.Exists(path))
            {
                Log.Write("splash: Ui/mushroom.png not found, drawing the mushroom instead");
                return null;
            }

            // FromStream into a copy: Image.FromFile keeps the file open, and a locked file in the
            // output folder makes the next build fail with a copy error.
            using var stream = File.OpenRead(path);
            using var loaded = Image.FromStream(stream);
            _art = new Bitmap(loaded);
            Log.Write("splash: Ui/mushroom.png loaded (" + _art.Width + "x" + _art.Height + ")");
        }
        catch (Exception error)
        {
            // A corrupt or half-copied picture must not take the indicator down with it.
            Log.Write("splash: Ui/mushroom.png unreadable (" + error.Message + "), drawing the mushroom instead");
            _art = null;
        }

        return _art;
    }

    private static GraphicsPath RoundedRect(RectangleF rect, float radius)
    {
        var path = new GraphicsPath();
        var d = radius * 2;
        path.AddArc(rect.Left, rect.Top, d, d, 180, 90);
        path.AddArc(rect.Right - d, rect.Top, d, d, 270, 90);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
        path.AddArc(rect.Left, rect.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    public static void ShowBriefly()
    {
        var thread = new Thread(() =>
        {
            try
            {
                using var form = new SplashForm();
                _open = form;
                form._tick.Start();
                form._close.Start();
                Application.Run(form);
                _open = null;
                Log.Write("splash: mushroom shown and closed");
            }
            catch (Exception error)
            {
                Log.Write("splash failed: " + error.Message);
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
