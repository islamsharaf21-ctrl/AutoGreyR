$ErrorActionPreference = "Stop"

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Helper = Join-Path $Here "AUTOGREY_V2_P11C_FROZEN_CONFIRMATORY_SCORING_R1.py"
$WslUser = if ($env:AUTOGREY_WSL_USER) { $env:AUTOGREY_WSL_USER } else { $env:USERNAME }
$Py = if ($env:AUTOGREY_WSL_PYTHON) { $env:AUTOGREY_WSL_PYTHON } else { "/home/$WslUser/.autogrey_p6_selector/venv-py3135/bin/python" }

$Downloads = if ($env:AUTOGREY_DOWNLOADS) { $env:AUTOGREY_DOWNLOADS } else { Join-Path $HOME "Downloads" }
$Work = if ($env:AUTOGREY_WORKSPACE) { $env:AUTOGREY_WORKSPACE } else { Join-Path $Downloads "AUTOGREY_V2_P4_WORKSPACE" }
$P10 = $Work
$P11A1 = $Work
$P11A2 = Join-Path $Work "AUTOGREY_V2_P11A2_FINAL_TARGET_FREE_PRODUCTION_R3"
$P11B = if ($env:AUTOGREY_P11B_DIR) { $env:AUTOGREY_P11B_DIR } else { Join-Path $Downloads "AUTOGREY_V2_P11B_IRREVERSIBLE_TARGET_OPENING_R1_OUTPUT" }
$R4Evidence = if ($env:AUTOGREY_R4_EVIDENCE) { $env:AUTOGREY_R4_EVIDENCE } else { Join-Path $Downloads "AUTOGREY_V2_P11C0_R4_PASS_CLOSED_EVIDENCE.zip" }
$PreflightOut = Join-Path $Downloads "AUTOGREY_V2_P11C_PREFLIGHT_R1_OUTPUT"
$PreflightJson = Join-Path $PreflightOut "AUTOGREY_V2_P11C_PREFLIGHT_R1.json"
$Out = Join-Path $Downloads "AUTOGREY_V2_P11C_FROZEN_CONFIRMATORY_SCORING_R1_OUTPUT"

function To-Wsl([string]$p) {
    $p = [IO.Path]::GetFullPath($p)
    return "/mnt/" + $p.Substring(0,1).ToLower() + "/" + $p.Substring(3).Replace("\","/")
}

if (-not (Test-Path -LiteralPath $PreflightJson -PathType Leaf)) {
    throw "P11-C score-free preflight PASS artifact is required before scoring: $PreflightJson"
}
$Preflight = Get-Content -LiteralPath $PreflightJson -Raw | ConvertFrom-Json
if ($Preflight.status -ne "PASS" -or
    $Preflight.target_binary_numeric_values_read -ne $false -or
    $Preflight.scientific_scoring_performed -ne $false -or
    $Preflight.scientific_lock_changed -ne $false -or
    $Preflight.p12_locked -ne $true) {
    throw "P11-C preflight artifact does not authorize scoring."
}
if (Test-Path -LiteralPath $Out) {
    throw "P11-C scoring output already exists; nothing overwritten: $Out"
}

Write-Host "===== AUTOGREY V2 P11-C FROZEN CONFIRMATORY SCORING R1 ====="
Write-Host "REALBENCH3_TARGET_STATE=PERMANENTLY_OPEN"
Write-Host "P11C_SCORE_FREE_PREFLIGHT=PASS"
Write-Host "P12=LOCKED"

wsl.exe $Py (To-Wsl $Helper) `
    --mode score `
    --out (To-Wsl $Out) `
    --p10 (To-Wsl $P10) `
    --p11a1 (To-Wsl $P11A1) `
    --p11a2 (To-Wsl $P11A2) `
    --p11b (To-Wsl $P11B) `
    --r4-evidence (To-Wsl $R4Evidence)

$c = $LASTEXITCODE
Write-Host "P11C_SCORING_EXIT_CODE=$c"
if ($c -ne 0) {
    Write-Host "P11C_RESULT=INCONCLUSIVE_EXECUTION_OR_ALIGNMENT_FAILURE"
    Write-Host "SCIENTIFIC_CHANGE_ALLOWED=FALSE"
    Write-Host "P12=LOCKED"
    exit $c
}
Write-Host "P11C_SCORING_COMMAND_COMPLETED=TRUE"
Write-Host "P12=LOCKED"
exit 0
