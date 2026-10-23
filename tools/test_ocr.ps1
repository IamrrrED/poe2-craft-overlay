<#
.SYNOPSIS
  Render a fake item tooltip and read it back with tools\grab_item.ps1.

.DESCRIPTION
  The image path of the capture (screen -> OCR -> item parameters) needs a repeatable
  test that does not require the game. This draws a tooltip the way the game shows it -
  dark plate, rarity-coloured name, small serif text - then asks the OCR script to read
  it and reports which lines came back and whether the overlay's parser would accept the
  result.

.PARAMETER Style
  "game" draws the PoE2 tooltip look (dark, small serif). "plain" draws big black text on
  white, which isolates OCR quality from styling.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_ocr.ps1
#>
[CmdletBinding()]
param(
	[string]$Style = "game",
	[string]$OutPng = "tools\cache\ocr_sample.png"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$itemLines = @(
	@("Item Class: Gloves", "#c8c8c8"),
	@("Rarity: Rare", "#c8c8c8"),
	@("Doom Grip", "#ffff77"),
	@("Blacksteel Gauntlets", "#ffff77"),
	@("--------", "#7f7f7f"),
	@("Quality: +20% (augmented)", "#8888ff"),
	@("Evasion Rating: 296 (augmented)", "#8888ff"),
	@("--------", "#7f7f7f"),
	@("+118 to maximum Life", "#8888ff"),
	@("+44% to Fire Resistance", "#8888ff"),
	@("+37% to Cold Resistance", "#8888ff"),
	@("--------", "#7f7f7f"),
	@("Item Level: 82", "#c8c8c8")
)

$width = 520
$height = 40 + ($itemLines.Count * 22)
$bitmap = New-Object System.Drawing.Bitmap($width, $height)
$canvas = [System.Drawing.Graphics]::FromImage($bitmap)
$canvas.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$canvas.Clear([System.Drawing.ColorTranslator]::FromHtml($(if ($Style -eq 'plain') { '#ffffff' } else { '#0c0a07' })))

$font = New-Object System.Drawing.Font("Georgia", $(if ($Style -eq 'plain') { 18 } else { 14 }))
$y = 16
foreach ($line in $itemLines) {
	$colour = if ($Style -eq 'plain') { '#000000' } else { $line[1] }
	$brush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($colour))
	$canvas.DrawString($line[0], $font, $brush, 16, $y)
	$brush.Dispose()
	$y += 22
}
$canvas.Dispose()

$outPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutPng))
$dir = [System.IO.Path]::GetDirectoryName($outPath)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$bitmap.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()
Write-Host "sample image: $outPath ($width x $height, style=$Style)"

# --- read it back -----------------------------------------------------------------

$textPath = "tools\cache\ocr_sample.txt"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'grab_item.ps1') `
	-Image $OutPng -OutText $textPath | ForEach-Object { "  $_" }

if (Test-Path $textPath) {
	$read = Get-Content $textPath -Raw
	Write-Host "--- recognised text ---"
	($read -split "`r?`n") | Where-Object { $_.Trim() } | ForEach-Object { "  | $_" }

	$expect = @("Doom Grip", "Blacksteel", "maximum Life", "Fire Resistance", "Item Level")
	$missing = @()
	foreach ($needle in $expect) {
		if ($read -notmatch [regex]::Escape($needle)) { $missing += $needle }
	}
	if ($missing.Count -eq 0) {
		Write-Host "RESULT: ok (all key phrases recognised)"
		exit 0
	}
	Write-Host ("RESULT: missing " + ($missing -join ', '))
	exit 1
}
Write-Host "RESULT: no text produced"
exit 1
