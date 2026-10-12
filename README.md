# Kubernetes Auto-Recovery Project

## 프로젝트 주제

**장애를 발견하는 인프라에서, 스스로 복구하는 인프라로**

Kubernetes 기반 장애 탐지 및 자동 복구 체계를 구축하고, 수동 장애 대응 방식과 자동 복구 방식의 차이를 정량적으로 비교하는 프로젝트입니다.

## 프로젝트 목표

오픈소스 애플리케이션을 Docker 기반으로 컨테이너화하고 Kubernetes 환경에 배포합니다.

Terraform을 활용하여 인프라를 코드로 관리하고, GitHub Actions와 Argo CD를 통해 CI/CD 파이프라인을 구성합니다.

Prometheus와 Grafana를 활용하여 서비스와 Kubernetes 상태를 모니터링하고, 실제 장애 상황을 재현하여 자동 복구 기능이 MTTD, MTTR, Error Rate, P95 Latency 등에 어떤 영향을 주는지 측정합니다.

## 주요 기술

- Docker
- Kubernetes
- Terraform
- GitHub Actions
- Argo CD
- Prometheus
- Grafana
- k6

## 주요 검증 항목

- Pod 장애 발생 시 Kubernetes Self-Healing 검증
- CPU 및 Memory 자원 고갈 상황 대응
- 잘못된 버전 배포 및 Rollback 검증
- 장애 탐지 시간(MTTD)
- 장애 복구 시간(MTTR)
- P95 Latency
- Error Rate
- Service Availability

## 프로젝트 핵심 질문

> 자동화된 장애 탐지 및 복구 체계는 수동 대응 방식보다 서비스 장애 시간을 얼마나 줄일 수 있는가?

## 장애 시나리오

### Scenario 1 — Pod Failure
Pod를 강제로 종료하여 Kubernetes Self-Healing 동작을 검증합니다.

### Scenario 2 — Resource Exhaustion
CPU 및 Memory 부하를 발생시켜 Resource Limit, HPA 및 서비스 안정성을 검증합니다.

### Scenario 3 — Deployment Failure
오류가 포함된 버전을 배포하고 장애 탐지 및 Rollback 과정을 검증합니다.

## 측정 지표

| Metric | Description |
|---|---|
| MTTD | 장애 발생부터 탐지까지 걸린 시간 |
| MTTR | 장애 발생부터 서비스 정상화까지 걸린 시간 |
| P95 Latency | 전체 요청 중 95%가 완료되는 응답시간 |
| Error Rate | 실패한 요청 비율 |
| Recovery Time | Pod 또는 서비스 복구 시간 |
| Availability | 테스트 시간 동안 서비스 가용률 |

## Repository Structure

```text
.
├── app/
├── docker/
├── terraform/
├── kubernetes/
├── argocd/
├── monitoring/
│   ├── prometheus/
│   └── grafana/
├── k6/
├── docs/
└── .github/
    └── workflows/
```

## Project Status

Planning
