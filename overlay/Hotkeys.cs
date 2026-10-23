using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Poe2CraftOverlay;

/// Global hot keys, registered with the shell instead of polled.
///
/// The key watcher reads GetAsyncKeyState, which reports nothing for keys pressed in a window that
/// runs at a higher integrity level - the game does - so the panel never saw the combination. A hot
/// key registered with the system is delivered to this process whatever has focus.
///
/// Ctrl+Q is registered once and stays. Escape is registered only while the panel is on screen:
/// registered permanently it would swallow the game's own Escape, which is why it is bound to the
/// panel's visibility instead.
internal sealed class Hotkeys : IMessageFilter
{
    private const int WM_HOTKEY = 0x0312;
    private const uint MOD_CONTROL = 0x0002;
    private const uint MOD_NOREPEAT = 0x4000;
    private const int VkQ = 0x51;
    private const int VkEscape = 0x1B;
    private const int IdCapture = 1;
    private const int IdClose = 2;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint vk);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private readonly Action _onCapture;
    private readonly Action _onShow;
    private readonly Action _onClose;
    private bool _captureBound;
    private bool _closeBound;

    private Hotkeys(Action onCapture, Action onShow, Action onClose)
    {
        _onCapture = onCapture;
        _onShow = onShow;
        _onClose = onClose;
    }

    /// Registers Ctrl+Q for the calling thread, installs the filter and watches Escape's binding.
    public static void Install(Form panel, Action onCapture, Action onShow, Action onClose)
    {
        var hotkeys = new Hotkeys(onCapture, onShow, onClose);
        hotkeys._captureBound = RegisterHotKey(IntPtr.Zero, IdCapture, MOD_CONTROL | MOD_NOREPEAT, VkQ);
        Log.Write(hotkeys._captureBound
            ? "hotkey: Ctrl+Q registered with the shell"
            : "hotkey: Ctrl+Q is taken by another program; the key watcher stays as a fallback");
        Application.AddMessageFilter(hotkeys);
        // Escape is deliberately not bound any more: the panel is closed with the button in its corner
        // and nothing else, so the game keeps its own Escape untouched.
    }

    private void BindEscape(bool wanted)
    {
        if (wanted == _closeBound)
        {
            return;
        }
        if (wanted)
        {
            _closeBound = RegisterHotKey(IntPtr.Zero, IdClose, MOD_NOREPEAT, VkEscape);
            Log.Write(_closeBound ? "hotkey: Escape closes the panel while it is on screen" : "hotkey: Escape could not be bound");
        }
        else
        {
            UnregisterHotKey(IntPtr.Zero, IdClose);
            _closeBound = false;
        }
    }

    public bool PreFilterMessage(ref Message message)
    {
        if (message.Msg != WM_HOTKEY)
        {
            return false;
        }
        var id = message.WParam.ToInt32();
        if (id == IdCapture && _captureBound)
        {
            Log.Write("hotkey: Ctrl+Q pressed");
            _onCapture();
            _onShow();
            return true;
        }
        if (id == IdClose && _closeBound)
        {
            Log.Write("hotkey: Escape pressed");
            _onClose();
            return true;
        }
        return false;
    }
}
