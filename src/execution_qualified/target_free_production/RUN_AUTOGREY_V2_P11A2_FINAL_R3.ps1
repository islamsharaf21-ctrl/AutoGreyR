$ErrorActionPreference = "Stop"

$Downloads = if ($env:AUTOGREY_DOWNLOADS) { $env:AUTOGREY_DOWNLOADS } else { Join-Path $HOME "Downloads" }
$Workspace = if ($env:AUTOGREY_WORKSPACE) { $env:AUTOGREY_WORKSPACE } else { Join-Path $Downloads "AUTOGREY_V2_P4_WORKSPACE" }
$Release = if ($env:AUTOGREY_V1_RELEASE) { $env:AUTOGREY_V1_RELEASE } else { Join-Path $Downloads "AutoGreyR-1.0.0" }
$Legacy = if ($env:AUTOGREY_LEGACY_ROOT) { $env:AUTOGREY_LEGACY_ROOT } else { Join-Path $Downloads "Autigrey chatgpt files" }
$WslUser = if ($env:AUTOGREY_WSL_USER) { $env:AUTOGREY_WSL_USER } else { $env:USERNAME }
$WslPython = if ($env:AUTOGREY_WSL_PYTHON) { $env:AUTOGREY_WSL_PYTHON } else { "/home/$WslUser/.autogrey_p6_selector/venv-py3135/bin/python" }
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Roots = @($Here, $Workspace, $Release, $Legacy, $Downloads) | Where-Object { Test-Path $_ } | Select-Object -Unique

function Get-SHA256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Find-Exact([string]$Name, [string]$ExpectedHash) {
    $Hits = @()
    foreach ($root in $Roots) {
        $Candidates = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter $Name -ErrorAction SilentlyContinue)
        foreach ($f in $Candidates) {
            try { $h = Get-SHA256 $f.FullName } catch { continue }
            if ($h -eq $ExpectedHash.ToUpperInvariant()) { $Hits += $f }
        }
    }
    $Hits = @($Hits | Sort-Object FullName -Unique)
    if ($Hits.Count -lt 1) { throw "No exact-hash copy found for $Name expected=$ExpectedHash" }
    return ($Hits | Sort-Object @{Expression={$_.FullName.Length};Ascending=$true}, FullName | Select-Object -First 1).FullName
}

function Find-P3Pair {
    $HarnessHash = "3CD58049273A796F3C4D8C726528571F17D51F59DC74E6688874F826024FC8B0"
    $WorkerHash = "243FD64F99F3B0BB69492AE34876B156E2F8ABEDBF9152499EA271DDF789A45A"
    $Pairs = @()
    foreach ($root in $Roots) {
        $Candidates = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter "autogrey_v2_p3_harness.R" -ErrorAction SilentlyContinue)
        foreach ($hfile in $Candidates) {
            try { $hh = Get-SHA256 $hfile.FullName } catch { continue }
            if ($hh -ne $HarnessHash) { continue }
            $worker = Join-Path $hfile.Directory.FullName "autogrey_v2_p3_worker.R"
            if (-not (Test-Path -LiteralPath $worker -PathType Leaf)) { continue }
            if ((Get-SHA256 $worker) -ne $WorkerHash) { continue }
            $Pairs += [pscustomobject]@{Harness=$hfile.FullName;Worker=$worker}
        }
    }
    $Pairs = @($Pairs | Sort-Object Harness -Unique)
    if ($Pairs.Count -lt 1) { throw "No exact frozen P3 R5D harness/worker sibling pair found." }
    return ($Pairs | Sort-Object @{Expression={$_.Harness.Length};Ascending=$true}, Harness | Select-Object -First 1)
}

function To-WslPath([string]$WinPath) {
    $p = [System.IO.Path]::GetFullPath($WinPath)
    if ($p -match '^([A-Za-z]):\\(.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $rest = $Matches[2] -replace '\\','/'
        return "/mnt/$drive/$rest"
    }
    throw "Cannot translate to WSL path: $WinPath"
}

function BashQuote([string]$s) {
    if ($s.Contains("'")) { throw "Unexpected apostrophe in path passed to WSL: $s" }
    return "'" + $s + "'"
}

