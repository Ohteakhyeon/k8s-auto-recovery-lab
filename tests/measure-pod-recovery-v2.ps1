
# Pod Failure Recovery Measurement v2
# Pod Ready / Endpoint Ready / HTTP Recovery

$Namespace = "online-boutique"
$App = "productcatalogservice"
$Url = "http://localhost:8080/product/OLJCESPC7Z"
$MaxSeconds = 100

$ResultDir = Join-Path $PSScriptRoot "results"
New-Item -ItemType Directory -Force $ResultDir | Out-Null

$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$CsvPath = Join-Path $ResultDir "pod-v2-$RunId.csv"
$SummaryPath = Join-Path $ResultDir "pod-v2-summary-$RunId.csv"
$BodyPath = Join-Path $ResultDir "pod-v2-response-$RunId.tmp"

# Get current Pod before fault injection
$Before = kubectl get pods -n $Namespace -l "app=$App" -o json |
    ConvertFrom-Json

$OldPods = @($Before.items)

if ($OldPods.Count -ne 1) {
    throw "Expected exactly one Pod before test."
}

$OldPodName = $OldPods[0].metadata.name
$OldReady = @($OldPods[0].status.conditions |
    Where-Object { $_.type -eq "Ready" -and $_.status -eq "True" })

if ($OldReady.Count -ne 1) {
    throw "Existing Pod is not Ready."
}

# Check frontend before injecting a fault
$BaselineCode = curl.exe -s --max-time 5 `
    -o $BodyPath -w "%{http_code}" $Url

$BaselineBody = ""
if (Test-Path $BodyPath) {
    $BaselineBody = Get-Content $BodyPath -Raw
}

if ($BaselineCode -ne "200" -or
    $BaselineBody -notlike "*Sunglasses*") {
    throw "Baseline HTTP check failed. No Pod was deleted."
}

$Records = [System.Collections.Generic.List[object]]::new()

$PodReadySec = $null
$EndpointReadySec = $null
$FirstHttpSuccessSec = $null
$StableHttpSec = $null

$FailureObserved = $false
$SuccessCount = 0
$NewPodName = ""

Write-Host "=== Pod Recovery v2 ==="
Write-Host "Old Pod: $OldPodName"
Write-Host "Baseline: Healthy"
Write-Host ""

# Shared measurement clock
$FaultStartTime = Get-Date
$Clock = [System.Diagnostics.Stopwatch]::StartNew()

kubectl delete pod $OldPodName -n $Namespace --wait=false

if ($LASTEXITCODE -ne 0) {
    throw "Pod deletion failed."
}

while ($Clock.Elapsed.TotalSeconds -lt $MaxSeconds) {

    # 1. Observe new Pod readiness
    $PodJson = kubectl get pods -n $Namespace `
        -l "app=$App" -o json 2>$null

    if ($LASTEXITCODE -eq 0 -and $PodJson) {
        $Pods = $PodJson | ConvertFrom-Json

        foreach ($Pod in $Pods.items) {
            if ($Pod.metadata.name -eq $OldPodName) {
                continue
            }

            $NewPodName = $Pod.metadata.name

            $IsReady = @($Pod.status.conditions |
                Where-Object {
                    $_.type -eq "Ready" -and
                    $_.status -eq "True"
                }).Count -gt 0

            if ($IsReady -and $null -eq $PodReadySec) {
                $PodReadySec = [math]::Round(
                    $Clock.Elapsed.TotalSeconds, 3
                )
                Write-Host "POD READY: $PodReadySec sec"
            }
        }
    }

    # 2. Observe new Endpoint readiness
    $EndpointJson = kubectl get endpointslices `
        -n $Namespace `
        -l "kubernetes.io/service-name=$App" `
        -o json 2>$null

    if ($LASTEXITCODE -eq 0 -and $EndpointJson) {
        $Slices = $EndpointJson | ConvertFrom-Json

        foreach ($Slice in $Slices.items) {
            foreach ($Endpoint in $Slice.endpoints) {

                if ($NewPodName -and
                    $Endpoint.targetRef.name -eq $NewPodName -and
                    $Endpoint.conditions.ready -eq $true -and
                    $null -eq $EndpointReadySec) {

                    $EndpointReadySec = [math]::Round(
                        $Clock.Elapsed.TotalSeconds, 3
                    )

                    Write-Host "ENDPOINT READY: $EndpointReadySec sec"
                }
            }
        }
    }

    # 3. Observe actual HTTP response
    Remove-Item $BodyPath -ErrorAction SilentlyContinue

    $HttpCode = curl.exe -s --max-time 3 `
        -o $BodyPath -w "%{http_code}" `
        "$Url`?probe=$([guid]::NewGuid().ToString('N'))"

    $Elapsed = [math]::Round(
        $Clock.Elapsed.TotalSeconds, 3
    )

    $Body = ""
    if (Test-Path $BodyPath) {
        $Body = Get-Content $BodyPath -Raw -ErrorAction SilentlyContinue
    }

    $Healthy = ($HttpCode -eq "200" -and
                $Body -like "*Sunglasses*")

    if ($Healthy) {
        $Result = "SUCCESS"
        $SuccessCount++

        if ($FailureObserved -and
            $null -eq $FirstHttpSuccessSec) {
            $FirstHttpSuccessSec = $Elapsed
        }
    }
    else {
        $Result = "FAILURE"
        $FailureObserved = $true
        $SuccessCount = 0
        $FirstHttpSuccessSec = $null
    }

    $Records.Add([PSCustomObject]@{
        RunId = $RunId
        Timestamp = (Get-Date).ToString("o")
        ElapsedSec = $Elapsed
        PodReadySec = $PodReadySec
        EndpointReadySec = $EndpointReadySec
        HttpStatus = $HttpCode
        HttpResult = $Result
    })

    Write-Host "$Elapsed sec | HTTP $HttpCode | $Result"

    if ($FailureObserved -and $SuccessCount -ge 3) {
        $StableHttpSec = $Elapsed
        break
    }

    Start-Sleep -Milliseconds 250
}

$Clock.Stop()

# Export detailed HTTP observations
$Records | Export-Csv $CsvPath `
    -NoTypeInformation -Encoding UTF8

# Export one-row summary
$Summary = [PSCustomObject]@{
    RunId = $RunId
    FaultStartTime = $FaultStartTime.ToString("o")
    OldPod = $OldPodName
    NewPod = $NewPodName
    PodReadySec = $PodReadySec
    EndpointReadySec = $EndpointReadySec
    FirstHttpSuccessSec = $FirstHttpSuccessSec
    StableHttpSec = $StableHttpSec
    FailureObserved = $FailureObserved
    RecoveryConfirmed = ($null -ne $StableHttpSec)
}

$Summary | Export-Csv $SummaryPath `
    -NoTypeInformation -Encoding UTF8

Remove-Item $BodyPath -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "========== RESULT =========="
$Summary | Format-List
Write-Host "Detail CSV: $CsvPath"
Write-Host "Summary CSV: $SummaryPath"