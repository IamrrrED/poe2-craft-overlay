<#
.SYNOPSIS
  Builds glyph atlases (Cyrillic included) for the overlay's own text renderer.

.DESCRIPTION
  The SimpleGraphic host draws text with PoB's bitmap fonts and none of the three
  accepted font names ("VAR", "VAR BOLD", "FIXED") contains Cyrillic glyphs, so the
  overlay rasterises its own atlas and draws each character with DrawImage.

  Two modes:
    (no switch)     build every candidate variant and rewrite the manifest
    -Id <variant>   build a single variant

  Atlases keep a uniform grid of cells but store a PER-GLYPH advance, so proportional
  faces (Segoe UI, Arial) render correctly instead of being forced onto a monospaced
  grid - that was the reason the first attempts looked wrong.

  Outputs (relative to the project root):
    src/Data/fonts/<id>.png     glyph grid, white on transparent
    src/Data/fonts/<id>.lua     cell size, per-glyph advances, codepoint order
    src/Data/fonts.lua          manifest: variant ids, labels, default

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\tools\build_fonts.ps1
#>
[CmdletBinding()]
param(
	[string]$Id
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $PSScriptRoot
$fontsDir = Join-Path $projectRoot 'src\Data\fonts'
$manifestPath = Join-Path $projectRoot 'src\Data\fonts.lua'

# Fontin - the typeface Path of Exile and the Sidekick companion app both use. It is
# not installed as a system font, so it is loaded straight from a file: a local copy in
# assets/fonts (git-ignored, put there by setup.ps1 or by hand), otherwise out of the
# Sidekick installation.
$fontinDir = Join-Path $projectRoot 'assets\fonts'
$fontinCandidates = @(
	@{ regular = (Join-Path $fontinDir 'fontin-regular-webfont.ttf'); bold = (Join-Path $fontinDir 'fontin-bold-webfont.ttf') },
	@{
		regular = "$env:LOCALAPPDATA\Sidekick\current\Assets\Fonts\fontin-regular-webfont.ttf"
		bold = "$env:LOCALAPPDATA\Sidekick\current\Assets\Fonts\fontin-bold-webfont.ttf"
	}
)
$script:fontin = $null
foreach ($source in $fontinCandidates) {
	if ((Test-Path $source.regular) -and (Test-Path $source.bold)) { $script:fontin = $source; break }
}
if ($script:fontin) {
	Write-Host "Fontin (as in Sidekick): $($script:fontin.regular)"
} else {
	Write-Warning "Fontin not found in assets\fonts or in Sidekick: Fontin variants skipped"
}

# Candidate faces: all ship with Windows and cover Cyrillic. Sizes go down to 11 px so
# the panel can be as compact as needed, and `tracking` squeezes the gap between
# letters (1.0 = the font's natural advance) - that is what makes a line read as one
# solid block instead of a sparse row of glyphs.
$tracking = 0.94
$candidates = @(
	# --- Monospaced -------------------------------------------------------------
	@{ id = 'consolas_bold_16'; family = 'Consolas'; size = 16; style = 'Bold'; label = 'Consolas Bold 16 (mono)'; kind = 'mono' },
	@{ id = 'consolas_bold_14'; family = 'Consolas'; size = 14; style = 'Bold'; label = 'Consolas Bold 14 (mono)'; kind = 'mono' },
	@{ id = 'consolas_bold_13'; family = 'Consolas'; size = 13; style = 'Bold'; label = 'Consolas Bold 13 (mono)'; kind = 'mono' },
	@{ id = 'cascadia_mono_14'; family = 'Cascadia Mono'; size = 14; style = 'Regular'; label = 'Cascadia Mono 14 (mono)'; kind = 'mono' },
	@{ id = 'cascadia_mono_13'; family = 'Cascadia Mono'; size = 13; style = 'Regular'; label = 'Cascadia Mono 13 (mono)'; kind = 'mono' },
	@{ id = 'cascadia_code_13'; family = 'Cascadia Code'; size = 13; style = 'Regular'; label = 'Cascadia Code 13 (mono)'; kind = 'mono' },
	@{ id = 'lucida_13'; family = 'Lucida Console'; size = 13; style = 'Regular'; label = 'Lucida Console 13 (mono)'; kind = 'mono' },

	# --- Segoe UI family --------------------------------------------------------
	@{ id = 'segoe_semibold_16'; family = 'Segoe UI Semibold'; size = 16; style = 'Regular'; label = 'Segoe UI Semibold 16 (proportional)'; kind = 'prop' },
	@{ id = 'segoe_semibold_14'; family = 'Segoe UI Semibold'; size = 14; style = 'Regular'; label = 'Segoe UI Semibold 14 (proportional)'; kind = 'prop' },
	@{ id = 'segoe_semibold_13'; family = 'Segoe UI Semibold'; size = 13; style = 'Regular'; label = 'Segoe UI Semibold 13 (proportional)'; kind = 'prop' },
	@{ id = 'segoe_semibold_12'; family = 'Segoe UI Semibold'; size = 12; style = 'Regular'; label = 'Segoe UI Semibold 12 (proportional)'; kind = 'prop' },
	@{ id = 'segoe_semibold_11'; family = 'Segoe UI Semibold'; size = 11; style = 'Regular'; label = 'Segoe UI Semibold 11 (proportional)'; kind = 'prop' },
	@{ id = 'segoe_14'; family = 'Segoe UI'; size = 14; style = 'Regular'; label = 'Segoe UI 14 (proportional)'; kind = 'prop' },
	@{ id = 'segoe_13'; family = 'Segoe UI'; size = 13; style = 'Regular'; label = 'Segoe UI 13 (proportional)'; kind = 'prop' },
	@{ id = 'segoe_12'; family = 'Segoe UI'; size = 12; style = 'Regular'; label = 'Segoe UI 12 (proportional)'; kind = 'prop' },
	@{ id = 'segoe_bold_14'; family = 'Segoe UI'; size = 14; style = 'Bold'; label = 'Segoe UI Bold 14 (proportional)'; kind = 'prop' },
	@{ id = 'segoe_bold_12'; family = 'Segoe UI'; size = 12; style = 'Bold'; label = 'Segoe UI Bold 12 (proportional)'; kind = 'prop' },
	@{ id = 'segoe_var_14'; family = 'Segoe UI Variable Text'; size = 14; style = 'Regular'; label = 'Segoe UI Variable 14 (proportional)'; kind = 'prop' },
	@{ id = 'segoe_var_12'; family = 'Segoe UI Variable Text'; size = 12; style = 'Regular'; label = 'Segoe UI Variable 12 (proportional)'; kind = 'prop' },

	# --- Faces picked for legibility at small sizes -----------------------------
	@{ id = 'verdana_13'; family = 'Verdana'; size = 13; style = 'Regular'; label = 'Verdana 13 (proportional)'; kind = 'prop'; tracking = 0.90 },
	@{ id = 'verdana_12'; family = 'Verdana'; size = 12; style = 'Regular'; label = 'Verdana 12 (proportional)'; kind = 'prop'; tracking = 0.90 },
	@{ id = 'verdana_11'; family = 'Verdana'; size = 11; style = 'Regular'; label = 'Verdana 11 (proportional)'; kind = 'prop'; tracking = 0.90 },
	@{ id = 'verdana_bold_12'; family = 'Verdana'; size = 12; style = 'Bold'; label = 'Verdana Bold 12 (proportional)'; kind = 'prop'; tracking = 0.90 },
	@{ id = 'tahoma_13'; family = 'Tahoma'; size = 13; style = 'Regular'; label = 'Tahoma 13 (proportional)'; kind = 'prop'; tracking = 0.90 },
	@{ id = 'tahoma_12'; family = 'Tahoma'; size = 12; style = 'Regular'; label = 'Tahoma 12 (proportional)'; kind = 'prop'; tracking = 0.90 },
	@{ id = 'calibri_14'; family = 'Calibri'; size = 14; style = 'Regular'; label = 'Calibri 14 (proportional)'; kind = 'prop' },
	@{ id = 'calibri_13'; family = 'Calibri'; size = 13; style = 'Regular'; label = 'Calibri 13 (proportional)'; kind = 'prop' },
	@{ id = 'trebuchet_13'; family = 'Trebuchet MS'; size = 13; style = 'Regular'; label = 'Trebuchet MS 13 (proportional)'; kind = 'prop' },
	@{ id = 'corbel_14'; family = 'Corbel'; size = 14; style = 'Regular'; label = 'Corbel 14 (proportional)'; kind = 'prop' },
	@{ id = 'candara_13'; family = 'Candara'; size = 13; style = 'Regular'; label = 'Candara 13 (proportional)'; kind = 'prop' },
	@{ id = 'mssans_13'; family = 'Microsoft Sans Serif'; size = 13; style = 'Regular'; label = 'Microsoft Sans Serif 13 (proportional)'; kind = 'prop' },
	@{ id = 'lucida_sans_13'; family = 'Lucida Sans Unicode'; size = 13; style = 'Regular'; label = 'Lucida Sans Unicode 13 (proportional)'; kind = 'prop' },
	@{ id = 'franklin_13'; family = 'Franklin Gothic Medium'; size = 13; style = 'Regular'; label = 'Franklin Gothic Medium 13 (proportional)'; kind = 'prop' },

	# --- Fontin: the Path of Exile / Sidekick typeface, loaded from its own file ---
	@{ id = 'fontin_regular_16'; family = 'Fontin'; size = 16; style = 'Regular'; label = 'Fontin Regular 16 (as in Sidekick)'; kind = 'prop'; fontin = 'regular' },
	@{ id = 'fontin_regular_15'; family = 'Fontin'; size = 15; style = 'Regular'; label = 'Fontin Regular 15 (as in Sidekick)'; kind = 'prop'; fontin = 'regular' },
	@{ id = 'fontin_regular_14'; family = 'Fontin'; size = 14; style = 'Regular'; label = 'Fontin Regular 14 (as in Sidekick)'; kind = 'prop'; fontin = 'regular' },
	@{ id = 'fontin_regular_13'; family = 'Fontin'; size = 13; style = 'Regular'; label = 'Fontin Regular 13 (as in Sidekick)'; kind = 'prop'; fontin = 'regular' },
	@{ id = 'fontin_bold_16'; family = 'Fontin'; size = 16; style = 'Bold'; label = 'Fontin Bold 16 (as in Sidekick)'; kind = 'prop'; fontin = 'bold' },
	@{ id = 'fontin_bold_15'; family = 'Fontin'; size = 15; style = 'Bold'; label = 'Fontin Bold 15 (as in Sidekick)'; kind = 'prop'; fontin = 'bold' },
	@{ id = 'fontin_bold_14'; family = 'Fontin'; size = 14; style = 'Bold'; label = 'Fontin Bold 14 (as in Sidekick)'; kind = 'prop'; fontin = 'bold' }
)

# Default = Fontin, the typeface Path of Exile and Sidekick use; 14 px matches the
$defaultId = 'fontin_regular_14'

# Printable ASCII, Cyrillic upper/lower, Yo, and the symbols the panel uses.
function Get-Codes {
	$codes = New-Object System.Collections.Generic.List[int]
	for ($c = 32; $c -le 126; $c++) { $codes.Add($c) }
	$codes.AddRange([int[]](1025, 1105))
	for ($c = 1040; $c -le 1103; $c++) { $codes.Add($c) }
	$codes.AddRange([int[]](8470, 8212, 183, 8594, 176, 215, 8804, 8805, 10003, 9888))
	return $codes
}

$installed = (New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name }

function Build-Atlas {
	param([hashtable]$Variant, $Codes)

	$family = $Variant.family
	# The metrics store the plain family name, not a .NET object's ToString().
	$familyName = $Variant.family
	$private = $null
	if ($Variant.ContainsKey('fontin')) {
		# Fontin is not installed as a system font, so it is loaded from its file.
		if (-not $script:fontin) {
			Write-Warning "Fontin unavailable, skipping variant $($Variant.id)"
			return $false
		}
		$path = if ($Variant.fontin -eq 'bold') { $script:fontin.bold } else { $script:fontin.regular }
		$private = New-Object System.Drawing.Text.PrivateFontCollection
		$private.AddFontFile($path)
		$family = $private.Families[0]
		$familyName = $family.Name
	} elseif ($installed -notcontains $family) {
		Write-Warning "font '$family' not found, skipping variant $($Variant.id)"
		return $false
	}

	# A file already carries its weight, so the style is only applied to system fonts.
	$style = if ($Variant.ContainsKey('fontin')) {
		[System.Drawing.FontStyle]::Regular
	} elseif ($Variant.style -eq 'Bold') {
		[System.Drawing.FontStyle]::Bold
	} else {
		[System.Drawing.FontStyle]::Regular
	}
	$font = New-Object System.Drawing.Font($family, $Variant.size, $style, [System.Drawing.GraphicsUnit]::Pixel)

	$measureBitmap = New-Object System.Drawing.Bitmap(8, 8)
	$measureGraphics = [System.Drawing.Graphics]::FromImage($measureBitmap)
	$measureGraphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

	# Per-glyph advance: proportional faces need their own width per character.
	$advances = @()
	foreach ($code in $Codes) {
		$text = [char]::ConvertFromUtf32($code)
		$width = [int][Math]::Ceiling($measureGraphics.MeasureString($text, $font).Width)
		if ($width -lt 1) { $width = 1 }
		$advances += $width
	}
	$cellWidth = ($advances | Measure-Object -Maximum).Maximum + 1
	$variantTracking = if ($Variant.ContainsKey('tracking')) { [double]$Variant.tracking } else { [double]$tracking }
	$lineHeight = [int][Math]::Ceiling($font.GetHeight($measureGraphics))
	$measureGraphics.Dispose(); $measureBitmap.Dispose()

	$columns = 32
	$rows = [int][Math]::Ceiling($Codes.Count / $columns)
	$atlasWidth = $columns * $cellWidth
	$atlasHeight = $rows * $lineHeight

	$bitmap = New-Object System.Drawing.Bitmap($atlasWidth, $atlasHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
	$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
	$graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
	$graphics.Clear([System.Drawing.Color]::Transparent)
	$brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

	for ($i = 0; $i -lt $Codes.Count; $i++) {
		$col = $i % $columns
		$row = [int][Math]::Floor($i / $columns)
		$x = $col * $cellWidth
		$y = $row * $lineHeight
		$graphics.DrawString([char]::ConvertFromUtf32($Codes[$i]), $font, $brush, [single]$x, [single]$y)
	}
	$graphics.Dispose()
	$brush.Dispose()

	# Which glyphs came out blank? A blank cell means the face has no glyph for that
	# codepoint (the space character is blank by design), so this is what tells us
	# whether a typeface can actually draw the panel's Cyrillic text.
	$missing = @()
	for ($i = 0; $i -lt $Codes.Count; $i++) {
		if ($Codes[$i] -eq 32) { continue }
		$col = $i % $columns
		$row = [int][Math]::Floor($i / $columns)
		$blank = $true
		for ($px = $col * $cellWidth; $px -lt ($col + 1) * $cellWidth -and $blank; $px++) {
			for ($py = $row * $lineHeight; $py -lt ($row + 1) * $lineHeight; $py++) {
				if ($bitmap.GetPixel($px, $py).A -gt 40) { $blank = $false; break }
			}
		}
		if ($blank) { $missing += $Codes[$i] }
	}

	New-Item -ItemType Directory -Force -Path $fontsDir | Out-Null
	$pngPath = Join-Path $fontsDir ($Variant.id + '.png')
	$bitmap.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
	$bitmap.Dispose()
	$font.Dispose()

	$codeList = ($Codes | ForEach-Object { $_ }) -join ', '
	$advanceList = ($advances | ForEach-Object { $_ }) -join ', '
	$generated = (Get-Date).ToString('yyyy-MM-dd HH:mm')
	$isDefault = if ($Variant.id -eq $defaultId) { 'true' } else { 'false' }
	$lua = @"
-- PoE2 Craft Overlay : Data/fonts/$($Variant.id).lua
-- GENERATED FILE - do not edit by hand (tools/build_fonts.ps1).
--
-- Glyph atlas metrics. The host's bitmap fonts have no Cyrillic glyphs, so the panel
-- draws every character as one cell of this atlas. `advances` holds a per-glyph
-- advance in atlas pixels, which is what lets proportional faces (Segoe UI, Arial)
-- render correctly instead of being forced onto a monospaced grid.
return {
	generated = '$generated',
	id = '$($Variant.id)',
	label = '$($Variant.label)',
	font = '$familyName',
	kind = '$($Variant.kind)',
	style = '$($Variant.style)',
	baseSize = $($Variant.size),
	isDefault = $isDefault,
	file = 'Data/fonts/$($Variant.id).png',
	columns = $columns,
	rows = $rows,
	cellWidth = $cellWidth,
	cellHeight = $lineHeight,
	lineHeight = $lineHeight,
	codeCount = $($Codes.Count),
	codepoints = { $codeList },
	advances = { $advanceList },
	tracking = $variantTracking,
	-- Blank cells in the atlas: codepoints this face cannot draw. A non-empty list that
	-- includes Cyrillic means the panel must not be shown in Russian with this atlas.
	missingGlyphs = { $(($missing | ForEach-Object { $_ }) -join ', ') },
	missingCount = $($missing.Count),
}
"@
	$luaPath = Join-Path $fontsDir ($Variant.id + '.lua')
	[System.IO.File]::WriteAllText($luaPath, $lua, (New-Object System.Text.UTF8Encoding($false)))

	$info = Get-Item $pngPath
	$missingNote = if ($missing.Count -gt 0) { ", missing glyphs: $($missing.Count)" } else { ", all glyphs present" }
	Write-Host ("  {0,-20} atlas {1}x{2}, cell {3}x{4}, {5:N0} kB{6}" -f $Variant.id, $atlasWidth, $atlasHeight,
		$cellWidth, $lineHeight, ($info.Length / 1KB), $missingNote)
	return $true
}

$codes = Get-Codes
$targets = if ($Id) { $candidates | Where-Object { $_.id -eq $Id } } else { $candidates }
if ($Id -and -not $targets) { throw "Unknown variant '$Id'. Available: $($candidates.id -join ', ')" }

Write-Host "Building atlases ($($targets.Count)):"
$built = @()
foreach ($variant in $targets) {
	if (Build-Atlas -Variant $variant -Codes $codes) { $built += $variant }
}

if ($built.Count -gt 0) {
	$lines = @()
	$lines += '-- PoE2 Craft Overlay : Data/fonts.lua'
	$lines += '-- GENERATED FILE - do not edit by hand (tools/build_fonts.ps1).'
	$lines += '--'
	$lines += '-- Available glyph atlases. `ui.fontVariant` in Data/config.lua picks one; the'
	$lines += '-- comparison render (font_compare.flag) draws all of them for side-by-side review.'
	$lines += 'return {'
	$lines += "`tdefault = '$defaultId',"
	$lines += "`tgenerated = '$(Get-Date -Format 'yyyy-MM-dd HH:mm')',"
	$lines += "`tvariants = {"
	foreach ($variant in $built) {
		$lines += "`t`t{ id = '$($variant.id)', label = '$($variant.label)', kind = '$($variant.kind)', family = '$($variant.family)', size = $($variant.size), style = '$($variant.style)' },"
	}
	$lines += "`t},"
	$lines += '}'
	$lines += ''
	[System.IO.File]::WriteAllText($manifestPath, ($lines -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
	Write-Host "Manifest: Data/fonts.lua (default '$defaultId', variants $($built.Count))"
}