# Exact frozen external inputs. Scientific inputs are unchanged from R1.
$Index = Find-Exact "AUTOGREY_V2_P11A1_REALBENCH3_DEVELOPMENT_INDEX_R1.csv" "8EEA756829B7A97F033EA81E5C2783528B68374A7B7549CE2D3EEA4D02D1C58B"
$Binary = Find-Exact "AUTOGREY_V2_P11A1_REALBENCH3_DEVELOPMENT_FLOAT64_LE_R1.bin" "98648163F9ABE781EAA03EE49FD53D9BE1A33666F0A42BF7016B332F11E536F9"
$P10Final = Find-Exact "AUTOGREY_V2_P10_FINAL_FREEZE_R1.zip" "35A97B99D62D00E3C5FC44E4611513281B4690DDF1E48105348315FDCEE420E3"
$P1Seal = Find-Exact "AUTOGREY_V2_P1_FINAL_REALBENCH3_SEAL_PACK_2026-09-16.zip" "04B3E677CA3DC0B0F9E8B6074656E1233769F70E3D76493CEDA83AAAE4EAE882"
$P5Schema = Find-Exact "AUTOGREY_V2_P5_FINAL_META_FEATURE_SCHEMA_R1.csv" "3ED14225EFC4FA9030BF114A466D1FBF410F47FE8CBE054AF446C4775E099D59"
$P5Matrix = Find-Exact "AUTOGREY_V2_P5D3A_RAW_SELECTOR_MATRIX_R1.csv" "507CEA9A4878ADFD7454E9E80B129006995E7E7A3F30E642AD1CE1A8AE10093B"
$P6Labels = Find-Exact "AUTOGREY_V2_P6B_TRAIN_LABELS_13G_R3.csv" "ECF821876B86C0A2B62A01E49ABBE539CFE616731C9D72EDF1DE6971C51F6435"
$P7Selector = Find-Exact "AUTOGREY_V2_P7B_FULLTRAIN_SELECTOR_IDENTITY_R2.json" "825F1DAF2B29EDD31FF4F5449ACEFDBD769EA36084C7224346D0A77FA623E3BB"
$P7Global = Find-Exact "AUTOGREY_V2_P7B_FULLTRAIN_GLOBAL_RANK_R2.csv" "91137509FD59059530E531E5FA75DB372C565024DF0BAE245C62A1D9373E7933"
$C4Freeze = Find-Exact "AUTOGREY_V2_P11A2C4_FINAL_FAST_IMPLEMENTATION_FREEZE_R1.json" "7FCE8B071503D277425685BFA43569219D7AB9DBC8A227467342D7ACA1B0F774"
$R1Evidence = Find-Exact "AUTOGREY_V2_P11A2_FINAL_TARGET_FREE_PRODUCTION_R1_INCONCLUSIVE_2026-09-24.zip" "F00AD7CEC6236E1DE87980901CD37B1A55B2C3A9E786B711729D16937828061F"
$R2Evidence = Find-Exact "AUTOGREY_V2_P11A2_FINAL_TARGET_FREE_PRODUCTION_R2_INCONCLUSIVE_2026-09-26.zip" "664A00306D57776C7C5D3FB469E14B18B41112025E3A5E3214A8761818FBE3EF"
$P3Pair = Find-P3Pair
$P3Harness = $P3Pair.Harness
$P3Worker = $P3Pair.Worker

