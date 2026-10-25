# Полный обход тайника: кнопка списка -> OCR строк -> клик по строке -> кадр. Повтор для каждой вкладки.
#
# Проверено практикой: кнопка справа от полосы открывает список вкладок, а клик по строке списка переключает
# страницу (после клика RITUAL полоса показала ITUAL — вкладка сдвинулась в видимую часть).
#
#   powershell -File tools\stash_scan2.ps1 -MaxTabs 12

param(
    [int]$MaxTabs = 12,
    [string]$Exe = "overlay\bin\Release\net8.0-windows\Poe2CraftOverlay.exe"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root "docs\stash-scan"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
Get-ChildItem $outDir -Filter tab-*.png | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem $outDir -Filter list-*.json | Remove-Item -Force -ErrorAction SilentlyContinue

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class UIList {
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

# The list is a toggle, so "open it" means "make sure it is open": click, read, and click again if the known tab
# names are absent. Without this, a click that closed an already-open list produced a frame of the world and the scan
# silently captured the wrong thing.
function EnsureListOpen([string]$scratch) {
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        [UIList]::Click($listButton[0], $listButton[1])
        Start-Sleep -Milliseconds 420
        Shot $scratch
        $ocr = Ocr $scratch $listRegion[0] $listRegion[1] $listRegion[2] $listRegion[3]
        $text = (@($ocr.lines) | ForEach-Object { $_.text }) -join " "
        if ($text -match '(?i)RITUAL|MAPS|FRAGMENTS|RUNES|GEMS|DELIRIUM|EXPEDITION') {
            return $ocr
        }
    }
    return $null
}
$listButton = @(862, 146)      # measured: the button that opens the tab list
$listRegion = @(880, 130, 260, 780)
$expectedTitle = [string]([char]0x0422) + [char]0x0430 + [char]0x0439 + [char]0x043D + [char]0x0438 + [char]0x043A

$game = Get-Process | Where-Object { $_.ProcessName -match 'PathOfExile' } | Select-Object -First 1
if (-not $game) { throw "game is not running" }
[UIList]::SetForegroundWindow($game.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 400

$probe = Join-Path $outDir "open.png"
Shot $probe
$title = Ocr $probe 240 70 300 70
$titleText = (@($title.lines) | ForEach-Object { $_.text }) -join " "
if ($titleText -notlike "*$expectedTitle*") {
    $python = $env:POE2CRAFT_PYTHON
    if (-not $python) { $python = (Get-Command python -ErrorAction SilentlyContinue).Source }
    $env:POE2CRAFT_STASH = "1"
    if ($python) { $env:POE2CRAFT_PYTHON = $python }
    $exePath = Join-Path $root $Exe
    Remove-Item (Join-Path (Split-Path $exePath) "stash-report.txt") -ErrorAction SilentlyContinue
    Start-Process -FilePath $exePath -ArgumentList "--open-stash" -WindowStyle Hidden | Out-Null
    $report = Join-Path (Split-Path $exePath) "stash-report.txt"
    for ($i = 0; $i -lt 120 -and -not (Test-Path $report); $i++) { Start-Sleep -Milliseconds 300 }
    Remove-Item Env:POE2CRAFT_STASH -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    Shot $probe
    $title = Ocr $probe 240 70 300 70
    $titleText = (@($title.lines) | ForEach-Object { $_.text }) -join " "
}
if ($titleText -notlike "*$expectedTitle*") { throw "stash panel is not on screen: $titleText" }
Write-Host "panel: open"

# Один раз читаем список, чтобы узнать имена и порядок строк.
[UIList]::Click($listButton[0], $listButton[1])
Start-Sleep -Milliseconds 500
$listFrame = Join-Path $outDir "list-raw.png"
Shot $listFrame
$listOcr = Ocr $listFrame $listRegion[0] $listRegion[1] $listRegion[2] $listRegion[3]
$rows = @($listOcr.lines | Where-Object { $_.w -gt 5 -and $_.h -gt 10 -and $_.y -gt 5 })
Write-Host ("rows in the list: " + $rows.Count)
$rows | ForEach-Object { Write-Host ("  [" + $_.text + "] y=" + ($listRegion[1] + $_.y)) }
($rows | ForEach-Object { [pscustomobject]@{ text = $_.text; x = $_.x; y = $_.y; w = $_.w; h = $_.h } } |
    ConvertTo-Json -Depth 3) | Set-Content (Join-Path $outDir "list-raw.json") -Encoding UTF8

# Список открыт; кликаем по строкам по очереди. После клика список обычно закрывается, поэтому перед каждой
# строкой он открывается заново.
$index = 0
$visited = @{}
foreach ($row in $rows) {
    if ($index -ge $MaxTabs) { break }
    $name = [regex]::Replace($row.text, '[^\w]', '')
    if ($name.Length -eq 0) { continue }
    if ($visited.ContainsKey($name)) { continue }
    $visited[$name] = $true

    [UIList]::Click($listButton[0], $listButton[1])
    Start-Sleep -Milliseconds 420
    $clickX = $listRegion[0] + [int]($row.x + $row.w / 2)
    $clickY = $listRegion[1] + [int]($row.y + $row.h / 2)
    [UIList]::Click($clickX, $clickY)
    Start-Sleep -Milliseconds 560
    $index++
    $shot = Join-Path $outDir ("tab-{0:d2}-{1}.png" -f $index, $name)
    Shot $shot
    Write-Host ("tab " + $name + " at " + $clickX + "," + $clickY + " -> " + (Split-Path $shot -Leaf))
}

Write-Host ("tabs captured: " + (@(Get-ChildItem $outDir -Filter tab-*.png).Count))
