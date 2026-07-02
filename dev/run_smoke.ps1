# Runs the headless smoke test and fails on script errors that Godot's exit
# code misses (a GDScript error can abort a coroutine without failing the run).
# Usage: powershell -File dev\run_smoke.ps1 [-Godot <path-to-godot-console-exe>]
param(
    [string]$Godot = "C:\Users\GAMING\Claude\Projects\uberstrike game building\tools\godot\Godot_v4.7-stable_win64_console.exe"
)
$repo = Split-Path $PSScriptRoot -Parent
$out = & $Godot --headless --path $repo --script res://dev/smoke_test.gd 2>&1 | Out-String
Write-Host $out
$hasErrors = $out -match "SCRIPT ERROR"
$passed = $out -match "=== smoke: PASS ==="
if ($LASTEXITCODE -ne 0 -or $hasErrors -or -not $passed) {
    Write-Host ">>> SMOKE FAILED (exit=$LASTEXITCODE scriptErrors=$hasErrors passed=$passed)"
    exit 1
}
Write-Host ">>> SMOKE OK"
exit 0