# Public-tree layout adapter. Frozen scientific files retain their recorded identities;
# only repository-relative locations differ from the historical execution bundle.
$RepoRoot = (Resolve-Path (Join-Path $Here "..\..\..")).Path
$ScientificLock = Join-Path $RepoRoot "config\scientific_contracts\AUTOGREY_V2_P11A2_FINAL_TARGET_FREE_PRODUCTION_LOCK_R1.json"
$R3RepairLock = Join-Path $RepoRoot "config\scientific_contracts\AUTOGREY_V2_P11A2_FINAL_SELECTOR_REPRESENTABILITY_REPAIR_LOCK_R3.json"
$Harness = Join-Path $Here "AUTOGREY_V2_P11A2_FINAL_TARGET_FREE_PRODUCTION_R3.py"
$RPreflight = Join-Path $Here "AUTOGREY_V2_P11A2_FINAL_R_RUNTIME_PREFLIGHT_R1.R"
$NewWorker = Join-Path $Here "AUTOGREY_V2_P11A2_FINAL_NEWGROUP_DONLY_WORKER_R2.R"
$Engine = Join-Path $RepoRoot "src\execution_qualified\grey_action_library\autogrey_engine_step4fb_r1.py"
$SG11 = Join-Path $RepoRoot "src\execution_qualified\grey_action_library\autogrey_v2_p4e1_fan_smgrey_R2.R"
$SG12 = Join-Path $RepoRoot "src\execution_qualified\grey_action_library\autogrey_v2_p11a2c2_sg12_candidate_R1.R"
$SG13 = Join-Path $RepoRoot "src\execution_qualified\grey_action_library\autogrey_v2_p11a2c2_sg13_candidate_R1.R"
$Features = Join-Path $RepoRoot "src\execution_qualified\features\autogrey_features_step4e.py"

$EmbeddedExpected = @(
    [pscustomobject]@{Path=$ScientificLock;Hash="54D2CA4024510992BF494C82DA6F729423461E3893508524EB439659986E693F"},
    [pscustomobject]@{Path=$R3RepairLock;Hash="4C7AD9E479EF946F04CE14F5059DB133EFFB17710E3947211AD4111C7B8208C2"},
    [pscustomobject]@{Path=$Harness;Hash="7CFE34D2857AD99893DF356624B34EDB997F7FF064F348152CCE23BABA5C0407"},
    [pscustomobject]@{Path=$RPreflight;Hash="26B57ADA1A08CFC40CD11187A2C41BC34A8196D1E3504DD2880E1E39DEACFAD6"},
    [pscustomobject]@{Path=$NewWorker;Hash="F8E50E535E35F9D654EE55C21B2F8E23BA4F6C7E7698DF2641F492124F8C0F80"},
    [pscustomobject]@{Path=$Engine;Hash="FC421E18E44C527C38E8DEDD3C30DE42506FA269AAD1498BAA56521DF21AA0F3"},
    [pscustomobject]@{Path=$SG11;Hash="6F7AF041001107E06E444990EC9F7C21D8D0E2A1F360BB6A4DE98C4D23AD848C"},
    [pscustomobject]@{Path=$SG12;Hash="8AEE4DFE49DF95DE9E9A15B123B2887A2AD66AF7C5695E837FB3807786E399F0"},
    [pscustomobject]@{Path=$SG13;Hash="1E0C5710A82134ED8C08F27D856D560F3F7D2B524F5937BCD2E21F5074A8B618"},
    [pscustomobject]@{Path=$Features;Hash="BBBD645CFFAE6462EB50CBB9FF5FB902912E6204DF1AB5A9A316428D58B7A113"}
)
foreach ($item in $EmbeddedExpected) {
    if (-not (Test-Path -LiteralPath $item.Path -PathType Leaf)) { throw "Embedded source missing: $($item.Path)" }
    $got = Get-SHA256 $item.Path
    if ($got -ne $item.Hash) { throw "Embedded source hash mismatch: $($item.Path) got=$got expected=$($item.Hash)" }
}

$OutDir = Join-Path $Workspace "AUTOGREY_V2_P11A2_FINAL_TARGET_FREE_PRODUCTION_R3"
if (Test-Path -LiteralPath $OutDir) {
    Write-Host "R3_RESUME_OUTDIR=$OutDir"
} else {
    Write-Host "R3_NEW_OUTDIR=$OutDir"
}

