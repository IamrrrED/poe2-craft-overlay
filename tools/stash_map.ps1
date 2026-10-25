# Карта тайника: открыть тайник, прочитать список вкладок OCR-ом, пройти по центру каждой строки,
# сохранить кадр каждой вкладки и собрать из этого данные для карты.
#
# Почему так: клик по «примерно тому месту» уже дважды закрывал тайник. Координаты берутся из OCR: центр
# ограничивающей рамки строки, которую распознал Windows. Никакой арифметики «на глаз».
#
#   powershell -File tools\stash_map.ps1 [-MaxTabs 8]

param(
    [int]$MaxTabs = 8,
    [string]$Exe = "overlay\bin\Release\net8.0-windows\Poe2CraftOverlay.exe"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root "docs\stash-map-frames"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
Get-ChildItem $outDir -Filter *.png | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem $outDir -Filter *.json | Remove-Item -Force -ErrorAction SilentlyContinue

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class UI {
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

$game = Get-Process | Where-Object { $_.ProcessName -match 'PathOfExile' } | Select-Object -First 1
if (-not $game) { throw "игра не запущена" }
[UI]::SetForegroundWindow($game.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 400

# The stash toggles: clicking it when it is already open closes it. So the state is read from the frame first, and a
# click happens only when the panel is definitely absent.
$expectedTitle = [string]([char]0x0422) + [char]0x0430 + [char]0x0439 + [char]0x043D + [char]0x0438 + [char]0x043A
function TitleVisible([string]$frame) {
    $ocr = Ocr $frame 240 70 300 70
    $text = (@($ocr.lines) | ForEach-Object { $_.text }) -join " "
    if ($text.Length -eq 0) { return $false }
    return ($text -like "*$expectedTitle*")
}

$probe = Join-Path $outDir "00-open.png"
Shot $probe
$panelOpen = TitleVisible $probe
Write-Host ("panel open before: " + $panelOpen)

if (-not $panelOpen) {
    $python = $env:POE2CRAFT_PYTHON
    if (-not $python) { $python = (Get-Command python -ErrorAction SilentlyContinue).Source }
    $env:POE2CRAFT_STASH = "1"
    if ($python) { $env:POE2CRAFT_PYTHON = $python }
    $exePath = Join-Path $root $Exe
    if (-not (Test-Path $exePath)) { throw "overlay is not built: $exePath" }
    Remove-Item (Join-Path (Split-Path $exePath) "stash-report.txt") -ErrorAction SilentlyContinue
    Start-Process -FilePath $exePath -ArgumentList "--open-stash" -WindowStyle Hidden | Out-Null
    $stashReport = Join-Path (Split-Path $exePath) "stash-report.txt"
    for ($i = 0; $i -lt 120 -and -not (Test-Path $stashReport); $i++) { Start-Sleep -Milliseconds 300 }
    Remove-Item Env:POE2CRAFT_STASH -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 400
    Shot $probe
    $panelOpen = TitleVisible $probe
    Write-Host ("panel open after the click: " + $panelOpen)
}
if (-not $panelOpen) { throw "the stash panel is not on screen, so there is nothing to map" }
# Снимок и OCR области списка вкладок. Область шире, чем сам список: пусть OCR сам найдёт строки.
$frame = Join-Path $outDir "00-open.png"
Shot $frame
$listOcr = Ocr $frame 880 120 260 800
$lines = @($listOcr.lines | Where-Object { $_.h -gt 12 -and $_.w -gt 6 })
Write-Host ("строк в списке вкладок: " + $lines.Count)
foreach ($line in $lines) { Write-Host ("  " + $line.text + " @ " + ($line.x + 880) + "," + ($line.y + 120)) }

$used = 0
$index = 0
foreach ($line in $lines) {
    if ($used -ge $MaxTabs) { break }
    # The label keeps Unicode letters and digits only: a regex with Cyrillic ranges arrives mangled through the
    # system codepage, while .NET's \w already covers Cyrillic.
    $label = [regex]::Replace($line.text, '[^\w]', '')
    if ($label.Length -eq 0) { continue }
    # Клик строго по центру строки, которую нашёл OCR.
    $clickX = 880 + [int]($line.x + $line.w / 2)
    $clickY = 120 + [int]($line.y + $line.h / 2)
    [UI]::Click($clickX, $clickY)
    Start-Sleep -Milliseconds 500
    $index++
    $shotPath = Join-Path $outDir ("{0:d2}-{1}.png" -f $index, ([regex]::Replace($label, '[^\w]', '_')))
    Shot $shotPath
    $used++
    Write-Host ("вкладка " + $label + ": клик " + $clickX + "," + $clickY + " -> " + (Split-Path $shotPath -Leaf))
}

Get-ChildItem $outDir -Filter *.png | Select-Object Name, Length | Format-Table -AutoSize
