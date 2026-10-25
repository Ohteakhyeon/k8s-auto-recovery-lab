# EKS Auto Recovery Lab - Monitoring Installation
$ErrorActionPreference = "Stop"

# 프로젝트 루트 경로
$ProjectRoot = Split-Path -Parent $PSScriptRoot

# Helm Repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
if ($LASTEXITCODE -ne 0) { throw "Helm repo add failed" }

helm repo update
if ($LASTEXITCODE -ne 0) { throw "Helm repo update failed" }

# Monitoring 설치 또는 업데이트
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack `
  --namespace monitoring `
  --create-namespace `
  --version 92.13.1 `
  -f "$ProjectRoot\monitoring\values.yaml" `
  -f "$ProjectRoot\monitoring\rules\pod-alerts.yaml" `
  --wait `
  --timeout 10m

if ($LASTEXITCODE -ne 0) { throw "Monitoring installation failed" }

Write-Host "Monitoring installation completed."

kubectl get pods -n monitoring