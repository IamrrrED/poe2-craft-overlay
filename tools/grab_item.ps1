<#
.SYNOPSIS
  Capture the item tooltip on screen and read its text.

.DESCRIPTION
  Two steps in one process, because the overlay needs both for a single hotkey press:

    1. grab a screen region with GDI+ (System.Drawing) and save it as PNG;
    2. run it through the OCR engine that ships with Windows
       (Windows.Media.Ocr), which needs no installation, no network and no API key.

  The text is meant to be fed straight into the overlay's item parser, which already
  understands the game's copied-item format, so the OCR only has to be good, not perfect:
  the site shows the picture next to what was read, and the overlay falls back to the
  clipboard when the reading is empty.

  Windows PowerShell 5.1 cannot await WinRT operations directly, hence the well-known
  AsTask/Await helper below.

.PARAMETER X
  Left edge of the region. Omitted: measured from the cursor.

.PARAMETER Y
  Top edge of the region. Omitted: measured from the cursor.

.PARAMETER Width
  Region width in pixels (default 640).

.PARAMETER Height
  Region height in pixels (default 780).

.PARAMETER OffsetX
  Gap between the cursor and the region when X is derived from it (default 22).

.PARAMETER OffsetY
  Vertical offset from the cursor when Y is derived from it (default -40).

.PARAMETER Scale
  Upscale factor before OCR; the game's font is small, and the engine reads larger text
  more reliably (default 2).

.PARAMETER OutPng
  Where to save the capture (default src\capture.png).

.PARAMETER OutText
  Where to save the recognised text (default src\ocr_item.txt).

.PARAMETER Image
  Recognise this file instead of capturing the screen. Used by the tests and to re-read a
  capture that was kept.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\grab_item.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\grab_item.ps1 -X 900 -Y 300 -Width 700 -Height 800
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\grab_item.ps1 -Image tools\cache\ocr_sample.png
#>
[CmdletBinding()]
param(
	[int]$X = [int]::MinValue,
	[int]$Y = [int]::MinValue,
	# The box sits at the cursor, so it has to be big enough for the largest tooltip: a rare
	# item with six modifiers and a long name runs past 640x780 at a high interface scale, and
	# a clipped tooltip is exactly what made OCR return "too short" text.
	[int]$Width = 940,
	[int]$Height = 1150,
	[int]$OffsetX = 22,
	[int]$OffsetY = -40,
	[double]$Scale = 3,
	[switch]$NoPreprocess,
	[string]$OutPng = "src\capture.png",
	[string]$OutText = "src\ocr_item.txt",
	[string]$Image = ""
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# --- 1. screen region ------------------------------------------------------------

if ($Image) {
	$outPngPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Image))
	if (-not (Test-Path $outPngPath)) { throw "no such image: $outPngPath" }
	$X = 0; $Y = 0
} else {
	if ($X -eq [int]::MinValue -or $Y -eq [int]::MinValue) {
		Add-Type -AssemblyName System.Windows.Forms
		$cursor = [System.Windows.Forms.Cursor]::Position
		$X = $cursor.X + $OffsetX
		$Y = $cursor.Y + $OffsetY
	}

	$screen = [System.Windows.Forms.Screen]::FromPoint((New-Object System.Drawing.Point($X, $Y)))
	$bounds = $screen.Bounds
	# Keep the region on screen: a capture that runs off the edge comes back black.
	if ($X + $Width -gt $bounds.Right) { $Width = [Math]::Max(80, $bounds.Right - $X) }
	if ($Y + $Height -gt $bounds.Bottom) { $Height = [Math]::Max(80, $bounds.Bottom - $Y) }

	$bitmap = New-Object System.Drawing.Bitmap($Width, $Height)
	$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
	$graphics.CopyFromScreen($X, $Y, 0, 0, (New-Object System.Drawing.Size($Width, $Height)))
	$graphics.Dispose()

	$outPngPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutPng))
	$outDir = [System.IO.Path]::GetDirectoryName($outPngPath)
	if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
	$bitmap.Save($outPngPath, [System.Drawing.Imaging.ImageFormat]::Png)
}

# --- 2. OCR (Windows.Media.Ocr) ---------------------------------------------------

function Await($WinRtTask, $ResultType) {
	$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
			$_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
			$_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
		})[0]
	$netTask = $asTask.MakeGenericMethod($ResultType).Invoke($null, @($WinRtTask))
	$netTask.Wait(-1) | Out-Null
	$netTask.Result
}

