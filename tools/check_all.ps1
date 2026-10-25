# PoE2 Craft Overlay : every check, in one command.
#
# The project has four kinds of check and they were only ever run one at a time: the Lua suite in the shipping
# engine (tests.ps1), the source-level checks on the panel and the C# host (the python tools), the generated
# item corpus (which must match its sources), and the build itself. A green run of one of them said nothing
# about the others, which is how a dictionary that failed to compile stayed invisible.
#
#   powershell -ExecutionPolicy Bypass -File tools\check_all.ps1
#
# Every step runs even when an earlier one fails, so one run shows the whole picture; the exit code is
# non-zero if anything failed.

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Push-Location $root
$failures = @()
$timings = @()

function Step($name, $block) {
    Write-Host ""
    Write-Host "=== $name" -ForegroundColor Cyan
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    & $block
    $watch.Stop()
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 0 }
    $script:timings += [pscustomobject]@{ Step = $name; Seconds = [math]::Round($watch.Elapsed.TotalSeconds, 1); Exit = $code }
    if ($code -ne 0) { $script:failures += "$name (exit $code)" }
}

Step "engine test suite" {
    & powershell -NoProfile -ExecutionPolicy Bypass -File .\tests.ps1 | Select-String -Pattern 'TOTAL|RESULT|^FAIL' | ForEach-Object { $_.Line }
}

Step "panel chrome: keys, language parity, glossary" {
    & python tools\check_panel_i18n.py
}

Step "host messages: both languages, placeholders, call sites" {
    & python tools\check_host_messages.py
}

Step "modifier price cache (node self-test, no network)" {
    & node tools\lib\mod_cache.js --self-test
    if ($LASTEXITCODE -ne 0) { throw "mod cache self-test failed" }
}
Step "game probe: refuses without permission, points stay inside the inventory" {
    $exe = Join-Path $PSScriptRoot '..\overlay\bin\Debug\net8.0-windows\Poe2CraftOverlay.exe'
    if (-not (Test-Path $exe)) {
        $exe = Join-Path $PSScriptRoot '..\overlay\bin\Release\net8.0-windows\Poe2CraftOverlay.exe'
    }
    if (-not (Test-Path $exe)) { throw "панель не собрана" }
    $report = Join-Path (Split-Path $exe) 'probe-report.txt'
    Remove-Item $report -ErrorAction SilentlyContinue
    $old = $env:POE2CRAFT_PROBE
    Remove-Item Env:POE2CRAFT_PROBE -ErrorAction SilentlyContinue
    & $exe --probe-capture | Out-Null
    for ($i = 0; $i -lt 40 -and -not (Test-Path $report); $i++) { Start-Sleep -Milliseconds 250 }
    $refused = (Get-Content $report -Encoding UTF8 -ErrorAction SilentlyContinue) -join ' '
    if ($refused -notmatch 'POE2CRAFT_PROBE is not 1') { throw "зонд не отказался без разрешения: $refused" }
    if ($old) { $env:POE2CRAFT_PROBE = $old }
    Write-Host "PASS probe refuses without POE2CRAFT_PROBE=1"

    $pointsFile = Join-Path (Split-Path $exe) 'probe-candidates.txt'
    Remove-Item $pointsFile -ErrorAction SilentlyContinue
    & $exe --probe-candidates 1920 1080 | Out-Null
    for ($i = 0; $i -lt 40 -and -not (Test-Path $pointsFile); $i++) { Start-Sleep -Milliseconds 250 }
    $points = Get-Content $pointsFile -Encoding UTF8 | Where-Object { $_ -match '^\d+,\d+$' }
    if (-not $points -or $points.Count -lt 4) { throw "точек наведения нет" }
    foreach ($point in $points) {
        $parts = $point -split ','
        $x = [int]$parts[0]; $y = [int]$parts[1]
        if ($x -gt 640 -or $y -lt 216 -or $y -gt 648) { throw "точка вне области инвентаря: $point" }
    }
    Write-Host "PASS probe hover points stay inside the inventory ($($points.Count) points)"
}
Step "market refusal reasons have Russian" {
    & python tools\check_market_reasons.py
}

Step "the generated item corpus is up to date" {
    & python tools\build_item_corpus.py --check
}

Step "the data files carry no raw newlines inside strings" {
    & python tools\repair_lua_newlines.py --check
}

# Chrome-based: the page is rendered and its DOM read, so a button that only "exists" in source but never
# renders is caught. Skipped (with a note) when Chrome is not installed.
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
Step "buy verdict renders in a real page (Chrome)" {
    if (Test-Path $chrome) {
        & python tools\check_buy_verdict.py
    } else {
        Write-Host "skipped: Chrome not found at $chrome" -ForegroundColor Yellow
        $global:LASTEXITCODE = 0
    }
}

Step "the overlay builds" {
    & dotnet build overlay\Overlay.csproj -c Release --nologo | Select-String -Pattern 'error|Ошибок|Warning\(s\)' | ForEach-Object { $_.Line }
}

Pop-Location

Write-Host ""
$timings | Format-Table -AutoSize | Out-String | Write-Host
if ($failures.Count -eq 0) {
    Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
    exit 0
}
Write-Host ("FAILED: " + ($failures -join '; ')) -ForegroundColor Red
exit 1
