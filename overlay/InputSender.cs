using System;
using System.Runtime.InteropServices;

namespace Poe2CraftOverlay;

/// Ctrl+C, sent the way modern games expect it.
///
/// keybd_event only sets the virtual key, and Path of Exile 2 ignores those: the item was never
/// copied until the player pressed Ctrl+C by hand. SendInput carries the scan code as well, which is
/// what a DirectInput style game actually reads.
internal static class InputSender
{
    private const int INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint KEYEVENTF_SCANCODE = 0x0008;
    private const ushort VkControl = 0x11;
    private const ushort VkC = 0x43;

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public int type;
        public KEYBDINPUT ki;
        public int padding;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint count, INPUT[] inputs, int size);

    [DllImport("user32.dll")]
    private static extern uint MapVirtualKey(uint code, uint mapType);

    private static INPUT Key(ushort vk, bool up)
    {
        return new INPUT
        {
            type = INPUT_KEYBOARD,
            ki = new KEYBDINPUT
            {
                wVk = 0,
                wScan = (ushort)MapVirtualKey(vk, 0),
                dwFlags = KEYEVENTF_SCANCODE | (up ? KEYEVENTF_KEYUP : 0),
                time = 0,
                dwExtraInfo = IntPtr.Zero,
            },
        };
    }

    /// Presses Ctrl+C once, with scan codes, and reports what the system did.
    public static bool CtrlC()
    {
        var keys = new[] { Key(VkControl, false), Key(VkC, false), Key(VkC, true), Key(VkControl, true) };
        var sent = SendInput((uint)keys.Length, keys, Marshal.SizeOf<INPUT>());
        Log.Write(sent == keys.Length
            ? "capture: Ctrl+C injected with scan codes"
            : $"capture: SendInput sent {sent} of {keys.Length} events, win32 error {Marshal.GetLastWin32Error()}");
        return sent == keys.Length;
    }
}