function Get-OcrText([string]$Path, [double]$Scale, [bool]$Preprocess) {
	Add-Type -AssemblyName System.Runtime.WindowsRuntime
	$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
	$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
	$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
	$null = [Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]

	# One engine per language the client might be using. The Russian client needs the Russian
	# engine and an English one needs the English engine; running both and keeping the better
	# reading is more reliable than assuming which client is running. If neither pack exists,
	# the user profile list is a reasonable last try, and anything else means "no OCR here".
	$engines = @()
	foreach ($tag in @('en-US', 'ru-RU')) {
		try {
			$language = New-Object Windows.Globalization.Language $tag
			$candidate = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($language)
			if ($candidate) { $engines += [pscustomobject]@{ Name = $tag; Engine = $candidate } }
		} catch {
			# a missing language pack is not an error: the other engine still runs
		}
	}
	if ($engines.Count -eq 0) {
		$fallback = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
		if ($fallback) { $engines += [pscustomobject]@{ Name = 'user-profile'; Engine = $fallback } }
	}
	if ($engines.Count -eq 0) { throw 'no OCR engine available on this system' }

	# Upscale and clean up first. The tooltip font is ~14 px on a dark plate, which is the
	# worst case for the engine; converting to dark text on white and enlarging it is what
	# makes a modifier line come back with its percentages intact.
	$source = [System.Drawing.Image]::FromFile($Path)
	$target = New-Object System.Drawing.Bitmap(
		[int]($source.Width * $Scale), [int]($source.Height * $Scale))
	$canvas = [System.Drawing.Graphics]::FromImage($target)
	$canvas.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
	$canvas.DrawImage($source, 0, 0, $target.Width, $target.Height)
	$canvas.Dispose()
	$source.Dispose()

	if ($Preprocess) {
		# Luminance threshold with an automatic polarity: the game draws light text on a
		# dark plate, and OCR wants the opposite.
		$total = 0.0
		$count = 0
		for ($y = 0; $y -lt $target.Height; $y += 4) {
			for ($x = 0; $x -lt $target.Width; $x += 4) {
				$pixel = $target.GetPixel($x, $y)
				$total += (0.299 * $pixel.R + 0.587 * $pixel.G + 0.114 * $pixel.B)
				$count++
			}
		}
		$mean = if ($count -gt 0) { $total / $count } else { 128 }
		$invert = $mean -lt 128
		$threshold = if ($invert) { [Math]::Max(70, $mean + 40) } else { [Math]::Min(185, $mean - 20) }

		$rect = New-Object System.Drawing.Rectangle(0, 0, $target.Width, $target.Height)
		$data = $target.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite,
			[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
		$bytes = New-Object byte[] ($data.Stride * $target.Height)
		[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
		for ($index = 0; $index -lt $bytes.Length; $index += 4) {
			$luma = 0.299 * $bytes[$index + 2] + 0.587 * $bytes[$index + 1] + 0.114 * $bytes[$index]
			$ink = if ($invert) { $luma -gt $threshold } else { $luma -lt $threshold }
			$value = if ($ink) { 0 } else { 255 }
			$bytes[$index] = $value; $bytes[$index + 1] = $value; $bytes[$index + 2] = $value
		}
		[System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
		$target.UnlockBits($data)
	}

	$scaledPath = [System.IO.Path]::ChangeExtension($Path, '.scaled.png')
	$target.Save($scaledPath, [System.Drawing.Imaging.ImageFormat]::Png)
	$target.Dispose()

	$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($scaledPath)) ([Windows.Storage.StorageFile])
	$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
	$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
	$software = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
	# Every engine reads the same bitmap and the best reading wins. An item names its rarity and
	# its class, and a readable tooltip gives more lines than noise does, so those two signals
	# are enough to tell a correct reading from one produced by the wrong language.
	$best = $null
	foreach ($candidate in $engines) {
		try {
			$reading = Await ($candidate.Engine.RecognizeAsync($software)) ([Windows.Media.Ocr.OcrResult])
			$joined = (($reading.Lines | ForEach-Object { $_.Text }) -join "`n")
			$score = $reading.Lines.Count
			foreach ($marker in @('Rarity', 'Редкость', 'Item Class', 'Класс предмета', 'Item Level', 'Уровень предмета')) {
				if ($joined -like ('*' + $marker + '*')) { $score += 100 }
			}
			if ($script:OcrTrace) { Write-Host ("    OCR {0}: строк {1}, оценка {2}" -f $candidate.Name, $reading.Lines.Count, $score) }
			if (-not $best -or $score -gt $best.Score) {
				$best = [pscustomobject]@{ Score = $score; Reading = $reading; Engine = $candidate.Name }
			}
		} catch {
			# an engine that refuses this bitmap is simply skipped
		}
	}
	if (-not $best) { throw 'OCR produced no result on this system' }
	$result = $best.Reading
	$stream.Dispose()
	Remove-Item $scaledPath -ErrorAction SilentlyContinue

	# One recognised line per line: joining everything with spaces glues an item name to
	# its base type, and the parser then cannot match the base. Word order inside a line
	# is preserved, so each line is rebuilt from its words.
	$builder = New-Object System.Text.StringBuilder
	foreach ($line in $result.Lines) {
		$words = @()
		foreach ($word in $line.Words) { $words += $word.Text }
		$null = $builder.AppendLine(($words -join ' '))
	}
	if ($builder.Length -eq 0) { return $result.Text }
	return $builder.ToString().TrimEnd()
}

function Get-Levenshtein([string]$A, [string]$B) {
	$previous = New-Object int[] ($B.Length + 1)
	$current = New-Object int[] ($B.Length + 1)
	for ($j = 0; $j -le $B.Length; $j++) { $previous[$j] = $j }
	for ($i = 1; $i -le $A.Length; $i++) {
		$current[0] = $i
		for ($j = 1; $j -le $B.Length; $j++) {
			$cost = if ($A[$i - 1] -eq $B[$j - 1]) { 0 } else { 1 }
			$current[$j] = [Math]::Min([Math]::Min($current[$j - 1] + 1, $previous[$j] + 1), $previous[$j - 1] + $cost)
		}
		$swap = $previous; $previous = $current; $current = $swap
	}
	return $previous[$B.Length]
}

function Repair-OcrText([string]$Text) {
	# Windows OCR misreads small serif text on a dark background. Two kinds of repair, both
	# data-driven and both limited to the vocabulary an item tooltip can contain:
	#   1. distortions seen in practice (kept short and explicit);
	#   2. any other word that is one or two edits away from exactly one vocabulary word.
	# A word that matches nothing is left exactly as it was read - nothing is invented.
	$known = @{
		'Ina\.xinuun' = 'maximum'
		'auginented' = 'augmented'
		'maxinium' = 'maximum'
		'Kesistance' = 'Resistance'
		'Resistanee' = 'Resistance'
		'Evasiou' = 'Evasion'
		'Llfe' = 'Life'
		'Llfe:' = 'Life:'
	}
	foreach ($pattern in $known.Keys) {
		$Text = [regex]::Replace($Text, $pattern, $known[$pattern])
	}

	$vocabularyPath = Join-Path $PSScriptRoot 'cache\vocabulary.txt'
	if (-not (Test-Path $vocabularyPath)) { return $Text }
	$vocabulary = @(Get-Content $vocabularyPath | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })

	$lines = $Text -split "`r?`n"
	for ($index = 0; $index -lt $lines.Count; $index++) {
		$words = $lines[$index] -split '(\s+)'
		for ($word = 0; $word -lt $words.Count; $word++) {
			$token = $words[$word]
			$bare = $token.Trim([char[]]'.,;:()[]%+-')
			if ($bare.Length -lt 5 -or $vocabulary -contains $bare) { continue }
			$best = $null; $bestDistance = 99; $ambiguous = $false
			foreach ($candidate in $vocabulary) {
				if ([Math]::Abs($candidate.Length - $bare.Length) -gt 2) { continue }
				$distance = Get-Levenshtein $bare $candidate
				if ($distance -lt $bestDistance) { $best = $candidate; $bestDistance = $distance; $ambiguous = $false }
				elseif ($distance -eq $bestDistance) { $ambiguous = $true }
			}
			if ($best -and $bestDistance -le 2 -and -not $ambiguous) {
				$words[$word] = $token.Replace($bare, $best)
			}
		}
		$lines[$index] = ($words -join '')
	}
	return ($lines -join "`r`n")
}

$recognised = ''
$ocrError = ''
try {
	$recognised = Get-OcrText -Path $outPngPath -Scale $Scale -Preprocess (-not $NoPreprocess)
	$recognised = Repair-OcrText -Text $recognised
} catch {
	$ocrError = $_.Exception.Message
}

$outTextPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutText))
if ($recognised) {
	[System.IO.File]::WriteAllText($outTextPath, $recognised, (New-Object System.Text.UTF8Encoding($false)))
} else {
	Remove-Item $outTextPath -ErrorAction SilentlyContinue
}

# The overlay reads this summary from stdout; the picture is proof of what was read.
$lines = if ($recognised) { ($recognised -split "`r?`n").Count } else { 0 }
"captured={0},{1} {2}x{3}" -f $X, $Y, $Width, $Height
"png={0}" -f $outPngPath
"text={0}" -f $outTextPath
"lines={0}" -f $lines
"ocr_error={0}" -f $ocrError
