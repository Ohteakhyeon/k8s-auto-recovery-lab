
$Namespace = "recovery-test"
$App = "productcatalog-auto"
$ResultDir = Join-Path $PSScriptRoot "..\results"

New-Item -ItemType Directory -Force $ResultDir | Out-Null

$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$CsvPath = Join-Path $ResultDir "auto-recovery-$RunId.csv"

# Check current Pod
$BeforeJson = kubectl get pods -n $Namespace -l "app=$App" -o json

if ($LASTEXITCODE -ne 0) {
    throw "Failed to read Pods."
}

$Before = $BeforeJson | ConvertFrom-Json

if (@($Before.items).Count -ne 1) {
    throw "Expected exactly one automatic recovery Pod."
}

$OldPod = $Before.items[0]
$OldName = $OldPod.metadata.name
$OldUid = $OldPod.metadata.uid

$Ready = @($OldPod.status.conditions | Where-Object {
    $_.type -eq "Ready" -and $_.status -eq "True"
})

if ($Ready.Count -ne 1) {
    throw "Existing Pod is not Ready."
}

Write-Host ""
Write-Host "=== AUTO RECOVERY TEST ==="
Write-Host "Old Pod: $OldName"

$Start = Get-Date

kubectl delete pod $OldName -n $Namespace --wait=false

if ($LASTEXITCODE -ne 0) {
    throw "Pod deletion failed."
}

$Recovered = $false
$RecoveryTime = $null
$NewPodName = ""
$Deadline = $Start.AddSeconds(120)

while ((Get-Date) -lt $Deadline) {

    $Json = kubectl get pods -n $Namespace `
        -l "app=$App" -o json 2>$null

    if ($LASTEXITCODE -eq 0 -and $Json) {

        $Pods = $Json | ConvertFrom-Json

        foreach ($Pod in $Pods.items) {

            if ($Pod.metadata.uid -eq $OldUid) {
                continue
            }

            $NewPodName = $Pod.metadata.name

            $IsReady = @($Pod.status.conditions | Where-Object {
                $_.type -eq "Ready" -and $_.status -eq "True"
            }).Count -gt 0

            if ($IsReady) {
                $RecoveryTime = Get-Date
                $Recovered = $true
                break
            }
        }
    }

    if ($Recovered) {
        break
    }

    Start-Sleep -Milliseconds 300
}

$TotalSec = $null

if ($Recovered) {
    $TotalSec = [math]::Round(
        ($RecoveryTime - $Start).TotalSeconds, 3
    )
}

$Result = [PSCustomObject]@{
    RunId = $RunId
    Mode = "Auto"
    StartTime = $Start.ToString("o")
    OldPod = $OldName
    NewPod = $NewPodName
    TotalRecoverySec = $TotalSec
    RecoveryConfirmed = $Recovered
}

$Result | Export-Csv $CsvPath `
    -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "========== AUTO RESULT =========="
$Result | Format-List
Write-Host "CSV: $CsvPath"
