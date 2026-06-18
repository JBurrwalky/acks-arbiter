<#
.SYNOPSIS
    Run the ACKS Arbiter headless test suite in an APPDATA-isolated user dir.

.DESCRIPTION
    Godot derives user:// from %APPDATA% (+ the project name). Every git worktree
    of this project shares the same project name, so by default they ALSO share
    one user://campaign.db — which is why a test run in one worktree wipes the
    playtest data used by another, and why concurrent runs collide with
    "database is locked" spam.

    This wrapper points %APPDATA% at a STABLE per-worktree temp dir before
    launching Godot, giving the suite a fully private campaign.db + saves. It
    NEVER touches the player's live save data, and two worktrees never fight over
    one DB. The dir is stable per worktree, so re-runs reuse the same isolated
    test DB (no fresh-DB FK-noise on every run).

    Belt-and-suspenders: it also passes `-- --test`, which CampaignRepository
    detects to redirect to campaign_test.db even if APPDATA isolation were
    bypassed.

.PARAMETER Runs
    How many times to run the suite. Defaults to 2: a freshly-created isolated
    APPDATA starts with an empty DB, so run 1 applies all migrations and leaves
    foreign_keys ON (latent-FK noise); measure pass/fail on run 2. After the
    first invocation the dir persists, so subsequent invocations are clean on
    run 1 too — but 2 stays the safe default.

.PARAMETER Godot
    Path to the Godot console executable.

.EXAMPLE
    pwsh tools/run_tests.ps1
    pwsh tools/run_tests.ps1 -Runs 1
#>
param(
    [int]$Runs = 2,
    [string]$Godot = "C:\godot\Godot_v4.6.1-stable_win64_console.exe"
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# Stable per-worktree hash -> private %APPDATA% under TEMP.
$sha = [System.Security.Cryptography.SHA1]::Create()
$hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($projectRoot))
$hash = ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').Substring(0, 8).ToLower()
$isolatedAppData = Join-Path $env:TEMP "acks_test_appdata_$hash"
New-Item -ItemType Directory -Force -Path $isolatedAppData | Out-Null

$env:APPDATA = $isolatedAppData
Write-Host "ACKS Arbiter test suite"
Write-Host "  project       : $projectRoot"
Write-Host "  isolated APPDATA: $isolatedAppData"
Write-Host "  (live save data in your real %APPDATA% is never touched)"

if (-not (Test-Path $Godot)) {
    Write-Error "Godot executable not found at '$Godot'. Pass -Godot <path>."
    exit 1
}

# Godot writes copiously to stderr (push_warning / push_error / ASSERTION). In
# Windows PowerShell 5.1, `*>`/`2>&1` on a native exe wraps each stderr line as a
# NativeCommandError and, under ErrorActionPreference=Stop, ABORTS the run. Do the
# redirect in cmd (`> file 2>&1`) instead, and let a non-zero test exit be data,
# not a thrown error. (cmd passes Godot's UTF-8 stdout through verbatim, so the
# log greps cleanly — no UTF-16 spacing artifacts.)
$ErrorActionPreference = "Continue"
$log = Join-Path $projectRoot "headless_test_run.log"
$exit = 0
for ($i = 1; $i -le $Runs; $i++) {
    Write-Host "--- Run $i of $Runs ---"
    & cmd /c "`"$Godot`" --headless --path `"$projectRoot`" res://tests/test_runner.tscn -- --test > `"$log`" 2>&1"
    $exit = $LASTEXITCODE
    Write-Host "Run $i exit code: $exit (non-zero just means some suites failed; see log)"
}

Write-Host "Done. Full log: $log"
Write-Host "Summary (last lines):"
Select-String -Path $log -Pattern "TEST MODE|passed|failed|PASS|FAIL|TOTAL" |
    Select-Object -Last 12 |
    ForEach-Object { "  " + $_.Line }

exit $exit
