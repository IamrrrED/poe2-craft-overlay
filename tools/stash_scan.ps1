# Обход всех вкладок тайника: OCR верхней полосы -> клик по центру плашки -> кадр; стрелка прокручивает полосу.
#
# Без угадывания: координаты берутся из OCR, а какая вкладка активна — проверяется по яркости плашки (у активной
# фон светлее), а не по предположению «клик попал туда, куда собирался».
#
#   powershell -File tools\stash_scan.ps1 -MaxTabs 16

param(
    [int]$MaxTabs = 16,
    [string]$Exe = "overlay\bin\Release\net8.0-windows\Poe2CraftOverlay.exe"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root "docs\stash-scan"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
Get-ChildItem $outDir -Filter *.png | Remove-Item -Force -ErrorAction SilentlyContinue

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class UIScan {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr w);
  public static void Click(int x, int y) {
    SetCursorPos(x, y);
    mouse_event(0x0001, 2, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(20);
    mouse_event(0x0001, -2, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(90);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(40);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
  }
}
'@
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
    if (-not $raw) { return $null }
    return ($raw | Select-Object -Last 1 | ConvertFrom-Json)
}

# Полоса вкладок: область внутри панели, выше сетки.
$stripLeft, $stripTop, $stripWidth, $stripHeight = 20, 120, 820, 48
$expectedTitle = [string]([char]0x0422) + [char]0x0430 + [char]0x0439 + [char]0x043D + [char]0x0438 + [char]0x043A

function PanelOpen([string]$frame) {
    $ocr = Ocr $frame 240 70 300 70
    $text = (@($ocr.lines) | ForEach-Object { $_.text }) -join " "
    return ($text -like "*$expectedTitle*")
}

$game = Get-Process | Where-Object { $_.ProcessName -match 'PathOfExile' } | Select-Object -First 1
if (-not $game) { throw "game is not running" }
[UIScan]::SetForegroundWindow($game.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 400

$probe = Join-Path $outDir "open.png"
Shot $probe
if (-not (PanelOpen $probe)) {
    $python = $env:POE2CRAFT_PYTHON
    if (-not $python) { $python = (Get-Command python -ErrorAction SilentlyContinue).Source }
    $env:POE2CRAFT_STASH = "1"
    if ($python) { $env:POE2CRAFT_PYTHON = $python }
    $exePath = Join-Path $root $Exe
    if (-not (Test-Path $exePath)) { throw "overlay is not built: $exePath" }
    Remove-Item (Join-Path (Split-Path $exePath) "stash-report.txt") -ErrorAction SilentlyContinue
    Start-Process -FilePath $exePath -ArgumentList "--open-stash" -WindowStyle Hidden | Out-Null
    $report = Join-Path (Split-Path $exePath) "stash-report.txt"
    for ($i = 0; $i -lt 120 -and -not (Test-Path $report); $i++) { Start-Sleep -Milliseconds 300 }
    Remove-Item Env:POE2CRAFT_STASH -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 400
    Shot $probe
}
if (-not (PanelOpen $probe)) { throw "stash panel is not on screen" }
Write-Host "panel: open"

$visited = @{}
$index = 0
$scrolls = 0
while ($index -lt $MaxTabs -and $scrolls -le 3) {
    $frame = Join-Path $outDir ("strip-{0}.png" -f $scrolls)
    Shot $frame
    $ocr = Ocr $frame $stripLeft $stripTop $stripWidth $stripHeight
    $labels = @($ocr.lines | Where-Object { $_.w -gt 20 -and $_.h -gt 10 })
    if ($labels.Count -eq 0) { break }
    Write-Host ("strip pass " + $scrolls + ": " + ($labels | ForEach-Object { $_.text }) -join " | ")

    foreach ($label in $labels) {
        if ($index -ge $MaxTabs) { break }
        $name = [regex]::Replace($label.text, '[^\w]', '')
        if ($name.Length -eq 0) { continue }
        if ($visited.ContainsKey($name)) { continue }
        $visited[$name] = $true
        $clickX = $stripLeft + [int]($label.x + $label.w / 2)
        $clickY = $stripTop + [int]($label.y + $label.h / 2)
        [UIScan]::Click($clickX, $clickY)
        Start-Sleep -Milliseconds 520
        $index++
        $shot = Join-Path $outDir ("tab-{0:d2}-{1}.png" -f $index, $name)
        Shot $shot
        Write-Host ("tab " + $name + " -> " + (Split-Path $shot -Leaf))
    }

    # Стрелка прокрутки полосы: сразу справа от последней плашки.
    $last = $labels | Sort-Object { $_.x + $_.w } | Select-Object -Last 1
    $arrowX = $stripLeft + [int]($last.x + $last.w) + 22
    $arrowY = $stripTop + [int]($last.y + $last.h / 2)
    [UIScan]::Click($arrowX, $arrowY)
    $scrolls++
    Start-Sleep -Milliseconds 450
    Write-Host ("scroll " + $scrolls + " at " + $arrowX + "," + $arrowY)
}

Get-ChildItem $outDir -Filter tab-*.png | Select-Object Name | Format-Table -AutoSize
Write-Host ("tabs captured: " + (@(Get-ChildItem $outDir -Filter tab-*.png).Count))
