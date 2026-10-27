
# Pod Failure Recovery Measurement v3
# HTTP monitoring runs independently using Start-Job.

$Namespace = "online-boutique"
$App = "productcatalogservice"
$Url = "http://localhost:8080/product/OLJCESPC7Z"
$Duration = 55

$ResultDir = Join-Path $PSScriptRoot "results"
New-Item -ItemType Directory -Force $ResultDir | Out-Null

$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$HttpCsv = Join-Path $ResultDir "pod-v3-http-$RunId.csv"
$KubeCsv = Join-Path $ResultDir "pod-v3-kube-$RunId.csv"
$SummaryCsv = Join-Path $ResultDir "pod-v3-summary-$RunId.csv"
$ReadyFile = Join-Path $ResultDir "pod-v3-ready-$RunId.tmp"

# Confirm exactly one healthy Pod before fault injection.
$Before = kubectl get pods -n $Namespace -l "app=$App" -o json |
    ConvertFrom-Json

if ($LASTEXITCODE -ne 0 -or @($Before.items).Count -ne 1) {
    throw "Expected exactly one Pod."
}

$OldPod = $Before.items[0].metadata.name

$OldReady = @($Before.items[0].status.conditions |
    Where-Object {
        $_.type -eq "Ready" -and $_.status -eq "True"
    })

if ($OldReady.Count -ne 1) {
    throw "Existing Pod is not Ready."
}

$BodyCheck = Join-Path $ResultDir "baseline-$RunId.tmp"

