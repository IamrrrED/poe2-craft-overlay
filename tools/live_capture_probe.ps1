# Ask the running game for the item under the cursor, exactly the way the panel does it.
#
# The panel finds the game window by its class (POEWindowClass) or its exact title, brings it forward and sends
# Ctrl+C. Until now that path was only ever exercised against a synthetic clipboard: the real question - does
# the running game accept our keystroke - needs the game itself, and it is running.
#
# If nothing is under the cursor the game copies nothing, the clipboard sequence number does not move, and that
# is the honest answer rather than a failure. The clipboard is restored on the way out.

Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Win {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr extra);
    public delegate bool EnumWindowsProc(IntPtr window, IntPtr extra);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr window, StringBuilder name, int size);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr window, StringBuilder text, int size);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, IntPtr extra);
}
"@

$found = [IntPtr]::Zero
$foundInfo = ""
$callback = [Win+EnumWindowsProc]{
    param($window, $extra)
    if (-not [Win]::IsWindowVisible($window)) { return $true }
    $class = New-Object System.Text.StringBuilder 256
    [Win]::GetClassName($window, $class, 256) | Out-Null
    $title = New-Object System.Text.StringBuilder 256
    [Win]::GetWindowText($window, $title, 256) | Out-Null
    if ($class.ToString() -eq 'POEWindowClass' -or $title.ToString() -eq 'Path of Exile 2') {
        $script:found = $window
        $script:foundInfo = "class='$($class.ToString())' title='$($title.ToString())'"
        return $false
    }
    return $true
}
[Win]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null

if ($found -eq [IntPtr]::Zero) {
    "focus: NO GAME WINDOW FOUND (the panel would log the same and leave the clipboard alone)"
    exit 2
}
"focus: found the game window $foundInfo"

$before = [Win]::GetClipboardSequenceNumber()
$saved = $null
try { $saved = [System.Windows.Forms.Clipboard]::GetText() } catch { }

[Win]::SetForegroundWindow($found) | Out-Null
Start-Sleep -Milliseconds 400
$foreground = [Win]::GetForegroundWindow()
"focus: foreground is now " + ($(if ($foreground -eq $found) { "the game" } else { "window $foreground (the game did not take focus)" }))

# Ctrl+C, exactly what the panel sends: control down, C, C up, control up.
[Win]::keybd_event(0x11, 0, 0, [IntPtr]::Zero)
[Win]::keybd_event(0x43, 0, 0, [IntPtr]::Zero)
[Win]::keybd_event(0x43, 0, 2, [IntPtr]::Zero)
[Win]::keybd_event(0x11, 0, 2, [IntPtr]::Zero)
Start-Sleep -Milliseconds 600

$after = [Win]::GetClipboardSequenceNumber()
"clipboard: sequence $before -> $after"

if ($after -ne $before) {
    $text = ""
    try { $text = [System.Windows.Forms.Clipboard]::GetText() } catch { }
    "capture: the game accepted Ctrl+C and copied " + $text.Length + " characters"
    $lines = ($text -split "`r?`n") | Select-Object -First 6
    "capture: first lines:"
    $lines | ForEach-Object { "    " + $_ }
    Set-Content -LiteralPath (Join-Path $PSScriptRoot 'real_capture.txt') -Value $text -Encoding UTF8
    "capture: saved to tools\real_capture.txt"
} else {
    "capture: the game did not change the clipboard - nothing is under the cursor, which is the honest"
    "         answer: the keystroke reached a running game and the game chose not to copy."
}

if ($null -ne $saved) {
    try { [System.Windows.Forms.Clipboard]::SetText($saved) } catch { }
    "clipboard: previous text restored"
}

if (-not $args.Contains('-Control')) {
    exit 0
}

# Control experiment: the same keystroke injection, aimed at an ordinary edit field we own. If the clipboard
# moves here, then "the game did not copy" above means the game had nothing to copy - not that our keystroke
# injection is broken. Without this, a broken SendInput would look exactly like an empty cursor.
""
"control: sending the same Ctrl+C to a plain text field"
Add-Type -AssemblyName System.Drawing | Out-Null
$form = New-Object System.Windows.Forms.Form
$form.Text = 'capture probe'
$form.Width = 420
$form.Height = 120
$box = New-Object System.Windows.Forms.TextBox
$box.Multiline = $true
$box.Dock = 'Fill'
$box.Text = 'control text 12345'
$form.Controls.Add($box)
$form.Show()
# A WinForms window in a script has no message loop of its own: without pumping messages it never paints,
# never becomes the foreground window and never receives a keystroke - which would make the control fail for
# reasons that have nothing to do with the injection.
for ($i = 0; $i -lt 20; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 }
$form.Activate()
$box.Focus()
$box.SelectAll()
for ($i = 0; $i -lt 20; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 }
"control: form foreground = " + ([Win]::GetForegroundWindow() -eq $form.Handle) + ", textbox focused = " + $box.Focused

$controlBefore = [Win]::GetClipboardSequenceNumber()
[Win]::SetForegroundWindow($form.Handle) | Out-Null
Start-Sleep -Milliseconds 200
[Win]::keybd_event(0x11, 0, 0, [IntPtr]::Zero)
[Win]::keybd_event(0x43, 0, 0, [IntPtr]::Zero)
[Win]::keybd_event(0x43, 0, 2, [IntPtr]::Zero)
[Win]::keybd_event(0x11, 0, 2, [IntPtr]::Zero)
Start-Sleep -Milliseconds 400
$controlAfter = [Win]::GetClipboardSequenceNumber()
$controlText = ""
try { $controlText = [System.Windows.Forms.Clipboard]::GetText() } catch { }
$form.Close()

"control: clipboard sequence $controlBefore -> $controlAfter, text '$controlText'"
if ($controlAfter -ne $controlBefore -and $controlText -eq 'control text 12345') {
    "control: PASS - the keystroke injection copies what it is aimed at, so the game simply had nothing"
} else {
    "control: FAIL - our Ctrl+C does not copy even from a field that should accept it, so the game result"
    "         above proves nothing about the game"
}
if ($null -ne $saved) {
    try { [System.Windows.Forms.Clipboard]::SetText($saved) } catch { }
    "clipboard: previous text restored again"
}
