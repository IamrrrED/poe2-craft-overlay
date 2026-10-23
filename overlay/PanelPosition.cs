using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Windows.Forms;

namespace Poe2CraftOverlay;

/// Remembers where the player put the panel.
///
/// The card is hidden rather than closed when it is not needed, and showing it again used to put it
/// back at its default corner - a panel dragged out of the way snapped back on the next capture. The
/// place is kept in a small file next to the executable, because it has to survive a restart as well.
///
/// Only a position the player can actually see is ever remembered. The window is parked far off
/// screen to keep it out of the way, and it stays "visible" while parked, so a guard on Visible alone
/// let that parking spot be saved as if it were a real place - after which the panel was shown off
/// screen and looked as if it had vanished for good.
internal static class PanelPosition
{
    /// Anything at or beyond this is a parking spot, not a place on the desktop.
    private const int OffScreenThreshold = -20000;

    /// Where the place is kept.
    //
    // Next to the executable is convenient but fragile: the position file lives in the build output
    // directory, and every rebuild replaces that directory's contents - so the place the player chose
    // is lost by the next build, which reads exactly like "the panel forgets where I put it". The
    // durable copy lives in the user's local application data instead, and the old location is still
    // read so an existing place is not thrown away.
    private static string DurablePath => System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Poe2CraftOverlay", "panel-position.ini");

    private static string LegacyPath => System.IO.Path.Combine(AppContext.BaseDirectory, "panel-position.ini");

    /// The files to try, in order: the durable one first, then the old one beside the executable.
    private static IEnumerable<string> CandidatePaths()
    {
        yield return DurablePath;
        yield return LegacyPath;
    }

    /// Is this position somewhere the player could actually use the panel?
    //
    // It is not enough for a corner to touch a monitor: a position just below the bottom edge, or
    // pushed so far to the right that only a sliver shows, is invisible in practice. The measured
    // case was 0,1364 with a 1392 pixel high working area - entirely under the screen, and still
    // accepted, so the panel was shown there and looked as if it had vanished for good. A named
    // amount of the panel has to be inside a working area instead.
    public static bool IsVisiblePlace(Point location)
    {
        if (location.X <= OffScreenThreshold || location.Y <= OffScreenThreshold)
        {
            return false;
        }
        const int neededWidth = 120;    // enough of the title bar to grab and drag
        const int neededHeight = 80;    // enough of the card to read
        foreach (var screen in Screen.AllScreens)
        {
            var visible = Rectangle.Intersect(screen.WorkingArea,
                new Rectangle(location, new Size(neededWidth, neededHeight)));
            if (visible.Width >= neededWidth && visible.Height >= neededHeight)
            {
                return true;
            }
        }
        return false;
    }

    /// Pull a position back so the panel is usable on some monitor.
    //
    // The saved place is used as it is when it is fully usable. It is not thrown away when only part of
    // the panel hangs off the edge - a panel left near an edge is a normal thing to do, and snapping it
    // to the default corner reads as "it forgot where I put it". This clamps instead: the title bar and
    // a readable strip of the card are brought back on screen.
    // @param location wanted position
    // @param size panel size
    /// @return a position that is at least partly visible
    public static Point ClampToScreen(Point location, Size size)
    {
        if (IsVisiblePlace(location))
        {
            return location;
        }
        var screen = Screen.FromPoint(location) ?? Screen.PrimaryScreen;
        if (screen is null)
        {
            return location;
        }
        var area = screen.WorkingArea;
        var x = Math.Max(area.Left, Math.Min(location.X, area.Right - 40));
        var y = Math.Max(area.Top, Math.Min(location.Y, area.Bottom - 30));
        return new Point(x, y);
    }

    /// The last position the panel was seen at, or null when there is none to trust.
    //
    // The NEWEST usable copy wins, not the first one found. An elevated run creates the durable copy in
    // the user's folder, and a later non-elevated run cannot overwrite it ("access denied" - the same
    // thing the log shows for the language file), so the durable copy can be stale while the copy beside
    // the exe is fresh. Reading the first copy would then undo the move the player just made.
    public static Point? Load()
    {
        Point? best = null;
        var bestWritten = DateTime.MinValue;
        foreach (var path in CandidatePaths())
        {
            try
            {
                if (!File.Exists(path))
                {
                    continue;
                }
                var written = File.GetLastWriteTimeUtc(path);
                var parts = File.ReadAllText(path).Trim().Split(',');
                if (parts.Length != 2
                    || !int.TryParse(parts[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out var x)
                    || !int.TryParse(parts[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out var y))
                {
                    continue;
                }
                var wanted = new Point(x, y);
                if (!IsVisiblePlace(wanted))
                {
                    Log.Write($"panel: saved position {x},{y} in {path} is not on screen, ignoring it");
                    continue;
                }
                if (written >= bestWritten)
                {
                    best = wanted;
                    bestWritten = written;
                    Log.Write($"panel: place {x},{y} read from {path} (written {written:u})");
                }
            }
            catch (Exception error)
            {
                Log.Write($"panel: could not read the saved position from {path}: {error.Message}");
            }
        }
        return best;
    }

    /// Stores the position, unless it is one of the off screen parking spots.
    //
    // Every write is logged with the reason: when a position turns out to be wrong, the log has to say
    // which code path produced it, or the next investigation starts from guesses again. Both copies are
    // written, so the place survives a rebuild (the durable copy) and is still found by an older build
    // that only knows the local one.
    public static void Save(Point location, string reason)
    {
        if (!IsVisiblePlace(location))
        {
            Log.Write($"panel: not saving place {location.X},{location.Y} from {reason}: not on screen");
            return;
        }
        var text = string.Format(CultureInfo.InvariantCulture, "{0},{1}", location.X, location.Y);
        foreach (var path in CandidatePaths())
        {
            try
            {
                var folder = System.IO.Path.GetDirectoryName(path);
                if (!string.IsNullOrEmpty(folder))
                {
                    Directory.CreateDirectory(folder);
                }
                File.WriteAllText(path, text);
                Log.Write($"panel: place {location.X},{location.Y} saved from {reason} to {path}");
            }
            catch (Exception error)
            {
                Log.Write($"panel: could not save the position to {path}: {error.Message}");
            }
        }
    }
}
