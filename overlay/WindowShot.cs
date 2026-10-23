using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Poe2CraftOverlay;

/// Takes a picture of the overlay window, so the interface can be checked without asking the player
/// to describe it. PrintWindow asks the window to draw itself (it works for some composited content);
/// a screen copy is taken as well, because that is exactly what the player sees.
internal static class WindowShot
{
    [DllImport("user32.dll")]
    private static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindowDC(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    /// The picture plus what is on it. A window whose browser never painted comes back as one flat
    /// colour, and no amount of reading the code tells that apart from a drawn card - the pixels do.
    public readonly record struct Shot(string Message, int Colours, double DominantShare);

    public static string Capture(IntPtr hwnd, string path, bool fromScreen) =>
        CaptureDetailed(hwnd, path, fromScreen).Message;

    public static Shot CaptureDetailed(IntPtr hwnd, string path, bool fromScreen)
    {
        if (!GetWindowRect(hwnd, out var rect))
        {
            return new Shot("window rect unavailable", 0, 1);
        }
        var width = rect.Right - rect.Left;
        var height = rect.Bottom - rect.Top;
        if (width <= 0 || height <= 0)
        {
            return new Shot("window has no area", 0, 1);
        }

        using var bitmap = new Bitmap(width, height, PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            if (fromScreen)
            {
                graphics.CopyFromScreen(rect.Left, rect.Top, 0, 0, new Size(width, height), CopyPixelOperation.SourceCopy);
            }
            else
            {
                var hdc = graphics.GetHdc();
                try
                {
                    PrintWindow(hwnd, hdc, 2);      // 2 = PW_RENDERFULLCONTENT
                }
                finally
                {
                    graphics.ReleaseHdc(hdc);
                }
            }
        }
        bitmap.Save(path, ImageFormat.Png);
        var (colours, dominant) = Measure(bitmap);
        return new Shot($"saved {width}x{height} to {path}, {colours} colours, dominant {dominant:P1}", colours, dominant);
    }

    /// How many different colours are on the picture, and how much of it the most common one covers.
    /// Sampling every other pixel is enough: a card that failed to draw has exactly one colour.
    private static (int Colours, double DominantShare) Measure(Bitmap bitmap)
    {
        var counts = new System.Collections.Generic.Dictionary<int, int>();
        var total = 0;
        for (var y = 0; y < bitmap.Height; y += 2)
        {
            for (var x = 0; x < bitmap.Width; x += 2)
            {
                var colour = bitmap.GetPixel(x, y).ToArgb();
                counts[colour] = counts.TryGetValue(colour, out var seen) ? seen + 1 : 1;
                total++;
            }
        }
        if (total == 0)
        {
            return (0, 1);
        }
        var largest = 0;
        foreach (var count in counts.Values)
        {
            if (count > largest)
            {
                largest = count;
            }
        }
        return (counts.Count, (double)largest / total);
    }
}