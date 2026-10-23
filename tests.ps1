<#
.SYNOPSIS
  Runs the overlay's headless self-tests.

.DESCRIPTION
  The tests execute inside the real shipping host (SimpleGraphic + LuaJIT x64) rather
  than a desktop Lua install, so parser/advisor behaviour is verified against the exact
  interpreter the overlay runs on.

  Protocol: drop a run_tests.flag marker next to Launch.lua. The entry point detects it,
  runs src/Tests/runner.lua, writes src/test_results.txt and finally src/test_done.flag.
  The host ignores Exit()/os.exit() coming from its init callback, so *this script* owns
  the process lifecycle: it waits for the marker and then closes the process. Pass/fail
  is taken from test_results.txt, not from the process exit code.

.OUTPUTS
  Exit code 0 when every assertion passes, 1 otherwise.
#>
[CmdletBinding()]
param(
	[int]$TimeoutSeconds = 45
)

$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$srcDir = Join-Path $projectRoot 'src'
$exe = Join-Path $projectRoot 'runtime\Path{space}of{space}Building-PoE2.exe'
$flag = Join-Path $srcDir 'run_tests.flag'
$done = Join-Path $srcDir 'test_done.flag'
$results = Join-Path $srcDir 'test_results.txt'
$trace = Join-Path $srcDir 'test_trace.txt'

if (-not (Test-Path -LiteralPath $exe)) {
	throw "Runtime is not deployed. Run .\setup.ps1 first."
}

Remove-Item -LiteralPath $results, $done, $trace -ErrorAction SilentlyContinue
New-Item -ItemType File -Force -Path $flag | Out-Null

$proc = $null
try {
	$proc = Start-Process -FilePath $exe -WorkingDirectory $projectRoot -PassThru
	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	while ((Get-Date) -lt $deadline) {
		if (Test-Path -LiteralPath $done) { break }
		if ($proc.HasExited) { break }
		Start-Sleep -Milliseconds 250
	}
}
finally {
	Remove-Item -LiteralPath $flag -ErrorAction SilentlyContinue
	if ($proc -and -not $proc.HasExited) {
		# Expected path: the host does not terminate itself from the init callback.
		$proc.Kill()
		$proc.WaitForExit(5000) | Out-Null
	}
}

if (-not (Test-Path -LiteralPath $results)) {
	if (Test-Path -LiteralPath $trace) {
		Write-Host '--- test_trace.txt ---' -ForegroundColor DarkGray
		Get-Content -LiteralPath $trace
	}
	throw 'The tests did not produce test_results.txt (see the trace above and the runtime console).'
}

$content = Get-Content -LiteralPath $results -Encoding UTF8
$content | ForEach-Object { Write-Host $_ }

$failedLines = $content | Where-Object { $_ -like 'FAIL*' }
$summary = $content | Where-Object { $_ -like 'RESULT:*' } | Select-Object -Last 1
Write-Host ''
if ($failedLines -or $summary -notmatch 'failed=0') {
	Write-Host 'TESTS FAILED' -ForegroundColor Red
	exit 1
}
Write-Host 'ALL TESTS PASSED' -ForegroundColor Green
Write-Host '(process closed by the runner: the host does not exit by itself in OnInit)' -ForegroundColor DarkGray
exit 0
