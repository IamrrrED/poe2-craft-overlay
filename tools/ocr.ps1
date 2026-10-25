# OCR через Windows.Media.Ocr: распознаёт текст в PNG и печатает строки с координатами.
#
# Почему так, а не своим движком: Windows уже содержит OCR с русским и английским распознавателем. Это снимает
# главную проблему чтения интерфейса игры (имена вкладок, названия предметов), не добавляя зависимостей.
#
#   powershell -File tools\ocr.ps1 -Path shot.png -Left 914 -Top 143 -Width 188 -Height 704
#
# Печатает JSON: { "lines": [ { "text": "...", "x": 10, "y": 20, "w": 80, "h": 14, "confidence": 0.91 } ], "lang": "ru" }

param(
    [Parameter(Mandatory = $true)][string]$Path,
    [int]$Left = 0,
    [int]$Top = 0,
    [int]$Width = 0,
    [int]$Height = 0,
    [string]$Language = "ru"
)

# The caller reads stdout as UTF-8 (the overlay runs powershell.exe and decodes UTF-8). Without this line the
# console code page mangles Cyrillic into question marks, and a wrong title reads as "no panel".
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Runtime.WindowsRuntime

# WinRT-типы подтягиваются лениво: без этого оператор :: на них не находится.
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]

function Await($operation, $resultType) {
    $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object { $_.Name -eq "AsTask" -and $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq "IAsyncOperation``1" } |
        Select-Object -First 1
    $task = $asTask.MakeGenericMethod($resultType).Invoke($null, @($operation))
    $task.Wait()
    return $task.Result
}

# Обрезаем область, если задана: OCR по всему кадру медленный и цепляет лишнее.
$source = [Windows.Storage.StorageFile]::GetFileFromPathAsync((Resolve-Path $Path).Path)
$file = Await $source ([Windows.Storage.StorageFile])
$stream = Await $file.OpenAsync([Windows.Storage.FileAccessMode]::Read) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])

$target = $bitmap
if ($Width -gt 0 -and $Height -gt 0) {
    # Простое обрезание через System.Drawing надёжнее WinRT-манипуляций с битмапом.
    Add-Type -AssemblyName System.Drawing
    $image = [System.Drawing.Image]::FromFile((Resolve-Path $Path).Path)
    $rect = New-Object System.Drawing.Rectangle $Left, $Top, $Width, $Height
    $crop = New-Object System.Drawing.Bitmap $Width, $Height
    $graphics = [System.Drawing.Graphics]::FromImage($crop)
    $graphics.DrawImage($image, (New-Object System.Drawing.Rectangle 0, 0, $Width, $Height), $rect,
        [System.Drawing.GraphicsUnit]::Pixel)
    $graphics.Dispose(); $image.Dispose()
    $temp = Join-Path $env:TEMP ("ocr-" + [guid]::NewGuid().ToString("N") + ".png")
    $crop.Save($temp, [System.Drawing.Imaging.ImageFormat]::Png)
    $crop.Dispose()
    $stream2 = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($temp)) ([Windows.Storage.StorageFile])
    $read2 = Await ($stream2.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    $decoder2 = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($read2)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $target = Await ($decoder2.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    Remove-Item $temp -ErrorAction SilentlyContinue
}

$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language $Language))
if ($null -eq $engine) {
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
}
if ($null -eq $engine) {
    Write-Output '{"lines":[],"error":"no ocr engine for that language"}'
    exit 1
}

$result = Await ($engine.RecognizeAsync($target)) ([Windows.Media.Ocr.OcrResult])
$lines = @()
foreach ($line in $result.Lines) {
    $words = $line.Words
    if ($words.Count -eq 0) { continue }
    $minX = ($words | ForEach-Object { $_.BoundingRect.X } | Measure-Object -Minimum).Minimum
    $minY = ($words | ForEach-Object { $_.BoundingRect.Y } | Measure-Object -Minimum).Minimum
    $maxX = ($words | ForEach-Object { $_.BoundingRect.X + $_.BoundingRect.Width } | Measure-Object -Maximum).Maximum
    $maxY = ($words | ForEach-Object { $_.BoundingRect.Y + $_.BoundingRect.Height } | Measure-Object -Maximum).Maximum
    $lines += [pscustomobject]@{
        text = $line.Text
        x    = [int]$minX
        y    = [int]$minY
        w    = [int]($maxX - $minX)
        h    = [int]($maxY - $minY)
    }
}
[pscustomobject]@{ lang = $engine.RecognizerLanguage.LanguageTag; lines = $lines } |
    ConvertTo-Json -Depth 5 -Compress
