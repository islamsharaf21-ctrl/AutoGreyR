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
$Out = Join-Path $Downloads "AUTOGREY_V2_P11C_PREFLIGHT_R1_OUTPUT"

function To-Wsl([string]$p) {
    $p = [IO.Path]::GetFullPath($p)
    return "/mnt/" + $p.Substring(0,1).ToLower() + "/" + $p.Substring(3).Replace("\","/")
}

if (Test-Path -LiteralPath $Out) {
    throw "P11-C preflight output already exists; nothing overwritten: $Out"
}

Write-Host "===== AUTOGREY V2 P11-C SCORE-FREE PREFLIGHT R1 ====="
Write-Host "REALBENCH3_TARGET_STATE=PERMANENTLY_OPEN"
Write-Host "P11C_NUMERIC_TARGET_SCORING_START=FALSE"
Write-Host "P12=LOCKED"

wsl.exe $Py (To-Wsl $Helper) `
    --mode preflight `
    --out (To-Wsl $Out) `
    --p10 (To-Wsl $P10) `
    --p11a1 (To-Wsl $P11A1) `
    --p11a2 (To-Wsl $P11A2) `
    --p11b (To-Wsl $P11B) `
    --r4-evidence (To-Wsl $R4Evidence)

$c = $LASTEXITCODE
Write-Host "P11C_PREFLIGHT_EXIT_CODE=$c"
if ($c -ne 0) {
    Write-Host "P11C_PREFLIGHT_RESULT=INCONCLUSIVE_EXECUTION_OR_ALIGNMENT_FAILURE"
    Write-Host "P11C_SCIENTIFIC_SCORING=FALSE"
    Write-Host "P11C_TARGET_INDEX_BINARY_SLICE_SCHEMA_BOUND=UNKNOWN_UNTIL_SCORER_PREFLIGHT"
    Write-Host "P12=LOCKED"
    exit $c
}