$Code = curl.exe -s --max-time 5 -o $BodyCheck `
    -w "%{http_code}" $Url

$Content = ""
if (Test-Path $BodyCheck) {
    $Content = Get-Content $BodyCheck -Raw
    Remove-Item $BodyCheck -Force
}

if ($Code -ne "200" -or $Content -notlike "*Sunglasses*") {
    throw "Baseline HTTP check failed. Pod not deleted."
}

Write-Host "=== Pod Recovery v3 ==="
Write-Host "Old Pod: $OldPod"
Write-Host "Baseline: Healthy"

# Independent HTTP monitoring process.
$HttpJob = Start-Job -ArgumentList @(
    $Url, $HttpCsv, $ReadyFile, $Duration, $RunId
) -ScriptBlock {
    param($Url, $Csv, $ReadyFile, $Duration, $RunId)

    $Records = [System.Collections.Generic.List[object]]::new()
    $BodyFile = Join-Path ([System.IO.Path]::GetDirectoryName($Csv)) `
        "http-body-$RunId.tmp"

    try {
        $Start = Get-Date
        Set-Content -Path $ReadyFile -Value "ready"

        while (((Get-Date) - $Start).TotalSeconds -lt $Duration) {
            $RequestStart = (Get-Date).ToUniversalTime()

            Remove-Item $BodyFile -ErrorAction SilentlyContinue

            $Status = curl.exe -s --max-time 2 `
                -o $BodyFile -w "%{http_code}" `
                "$Url`?probe=$([guid]::NewGuid().ToString('N'))"

            $RequestEnd = (Get-Date).ToUniversalTime()

            $Body = ""
            if (Test-Path $BodyFile) {
                $Body = Get-Content $BodyFile -Raw `
                    -ErrorAction SilentlyContinue
            }

            $Healthy = (
                $Status -eq "200" -and
                $Body -like "*Sunglasses*"
            )

            $Records.Add([PSCustomObject]@{
                RequestStartUtc = $RequestStart.ToString("o")
                RequestEndUtc = $RequestEnd.ToString("o")
                HttpStatus = $Status
                Healthy = $Healthy
            })

            Start-Sleep -Milliseconds 500
        }
    }
    finally {
        $Records | Export-Csv $Csv `
            -NoTypeInformation -Encoding UTF8

        Remove-Item $BodyFile -ErrorAction SilentlyContinue
        Remove-Item $ReadyFile -ErrorAction SilentlyContinue
    }
}

try {
    # Wait until the HTTP observer is running.
    $WaitStart = Get-Date

    while (-not (Test-Path $ReadyFile)) {
        if ($HttpJob.State -in @("Failed", "Stopped", "Completed")) {
            throw "HTTP monitoring job stopped unexpectedly."
        }

        if (((Get-Date) - $WaitStart).TotalSeconds -gt 15) {
            throw "HTTP monitoring job did not start."
        }

        Start-Sleep -Milliseconds 200
    }

    # Allow the HTTP observer to gather baseline requests.
    Start-Sleep -Seconds 2

    $FaultStartUtc = (Get-Date).ToUniversalTime()

    Write-Host "Fault start UTC: $($FaultStartUtc.ToString('o'))"

    kubectl delete pod $OldPod -n $Namespace --wait=false

    if ($LASTEXITCODE -ne 0) {
        throw "Pod deletion failed."
    }

    $NewPod = ""
    $PodReadyUtc = $null
    $EndpointReadyUtc = $null

    $KubeRecords = [System.Collections.Generic.List[object]]::new()

    # Poll Kubernetes independently of the HTTP job.
    while ($HttpJob.State -eq "Running") {
        $PodsJson = kubectl get pods -n $Namespace `
            -l "app=$App" -o json 2>$null

        if ($LASTEXITCODE -eq 0 -and $PodsJson) {
            $Pods = $PodsJson | ConvertFrom-Json

            foreach ($Pod in $Pods.items) {
                if ($Pod.metadata.name -eq $OldPod) {
                    continue
                }

                $NewPod = $Pod.metadata.name

                $ReadyCondition = @($Pod.status.conditions |
                    Where-Object {
                        $_.type -eq "Ready" -and
                        $_.status -eq "True"
                    })

                if ($ReadyCondition.Count -gt 0 -and
                    $null -eq $PodReadyUtc) {

                    $PodReadyUtc = (Get-Date).ToUniversalTime()
                    Write-Host "POD READY OBSERVED"
                }
            }
        }

        $SlicesJson = kubectl get endpointslices `
            -n $Namespace `
            -l "kubernetes.io/service-name=$App" `
            -o json 2>$null

        if ($LASTEXITCODE -eq 0 -and $SlicesJson) {
            $Slices = $SlicesJson | ConvertFrom-Json

            foreach ($Slice in $Slices.items) {
                foreach ($Endpoint in $Slice.endpoints) {
                    if (
                        $NewPod -and
                        $Endpoint.targetRef.name -eq $NewPod -and
                        $Endpoint.conditions.ready -eq $true -and
                        $null -eq $EndpointReadyUtc
                    ) {
                        $EndpointReadyUtc = (Get-Date).ToUniversalTime()
                        Write-Host "ENDPOINT READY OBSERVED"
                    }
                }
            }
        }

        $KubeRecords.Add([PSCustomObject]@{
            ObservedUtc = (Get-Date).ToUniversalTime().ToString("o")
            NewPod = $NewPod
            PodReadyObserved = ($null -ne $PodReadyUtc)
            EndpointReadyObserved = ($null -ne $EndpointReadyUtc)
        })

        Start-Sleep -Milliseconds 300
    }

    Wait-Job $HttpJob | Out-Null
    Receive-Job $HttpJob

    $KubeRecords | Export-Csv $KubeCsv `
        -NoTypeInformation -Encoding UTF8

    $HttpRecords = @(Import-Csv $HttpCsv)

    # Only count requests started after fault injection.
    $AfterFault = @($HttpRecords | Where-Object {
        [datetime]$_.RequestStartUtc -ge $FaultStartUtc
    })

    $FirstFailure = $null
    $FirstSuccess = $null
    $StableSuccess = $null
    $Consecutive = 0

    foreach ($Record in $AfterFault) {
        $IsHealthy = $Record.Healthy -eq "True"

        if (-not $IsHealthy) {
            if ($null -eq $FirstFailure) {
                $FirstFailure = [datetime]$Record.RequestEndUtc
            }

            $Consecutive = 0
            $FirstSuccess = $null
        }
        elseif ($null -ne $FirstFailure) {
            if ($Consecutive -eq 0) {
                $FirstSuccess = [datetime]$Record.RequestEndUtc
            }

            $Consecutive++

            if ($Consecutive -ge 3) {
                $StableSuccess = [datetime]$Record.RequestEndUtc
                break
            }
        }
    }

    function SecondsFromFault($Timestamp) {
        if ($null -eq $Timestamp) { return $null }

        return [math]::Round(
            ($Timestamp.ToUniversalTime() - $FaultStartUtc).TotalSeconds,
            3
        )
    }

    $Summary = [PSCustomObject]@{
        RunId = $RunId
        FaultStartUtc = $FaultStartUtc.ToString("o")
        OldPod = $OldPod
        NewPod = $NewPod
        PodReadySec = SecondsFromFault $PodReadyUtc
        EndpointReadySec = SecondsFromFault $EndpointReadyUtc
        FirstFailureSec = SecondsFromFault $FirstFailure
        FirstHttpSuccessSec = SecondsFromFault $FirstSuccess
        StableHttpSec = SecondsFromFault $StableSuccess
        FailureObserved = ($null -ne $FirstFailure)
        RecoveryConfirmed = ($null -ne $StableSuccess)
    }

    $Summary | Export-Csv $SummaryCsv `
        -NoTypeInformation -Encoding UTF8

    Write-Host ""
    Write-Host "========== V3 RESULT =========="
    $Summary | Format-List

    Write-Host "HTTP CSV: $HttpCsv"
    Write-Host "Kubernetes CSV: $KubeCsv"
    Write-Host "Summary CSV: $SummaryCsv"
}
finally {
    if ($HttpJob.State -eq "Running") {
        Stop-Job $HttpJob
    }

    Receive-Job $HttpJob -ErrorAction SilentlyContinue | Out-Null
    Remove-Job $HttpJob -Force -ErrorAction SilentlyContinue
}