Write-Host "===== P11-A2 FINAL R3 RESOLVED INPUTS ====="
Write-Host "INDEX=$Index"
Write-Host "BINARY=$Binary"
Write-Host "P10_FINAL=$P10Final"
Write-Host "P1_SEAL=$P1Seal"
Write-Host "P5_SCHEMA=$P5Schema"
Write-Host "P5_MATRIX=$P5Matrix"
Write-Host "P6_LABELS=$P6Labels"
Write-Host "P7_SELECTOR=$P7Selector"
Write-Host "P7_GLOBAL=$P7Global"
Write-Host "P3_HARNESS=$P3Harness"
Write-Host "P3_WORKER=$P3Worker"
Write-Host "C4_FREEZE=$C4Freeze"
Write-Host "R1_EVIDENCE=$R1Evidence"
Write-Host "R2_EVIDENCE=$R2Evidence"
Write-Host "OUTDIR=$OutDir"
Write-Host "R3_REPAIR=SELECTOR_INPUT_NUMERIC_REPRESENTABILITY_ONLY"
Write-Host "R3_REUSE=PRESERVED_R2_48_COMMITTED_CHECKPOINT_CHUNKS"
Write-Host "R3_RAW_FEATURE_MATRIX_CHANGED=FALSE"
Write-Host "SCIENTIFIC_LOCK_CHANGED=FALSE"
Write-Host "REALBENCH3_TARGET_VALUES_OPENED=FALSE"
Write-Host "P11_B=LOCKED"

$py = $WslPython
$cmd = @(
    "export R_LIBS_USER=`"`$HOME/autogrey_v2_p3_r5_rlib`";",
    "export R_LIBS_SITE=`"`$HOME/autogrey_v2_p3_r5_empty_site`";",
    "export R_LD_LIBRARY_PATH=`"`$HOME/autogrey_v2_p3_r5_openblas_shim:/opt/autogrey-openblas-0.3.30-lp64-skylakex/lib:/usr/lib/R/lib`";",
    "export LD_LIBRARY_PATH=`"`$HOME/autogrey_v2_p3_r5_openblas_shim:/opt/autogrey-openblas-0.3.30-lp64-skylakex/lib`";",
    "export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1 TZ=UTC LANG=C LC_ALL=C;",
    (BashQuote $py),
    (BashQuote (To-WslPath $Harness)),
    "--lock", (BashQuote (To-WslPath $ScientificLock)),
    "--r3-repair-lock", (BashQuote (To-WslPath $R3RepairLock)),
    "--r1-evidence", (BashQuote (To-WslPath $R1Evidence)),
    "--r2-evidence", (BashQuote (To-WslPath $R2Evidence)),
    "--index", (BashQuote (To-WslPath $Index)),
    "--binary", (BashQuote (To-WslPath $Binary)),
    "--p10-final", (BashQuote (To-WslPath $P10Final)),
    "--p1-seal", (BashQuote (To-WslPath $P1Seal)),
    "--p5-schema", (BashQuote (To-WslPath $P5Schema)),
    "--p5-matrix", (BashQuote (To-WslPath $P5Matrix)),
    "--p6b-labels", (BashQuote (To-WslPath $P6Labels)),
    "--p7b-selector", (BashQuote (To-WslPath $P7Selector)),
    "--p7b-global", (BashQuote (To-WslPath $P7Global)),
    "--p3-harness", (BashQuote (To-WslPath $P3Harness)),
    "--p3-worker", (BashQuote (To-WslPath $P3Worker)),
    "--c4-freeze", (BashQuote (To-WslPath $C4Freeze)),
    "--engine", (BashQuote (To-WslPath $Engine)),
    "--sg11", (BashQuote (To-WslPath $SG11)),
    "--sg12", (BashQuote (To-WslPath $SG12)),
    "--sg13", (BashQuote (To-WslPath $SG13)),
    "--features", (BashQuote (To-WslPath $Features)),
    "--r-preflight", (BashQuote (To-WslPath $RPreflight)),
    "--newgroup-worker", (BashQuote (To-WslPath $NewWorker)),
    "--outdir", (BashQuote (To-WslPath $OutDir))
) -join " "

Write-Host "===== RUNNING P11-A2 FINAL TARGET-FREE PRODUCTION R3 ====="
wsl.exe bash -lc $cmd
$Code = $LASTEXITCODE
Write-Host "P11A2_FINAL_R3_EXIT_CODE=$Code"
Write-Host "REALBENCH3_TARGET_VALUES_OPENED=FALSE"
Write-Host "P11_B=LOCKED"
if ($Code -ne 0) { exit $Code }
