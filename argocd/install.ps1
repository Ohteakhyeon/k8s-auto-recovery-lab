# EKS Auto Recovery Lab - Argo CD Installation
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot

# Namespace 생성 (이미 있으면 유지)
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { throw "Namespace setup failed" }

# Argo CD v3.5.6 설치
kubectl apply -n argocd `
  --server-side `
  --force-conflicts `
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.6/manifests/install.yaml

if ($LASTEXITCODE -ne 0) { throw "Argo CD installation failed" }

# Controller 준비
kubectl rollout status deployment/argocd-server -n argocd --timeout=600s
if ($LASTEXITCODE -ne 0) { throw "Argo CD Server not ready" }

kubectl rollout status deployment/argocd-repo-server -n argocd --timeout=600s
if ($LASTEXITCODE -ne 0) { throw "Argo CD Repo Server not ready" }

kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=600s
if ($LASTEXITCODE -ne 0) { throw "Argo CD Controller not ready" }

# Online Boutique Application 등록
kubectl apply -f "$ProjectRoot\argocd\online-boutique-eks.yaml"
if ($LASTEXITCODE -ne 0) { throw "Application registration failed" }

Write-Host "Argo CD installation completed."

kubectl get applications -n argocd