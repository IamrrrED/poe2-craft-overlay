using System.Runtime.InteropServices;

namespace Poe2CraftOverlay;

/// The Win32 calls that turn a normal window into an overlay: no clicks, no focus, always on top.
internal static class Native
{
    public const int GwlExStyle = -20;
    public const int WsExTransparent = 0x00000020;
    public const int WsExLayered = 0x00080000;
    public const int WsExToolWindow = 0x00000080;
    public const int WsExNoActivate = 0x08000000;

    public static readonly IntPtr HwndTopmost = new(-1);
    public const uint SwpNoSize = 0x0001;
    public const uint SwpNoMove = 0x0002;
    public const uint SwpNoActivate = 0x0010;

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    /// 0 hides, 5 shows without activating: revealing the panel must not steal the game's focus.
    public const int SwHide = 0;
    public const int SwShowNoActivate = 4;

    /// Ctrl+Q is the capture key: the same combination the price-check tools use, and the one
    /// the player already has in muscle memory.
    public const int VkControl = 0x11;
    public const int VkQ = 0x51;

    public const int VkF6 = 0x75;
    public const int VkF7 = 0x76;
    public const int VkF9 = 0x78;
    public const int VkF10 = 0x79;
    /// Sends Ctrl+C to whatever window has the focus: the player is in the game, so that is the game.
    /// The game may ignore synthetic input, which is why the clipboard sequence number is checked
    /// afterwards instead of trusting the press.
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern uint GetClipboardSequenceNumber();

    public const byte VkControlByte = 0x11;
    public const byte VkCByte = 0x43;
    public const uint KeyEventKeyUp = 0x0002;

    public static void SendCtrlC()
    {
        keybd_event(VkControlByte, 0, 0, UIntPtr.Zero);
        keybd_event(VkCByte, 0, 0, UIntPtr.Zero);
        keybd_event(VkCByte, 0, KeyEventKeyUp, UIntPtr.Zero);
        keybd_event(VkControlByte, 0, KeyEventKeyUp, UIntPtr.Zero);
    }
    /// The WebView2 is a child window of ours, and Avalonia paints its own surface as a sibling. If
    /// the surface ends up above the browser, the panel looks like an empty grey window even though
    /// the page loaded: raising every child to the top puts the browser back in front.
    public delegate bool EnumChildProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr hWndParent, EnumChildProc lpEnumFunc, IntPtr lParam);

    public static int RaiseChildWindows(IntPtr parent)
    {
        var raised = 0;
        EnumChildWindows(parent, (child, _) =>
        {
            SetWindowPos(child, IntPtr.Zero, 0, 0, 0, 0, SwpNoMove | SwpNoSize | SwpNoActivate);   // IntPtr.Zero is HWND_TOP
            raised++;
            return true;
        }, IntPtr.Zero);
        return raised;
    }
}