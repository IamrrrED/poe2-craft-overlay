# Builds a clean, source-only snapshot of the project and publishes it to GitHub.
#
# Publishing the working folder as-is would upload 700 MB of build output (app/, runtime/, bin/, node_modules,
# WebView2 profile). This script copies only what a stranger needs to read and build the project, checks the
# result for size, and then either stops (dry run) or pushes it to the repository you name.
#
#   powershell -ExecutionPolicy Bypass -File tools\publish_github.ps1 -DryRun
#   powershell -ExecutionPolicy Bypass -File tools\publish_github.ps1 -Remote https://github.com/USER/REPO.git
#
# Authentication is git's own: either a credential helper, or a token in the URL, or an SSH remote. This script
# never asks for a password and never stores one.

[CmdletBinding()]
param(
    [string]$Remote = "",
    [string]$OutDir = (Join-Path $env:TEMP "poe2craft-publish"),
    [string]$Branch = "main",
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

# Directories copied whole (relative to the project root).
$includeDirs = @(
    "src",
    "overlay\Ui",
    "tools",
    "mcp-market\lib",
    "docs"
)

# Single files that matter at the repository root.
$includeFiles = @(
    "README.md",
    "LICENSE",
    "NOTICE.md",
    ".gitignore",
    "tests.ps1"
)

# Extensions inside the included directories that belong in a source repository.
$includeExtensions = @(".lua", ".cs", ".csproj", ".html", ".css", ".js", ".py", ".ps1", ".json", ".md", ".png",
    ".ttf", ".ico", ".svg", ".sh", ".cmd", ".sln")

# Never copied, even inside an included directory.
$excludePatterns = @("__pycache__", "node_modules", "\bin\", "\obj\", "\.cache", "webview2-data", "tools\cache",
    "mcp_serve_", "last_item.txt", "craft_memory.lua", "probe_", "test_results.txt", "all.txt")

function Test-Excluded([string]$path) {
    foreach ($pattern in $excludePatterns) {
        if ($path -like "*$pattern*") { return $true }
    }
    return $false
}

Write-Host "== preparing the snapshot in $OutDir" -ForegroundColor Cyan
# The repository history lives in $OutDir\.git and must survive between publishes: wiping it would make every
# run a brand new first commit that GitHub rejects as non-fast-forward. Only the working tree is rebuilt.
if (Test-Path $OutDir) {
    Get-ChildItem $OutDir -Force | Where-Object { $_.Name -ne ".git" } | Remove-Item -Recurse -Force
} else {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

$copied = 0
$bytes = 0
$largest = @()

foreach ($dir in $includeDirs) {
    $sourceRoot = Join-Path $root $dir
    if (-not (Test-Path $sourceRoot)) { Write-Host "  skip (missing): $dir"; continue }
    foreach ($file in Get-ChildItem $sourceRoot -Recurse -File) {
        $relative = $file.FullName.Substring($root.Length).TrimStart('\')
        if (Test-Excluded $relative) { continue }
        if ($includeExtensions -notcontains $file.Extension.ToLower()) { continue }
        $target = Join-Path $OutDir $relative
        $targetDir = Split-Path -Parent $target
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        Copy-Item $file.FullName $target -Force
        $copied++
        $bytes += $file.Length
        $largest += [pscustomobject]@{ MB = [math]::Round($file.Length / 1MB, 2); Path = $relative }
    }
}

# Overlay's C# sources and project file live directly in overlay\, not in overlay\Ui.
foreach ($file in Get-ChildItem (Join-Path $root "overlay") -File -Filter "*.cs*") {
    $relative = $file.FullName.Substring($root.Length).TrimStart('\')
    Copy-Item $file.FullName (Join-Path $OutDir $relative) -Force
    $copied++
    $bytes += $file.Length
    $largest += [pscustomobject]@{ MB = [math]::Round($file.Length / 1MB, 2); Path = $relative }
}

foreach ($file in $includeFiles) {
    $source = Join-Path $root $file
    if (Test-Path $source) {
        Copy-Item $source (Join-Path $OutDir $file) -Force
        $copied++
        $bytes += (Get-Item $source).Length
    }
}

$sizeMb = [math]::Round($bytes / 1MB, 1)
Write-Host ("== files: {0}, size: {1} MB" -f $copied, $sizeMb) -ForegroundColor Green
Write-Host "== largest files:"
$largest | Sort-Object MB -Descending | Select-Object -First 5 | ForEach-Object { "   {0,6} MB  {1}" -f $_.MB, $_.Path }

# GitHub refuses files above 100 MB and warns above 50 MB; a source snapshot above 100 MB is a mistake anyway.
$tooBig = $largest | Where-Object { $_.MB -gt 50 }
if ($tooBig) {
    Write-Host "REFUSED: a file above 50 MB - look at the allow-list before publishing" -ForegroundColor Red
    $tooBig | ForEach-Object { "   {0} MB  {1}" -f $_.MB, $_.Path }
    exit 1
}
if ($sizeMb -gt 150) {
    Write-Host "REFUSED: snapshot above 150 MB - that is not source code" -ForegroundColor Red
    exit 1
}

if ($DryRun) {
    Write-Host "== dry run: nothing committed, nothing pushed" -ForegroundColor Yellow
    exit 0
}

if (-not $Remote) {
    Write-Host "No -Remote given, so the snapshot is ready but not pushed." -ForegroundColor Yellow
    Write-Host "Create an empty repository on GitHub, then run:"
    Write-Host "  powershell -ExecutionPolicy Bypass -File tools\publish_github.ps1 -Remote <repo-url>"
    exit 0
}

Write-Host "== git init + first commit" -ForegroundColor Cyan
Push-Location $OutDir
try {
    if (-not (Test-Path (Join-Path $OutDir ".git"))) {
        git init --initial-branch $Branch | Out-Null
    }
    git -c user.name="PoE2 Craft Overlay" -c user.email="overlay@localhost" add -A
    $message = @"
PoE2 Craft Overlay: crafting assistant for Path of Exile 2

A panel that answers "what do I click now, what does it cost, and when do I stop" instead of dumping item data.
Bilingual (Russian and English) panel and engine, routes built only from rules verified against independent
sources, price checks against the trade site of the player's own language, and slot checks that stop the advice
from suggesting a step the item cannot take.

First public snapshot: source only, no build output.
"@
    $messageFile = Join-Path $env:TEMP "poe2craft-commit-msg.txt"
    [System.IO.File]::WriteAllText($messageFile, $message, (New-Object System.Text.UTF8Encoding($false)))
    git -c user.name="PoE2 Craft Overlay" -c user.email="overlay@localhost" commit -q -F $messageFile
    # Read the config file instead of asking git: a missing remote makes git write to stderr, which Windows
    # PowerShell turns into a terminating error while ErrorActionPreference is Stop.
    $configPath = Join-Path $OutDir ".git\config"
    $hasOrigin = (Test-Path $configPath) -and ((Get-Content $configPath -Raw) -match '\[remote "origin"\]')
    if ($hasOrigin) { git remote set-url origin $Remote } else { git remote add origin $Remote }
    Write-Host "== pushing to $Remote ($Branch)" -ForegroundColor Cyan
    git push -u origin $Branch
    Write-Host "== done: $Remote" -ForegroundColor Green
}
finally {
    Pop-Location
}
