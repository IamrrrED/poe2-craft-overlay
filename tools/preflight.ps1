# Preflight: is the stash open, and is the EXPECTED tab on screen?
#
# The rule this enforces, learned the hard way: never read a stash page before proving which page it is. Two checks,
# both measured, both able to say "no":
#   1. the panel title has to be readable by OCR (a closed stash has no title at all);
#   2. the page has to match the expected tab TEMPLATE - not a label, because labels are player-renamed and the
#      language can differ, while the pixels of the page cannot lie.
#
#   powershell -File tools\preflight.ps1 -Expect currency
#
# Exit code 0 and "READY" when both hold; otherwise it prints why and exits 1.

param(
    [string]$Expect = "currency",
    [int]$TimeoutSeconds = 0
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$frame = Join-Path $root "docs\preflight.png"

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

function Shot([string]$path) {
    $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

function Ocr([string]$path, [int]$left, [int]$top, [int]$width, [int]$height) {
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "ocr.ps1") `
        -Path $path -Left $left -Top $top -Width $width -Height $height 2>$null
    if (-not $raw) { return "" }
    $json = $raw | Select-Object -Last 1 | ConvertFrom-Json
    return ((@($json.lines) | ForEach-Object { $_.text }) -join " ")
}

$stashTitle = [string]([char]0x0422) + [char]0x0430 + [char]0x0439 + [char]0x043D + [char]0x0438 + [char]0x043A
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

while ($true) {
    Shot $frame
    $title = Ocr $frame 240 70 300 70
    if ($title -notlike "*$stashTitle*") {
        if ((Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 700; continue }
        Write-Host "NOT READY: the stash panel title is not readable (read «$title»), so no page can be identified"
        exit 1
    }

    $match = & python (Join-Path $PSScriptRoot "match_tab.py") --frame $frame --expect $Expect
    $verdict = ($match | Select-Object -Last 1 | ConvertFrom-Json)
    if ($verdict.ok) {
        Write-Host ("READY: stash open, tab «" + $verdict.tab_name + "» confirmed at " + $verdict.score + " (" + $verdict.tab + ")")
        exit 0
    }

    if ((Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 700; continue }
    Write-Host ("NOT READY: stash is open, but the page is «" + $verdict.tab_name + "» (" + $verdict.tab + " at " +
        $verdict.score + "), not «" + $verdict.expect + "» - switch the tab first")
    exit 1
}
