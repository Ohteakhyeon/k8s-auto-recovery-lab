
# Pod Failure - Automatic Recovery Measurement

$Namespace = "online-boutique"
$App = "productcatalogservice"
$Url = "http://localhost:8080/product/OLJCESPC7Z"
$MaxSeconds = 90

$ResultDir = Join-Path $PSScriptRoot "results"
New-Item -ItemType Directory -Force $ResultDir | Out-Null

$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$CsvPath = Join-Path $ResultDir "pod-auto-$RunId.csv"
$BodyPath = Join-Path $ResultDir "response-$RunId.tmp"

$Records = @()
$ConsecutiveSuccesses = 0
$FailureObserved = $false
$Recovered = $false

# 정상 상태 확인
$ready = kubectl get deployment $App -n $Namespace `
  -o jsonpath='{.status.readyReplicas}'

if ($LASTEXITCODE -ne 0 -or $ready -ne "1") {
    throw "Deployment is not ready."
}

Write-Host "Starting Pod Failure test..."

# 장애 주입 시각
$Start = Get-Date

kubectl delete pod -n $Namespace -l "app=$App" --wait=false

if ($LASTEXITCODE -ne 0) {
    throw "Pod deletion failed."
}

# HTTP 응답 관찰
while (((Get-Date) - $Start).TotalSeconds -lt $MaxSeconds) {

    $Status = curl.exe --silent --max-time 3 `
      --output $BodyPath `
      --write-out "%{http_code}" `
      "$Url`?probe=$(Get-Date -Format 'HHmmssfff')"

    $RequestEnd = Get-Date
    $Elapsed = [math]::Round(
        ($RequestEnd - $Start).TotalSeconds, 3
    )

    $Body = ""
    if (Test-Path $BodyPath) {
        $Body = Get-Content $BodyPath -Raw -ErrorAction SilentlyContinue
    }

    $IsHealthy = ($Status -eq "200" -and $Body -like "*Sunglasses*")

    if ($IsHealthy) {
        $ConsecutiveSuccesses++
        $Result = "SUCCESS"
    }
    else {
        $FailureObserved = $true
        $ConsecutiveSuccesses = 0
        $Result = "FAILURE"
    }

    $Records += [PSCustomObject]@{
        RunId      = $RunId
        Timestamp  = $RequestEnd.ToString("yyyy-MM-dd HH:mm:ss.fff")
        ElapsedSec = $Elapsed
        HTTPStatus = $Status
        Result     = $Result
    }

    Write-Host "$Elapsed sec | HTTP $Status | $Result"

    if ($ConsecutiveSuccesses -ge 3 -and $FailureObserved) {
        $Recovered = $true
        break
    }

    Start-Sleep -Milliseconds 500
}

$Records | Export-Csv $CsvPath -NoTypeInformation -Encoding UTF8

if (Test-Path $BodyPath) {
    Remove-Item $BodyPath
}

Write-Host ""
Write-Host "===== Test Result ====="
Write-Host "Failure observed: $FailureObserved"
Write-Host "Recovery confirmed: $Recovered"
Write-Host "CSV: $CsvPath"

if ($Recovered) {
    $RecoverySec = [math]::Round(
        ((Get-Date) - $Start).TotalSeconds, 3
    )
    Write-Host "Recovery confirmation time: $RecoverySec sec"
}
else {
    Write-Host "Recovery time not established within test window."
}
