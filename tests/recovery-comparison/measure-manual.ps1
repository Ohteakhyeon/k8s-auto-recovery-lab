
$Namespace = "recovery-test"
$PodName = "productcatalog-manual"
$Manifest = Join-Path $PSScriptRoot "manual-pod.yaml"
$ResultDir = Join-Path $PSScriptRoot "..\results"

New-Item -ItemType Directory -Force $ResultDir | Out-Null

$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$CsvPath = Join-Path $ResultDir "manual-recovery-$RunId.csv"

$Before = kubectl get pod $PodName -n $Namespace -o json |
    ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    throw "Manual Pod not found."
}

$Ready = @($Before.status.conditions |
    Where-Object {
        $_.type -eq "Ready" -and $_.status -eq "True"
    })

if ($Ready.Count -ne 1) {
    throw "Manual Pod is not Ready."
}

$OldUid = $Before.metadata.uid

Write-Host ""
Write-Host "=== MANUAL RECOVERY TEST ==="
Write-Host "Old Pod UID: $OldUid"

$Start = Get-Date

kubectl delete pod $PodName -n $Namespace --wait=true

if ($LASTEXITCODE -ne 0) {
    throw "Pod deletion failed."
}

Write-Host ""
Write-Host "Pod deleted. Automatic recreation is disabled."
Write-Host "Check the failure, then press ENTER to recover."
Read-Host "Press ENTER to apply the Pod manifest"

$ActionStart = Get-Date

kubectl apply -f $Manifest

if ($LASTEXITCODE -ne 0) {
    throw "Manual recreation failed."
}

$Recovered = $false
$RecoveryTime = $null

$Deadline = (Get-Date).AddSeconds(120)

while ((Get-Date) -lt $Deadline) {

    $Json = kubectl get pod $PodName -n $Namespace `
        -o json 2>$null

    if ($LASTEXITCODE -eq 0 -and $Json) {

        $Pod = $Json | ConvertFrom-Json

        $IsNew = $Pod.metadata.uid -ne $OldUid

        $IsReady = @($Pod.status.conditions |
            Where-Object {
                $_.type -eq "Ready" -and
                $_.status -eq "True"
            }).Count -gt 0

        if ($IsNew -and $IsReady) {
            $RecoveryTime = Get-Date
            $Recovered = $true
            break
        }
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
    Mode = "Manual"
    StartTime = $Start.ToString("o")
    OperatorActionSec = [math]::Round(
        ($ActionStart - $Start).TotalSeconds, 3
    )
    TotalRecoverySec = $TotalSec
    RecoveryConfirmed = $Recovered
}

$Result | Export-Csv $CsvPath `
    -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "========== MANUAL RESULT =========="
$Result | Format-List
Write-Host "CSV: $CsvPath"
