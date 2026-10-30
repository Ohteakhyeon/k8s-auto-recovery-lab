| 버전 | 변경 내용 | 상태 |
| --- | --- | --- |
| v0.1 | Docker, Kubernetes, Terraform, CI/CD, Monitoring 전체 구조 초안 | 완료 |
| v0.2 | AWS EKS 인프라 구성 및 로컬 Kubernetes 검증 범위 반영 | 완료 |
| v0.3 | GitHub Actions, Argo CD, Prometheus 및 Grafana 연동 구조 반영 | 완료 |
| v1.0 | 실제 구현 아키텍처, 장애 복구 흐름, 운영 결과 및 한계 반영 | 최종 |

## 1. 문서 목적

오픈소스 애플리케이션 Google Online Boutique를 기반으로 구축할 Kubernetes 운영 환경의 전체 구조를 정의한다.

애플리케이션 소스 관리부터 Docker Image Build, Kubernetes 배포, GitOps 기반 CD, 인프라 IaC, 모니터링, 부하 테스트, 장애 탐지 및 자동 복구까지의 전체 흐름을 하나의 아키텍처로 구성하는 것을 목표로 함.

---

## 2. 아키텍처 설계 목표

| 설계 목표 | 적용 기술 및 검증 내용 |
| --- | --- |
| 컨테이너 기반 실행 환경 | Docker 및 Amazon ECR |
| Kubernetes 애플리케이션 운영 | AWS EKS, Deployment, Service |
| 자동 복구 | ReplicaSet, Readiness/Liveness Probe |
| CPU 기반 자동 확장 | Metrics Server, HPA |
| 인프라 코드 관리 | Terraform |
| 이미지 빌드 자동화 | GitHub Actions |
| GitOps 배포 관리 | Argo CD |
| 운영 지표 수집 | Prometheus |
| 상태 시각화 | Grafana |
| 장애 알림 | PrometheusRule, Alertmanager |
| 부하 및 장애 검증 | k6, kubectl, PowerShell |
| 복구 효과 분석 | Pod Ready 시간, P95, RPS, 오류율 |

---

## 3. 전체 시스템 구성

### 3.1 최종 논리 아키텍처

!전체아키텍처.png

GitHub Actions는 애플리케이션 이미지를 빌드하고 Amazon ECR에 업로드하는 CI 영역을 담당한다.

Argo CD는 Git 저장소에 선언된 Kubernetes Manifest를 기준으로 클러스터의 애플리케이션 상태를 관리한다.

Kubernetes는 Deployment, ReplicaSet, Probe, HPA 등의 기능을 통해 애플리케이션의 상태 유지와 리소스 조정을 수행한다.

Prometheus, Grafana, Alertmanager는 Kubernetes 리소스의 상태를 수집·시각화하고 장애 알림을 제공한다.

Terraform은 애플리케이션 배포와 별도로 AWS 기반 인프라 리소스를 관리한다.

---

### 3.2 AWS 인프라 아키텍처

!AWS아키텍처.png

---

### 3.3 실제 인프라 구성

| 항목 | 실제 구성 |
| --- | --- |
| Cloud Provider | AWS |
| Region | ap-northeast-2 |
| Kubernetes | Amazon EKS 1.35 |
| VPC CIDR | 10.0.0.0/16 |
| Subnet A | 10.0.1.0/24 |
| Subnet B | 10.0.2.0/24 |
| Worker Node | EC2 t3.large × 2 |
| Node Group | EKS Managed Node Group |
| Container Registry | Amazon ECR |
| Network Plugin | AWS VPC CNI |
| Kubernetes Metrics | Metrics Server EKS Add-on |
| IaC | Terraform |

---

### 3.4 Kubernetes Namespace 구성

| Namespace | 역할 |
| --- | --- |
| `online-boutique` | 실제 마이크로서비스 애플리케이션 |
| `recovery-test` | Pod 복구, HPA, 배포 실패 및 알림 실험 |
| `monitoring` | Prometheus, Grafana, Alertmanager |
| `argocd` | GitOps 기반 배포 관리 |
| `kube-system` | Kubernetes 시스템 구성요소 |

장애 테스트는 별도의 `recovery-test` Namespace에서 수행하여 기존 Online Boutique에 대한 영향을 최소화 함.

---

### 3.5 구현 및 검증 결과

- Terraform 기반 AWS EKS 인프라 구축
- Worker Node 2개 Ready 확인
- Online Boutique 11개 Deployment 정상 실행
- GitHub Actions 및 ECR 이미지 빌드·배포 흐름 구성
- Argo CD Application `Synced / Healthy` 확인
- Metrics Server 정상 동작
- HPA 자동 확장·축소 확인
- Prometheus 장애 Firing 확인
- Terraform 최종 Plan `No changes` 확인

---

## 4. 주요 구성요소

| 구성요소 | 역할 | 최종 상태 |
| --- | --- | --- |
| Google Online Boutique | 마이크로서비스 실험 애플리케이션 | EKS 배포 완료 |
| Docker | 애플리케이션 이미지 빌드 | 적용 완료 |
| GitHub | 소스 코드 및 Manifest 관리 | 적용 완료 |
| GitHub Actions | CI 자동화 | 구성 완료 |
| Amazon ECR | 컨테이너 이미지 저장 | 사용 완료 |
| Argo CD | GitOps 기반 CD | 적용 완료 |
| Kubernetes / EKS | 애플리케이션 운영 및 자동 복구 | 검증 완료 |
| Terraform | AWS 인프라 생성 및 상태 관리 | 검증 완료 |
| Metrics Server | CPU/Memory Metrics API 제공 | 설치 완료 |
| HPA | CPU 기반 Replica 자동 조정 | 검증 완료 |
| Prometheus | 메트릭 수집 및 알림 평가 | 검증 완료 |
| Grafana | 운영 상태 시각화 | 구성 완료 |
| Alertmanager | 장애 알림 수신 및 관리 | 수신 화면 확인 |
| k6 | gRPC 부하 테스트 | 검증 완료 |

---

## 5. 애플리케이션 배포 흐름

### 5.1 CI 영역 — GitHub Actions

```
Source Code 변경
        │
        ▼
GitHub Push
        │
        ▼
GitHub Actions
        │
        ├── Build / Test
        │
        ▼
Docker Image Build
        │
        ▼
Amazon ECR Push
        │
        ▼
이미지 버전 확보
```

GitHub Actions는 애플리케이션 소스 코드를 기반으로 Docker 이미지를 빌드하고 ECR에 저장하는 역할을 담당한다.

### 5.2 CD 영역 — Argo CD

```
Git Repository
    │
    ▼
Kubernetes Manifest
    │
    ▼
Argo CD Application
    │
    ▼
Git 상태와 Cluster 상태 비교
    │
    ▼
Kubernetes Deployment
    │
    ▼
Rolling Update
    │
    ▼
Pod Ready 확인
```

Argo CD는 `kubernetes/overlays/eks`의 Manifest를 기준으로 Online Boutique 애플리케이션을 관리하도록 구성했다.

자동 동기화 및 Self-Heal 설정을 통해 Git에 선언된 상태와 실제 Kubernetes 리소스 상태의 차이를 조정할 수 있도록 했다.

---

## 6. Kubernetes 운영 흐름

### 6.1 정상 운영

```
Deployment
    │
    ▼
ReplicaSet
    │
    ▼
Pod
    │
    ▼
Readiness Probe
    │
    ▼
Service Endpoint
    │
    ▼
Application Traffic
```

Deployment는 원하는 Replica 수와 Pod 구성을 선언하고, ReplicaSet은 해당 Pod 수를 유지한다.

Readiness Probe를 통과한 Pod는 Service의 요청 대상에 포함될 수 있다.

### 6.2 Pod 장애 및 자동 복구

```
Pod 삭제
    │
    ▼
실제 Replica 수 감소
    │
    ▼
ReplicaSet Controller 감지
    │
    ▼
새 Pod 생성
    │
    ▼
컨테이너 실행
    │
    ▼
Readiness Probe 성공
    │
    ▼
Pod Ready
```

**실험 결과**

| 항목 | 평균 Pod Ready 도달 시간 |
| --- | --- |
| 수동 복구 | 19.101초 |
| ReplicaSet 자동 복구 | 3.666초 |

자동 복구의 평균 Ready 도달 시간이 수동 복구보다 약 80.8% 짧게 측정됐다.

단, 수동과 자동의 실행·측정 조건이 완전히 동일하지 않아 서비스 전체 MTTR 개선율로 해석하지 않는다.

### 6.3 HPA 자동 확장

```
k6 부하 발생
      │
      ▼
Pod CPU 사용률 증가
      │
      ▼
Metrics Server
      │
      ▼
HPA Controller
      │
      ▼
Desired Replica 계산
      │
      ▼
Deployment Replica 증가
      │
      ▼
새 Pod 생성
```

실제 실험에서는 CPU 목표 60%, 최소 1개, 최대 3개로 구성했다.

CPU 사용률 상승 시 Replica가 1개에서 2개로 확장됐고, 부하 종료 후 1개로 축소되는 동작을 확인했다.

---

## 7. 장애 탐지 및 복구 흐름

장애 감지와 Kubernetes 자동 복구는 서로 독립적으로 동작하므로, 이를 분리하여 설계했다.

### 7.1 장애 감지

```
Pod / Deployment 상태 변화
            │
            ▼
      kube-state-metrics
            │
            ▼
        Prometheus
            │
      ┌─────┴─────┐
      │           │
      ▼           ▼
    Grafana    PrometheusRule
                  │
                  ▼
             Alertmanager
```

Prometheus는 Kubernetes 상태를 메트릭으로 수집하고 알림 규칙을 평가한다.

Grafana는 수집된 메트릭을 시각화하는 역할을 담당한다.

Alertmanager는 Prometheus가 발생시킨 알림을 수신하고 관리한다.

### 7.2 자동 복구

```
Pod 장애
    │
    ▼
Kubernetes Controller / Probe
    │
    ▼
Pod 재생성 또는 컨테이너 재시작
    │
    ▼
Readiness 성공
    │
    ▼
정상 상태 복귀
```

---

## 8. 장애 시나리오와 아키텍처 연결

| 장애 시나리오 | 실제 대상 | 사용 구성요소 | 검증 결과 |
| --- | --- | --- | --- |
| Pod Failure | ProductCatalog 실험 Pod | Deployment, ReplicaSet | 자동 재생성 |
| gRPC 재연결 지연 | Frontend | gRPC, HTTP 응답 측정 | 응답 회복 시간 비교 |
| CPU 부하 | productcatalog-auto | Metrics Server, HPA, k6 | 1 → 2 → 1 |
| HPA OFF/ON | ProductCatalog Service | k6 Job, Service, HPA | P95, RPS, 오류율 |
| Deployment Failure | productcatalog-rollout | Probe, Rolling Update | 기존 정상 Pod 유지 |
| Rollback | productcatalog-rollout | Deployment Revision | 수동 복구 16.360초 |
| Pod NotReady Alert | alert-test-pod | PrometheusRule, Alertmanager | Firing 확인 |

---

## 9. 모니터링 구조

**9.1 시스템 구성**

```
Kubernetes Nodes
       │
       ▼
Node Exporter ──────────┐
                        │
Kubernetes Objects      │
       │                │
       ▼                │
kube-state-metrics ─────┤
                        ▼
                    Prometheus
                        │
              ┌─────────┴─────────┐
              │                   │
              ▼                   ▼
           Grafana          Alert Rules
                                  │
                                  ▼
                             Alertmanager
```

### 9.2 주요 관측 지표

| 지표 | 수집 또는 확인 방법 |
| --- | --- |
| Node CPU / Memory | Node Exporter / Prometheus |
| Pod CPU / Memory | Metrics Server 및 Prometheus |
| Pod Ready | kube-state-metrics |
| Container Restart | kube-state-metrics |
| Deployment Available Replicas | kube-state-metrics |
| HPA Replica | kubectl / Kubernetes Metrics |
| gRPC P95 | k6 |
| RPS | k6 |
| Error Rate | k6 |

### 9.3 알림 검증

실험용 Pod의 Readiness Probe 실패를 통해 NotReady 상태를 재현했다.

Prometheus에서 `RecoveryTestPodNotReady`의 Firing 상태를 확인했으며, Alertmanager에서 관련 알림 그룹이 표시되는 것을 확인했다.

알림 발생부터 수신까지의 지연 시간을 정량적으로 측정하지는 않았다.

---

## 10. k6 부하 테스트 구조

최종 HPA 성능 비교에서는 Windows PC의 port-forward 방식 대신 EKS 내부의 k6 Job을 사용했다.

```
EKS Cluster
    │
    ▼
k6 Job
    │
    ▼
Kubernetes ClusterIP Service
    │
    ▼
productcatalog-auto Deployment
    │
    ▼
ProductCatalog Pod
```

k6 이미지는 Amazon ECR에 업로드했으며, 테스트 스크립트와 Proto 파일은 ConfigMap으로 주입했다.

### 10.2 부하 조건

| 항목 | 설정 |
| --- | --- |
| 대상 | ProductCatalog gRPC API |
| 테스트 방법 | EKS 내부 k6 Job |
| 부하 모델 | Constant Arrival Rate |
| 목표 요청 속도 | 100 RPS |
| 테스트 시간 | 180초 |
| HPA OFF | Replica 1개 |
| HPA ON | CPU 기반 자동 확장 |

### 10.3 성능 측정 결과

| 항목 | HPA OFF | HPA ON |
| --- | --- | --- |
| 총 요청 | 18,001 | 18,001 |
| 처리량 | 약 100 RPS | 약 100 RPS |
| 평균 gRPC 응답 | 0.853ms | 0.921ms |
| P95 | 1.25ms | 1.38ms |
| 오류율 | 0% | 0% |

---

## 11. Terraform 관리 범위

### 11.1 AWS 관리 대상

```
Terraform
    │
    ▼
AWS Infrastructure
    ├── VPC
    ├── Public Subnet × 2
    ├── Internet Gateway
    ├── Route Table / Route
    ├── Route Table Association
    ├── IAM Role / Policy Attachment
    ├── EKS Cluster
    ├── Managed Node Group
    ├── VPC CNI Add-on
    ├── Pod Identity Agent Add-on
    └── Metrics Server Add-on
```

Metrics Server는 EKS Add-on으로 설치한 뒤 Terraform Import를 통해 관리 대상으로 편입했다.

### 11.2 Terraform 검증 결과

| 검증 항목 | 결과 |
| --- | --- |
| `terraform fmt -check` | 통과 |
| `terraform validate` | 통과 |
| Metrics Server Import | 성공 |
| Terraform Apply | 태그 변경 적용 |
| 최종 Terraform Plan | No changes |
| GitHub 반영 | 완료 |

최종 Terraform Plan에서 관리 대상 AWS 리소스와 코드 사이의 차이가 발견되지 않았다.

이는 Terraform으로 관리하는 AWS 리소스에 대한 상태 일치 검증이며, Kubernetes 애플리케이션과 Helm 설정까지 모두 Terraform에서 관리한다는 의미는 아니다.

### 11.3 Terraform 비관리 영역

- Kubernetes 애플리케이션 Manifest
- Argo CD Application
- Helm 기반 Monitoring 구성
- GitHub Actions 워크플로
- 실험용 Kubernetes Job 및 Pod
- 별도로 생성한 ECR Repository

---

## 12. 관리 영역 분리

| 영역 | 관리 도구 | 실제 적용 |
| --- | --- | --- |
| Application Source | GitHub | 적용 |
| Container Build | Docker / GitHub Actions | 적용 |
| Container Registry | Amazon ECR | 적용 |
| AWS Infrastructure | Terraform | 적용 |
| Kubernetes Application | YAML / Kustomize | 적용 |
| GitOps CD | Argo CD | 적용 |
| Resource Metrics | Metrics Server | 적용 |
| Monitoring | Prometheus / Grafana | 적용 |
| Alerting | PrometheusRule / Alertmanager | 검증 |
| Load Test | k6 | 검증 |
| Failure Test | PowerShell / kubectl | 검증 |

---

## 13. 보안 기본 방향

### 13.1 AWS 인증 및 IAM

- AWS IAM Identity Center 기반 SSO 사용
- Terraform 코드에 AWS Access Key 직접 저장하지 않음
- EKS Cluster Role과 Node Role 분리
- VPC CNI 관련 IAM Role 분리
- EKS Pod Identity Agent 사용

### 13.2 네트워크

- VPC 내부에서 Kubernetes Workload 운영
- EKS API 접근 범위 제한
- AWS Security Group 기반 접근 제어
- 실습 환경에서는 Public Subnet 기반 Worker Node 구성
- 별도 NAT Gateway 미사용

### 13.3 컨테이너 및 Kubernetes

- Namespace를 통한 실험 영역 분리
- Readiness 및 Liveness Probe 활용
- CPU / Memory Request 및 Limit 설정
- 일부 실험용 컨테이너에 Non-root 실행 및 읽기 전용 Root Filesystem 적용

### 13.4 Git 및 민감 정보

- `terraform.tfstate` Git 관리 제외
- `terraform.tfvars` Git 관리 제외
- Terraform Plan 파일 Git 관리 제외
- AWS 인증 정보를 소스 코드에 포함하지 않음

---

## 14. 설계상 핵심 포인트

### 14.1 운영 자동화 흐름

```
Source Code
    │
    ▼
GitHub Actions
    │
    ▼
Amazon ECR
    │
    ▼
GitOps Deployment
    │
    ▼
Kubernetes Application
    │
    ├── ReplicaSet Self-Healing
    ├── HPA Scaling
    ├── Readiness / Liveness Probe
    └── Rolling Update
    │
    ▼
Prometheus Monitoring
    │
    ▼
Alertmanager
    │
    ▼
장애 분석 및 운영 개선
```

### 14.2 설계 결정 및 근거

| 설계 결정 | 이유 |
| --- | --- |
| AWS EKS 활용 | Kubernetes 운영 및 장애 대응 기능 검증 |
| Terraform 사용 | 인프라 구성 코드화 및 상태 관리 |
| Managed Node Group 사용 | Worker Node 관리 복잡도 완화 |
| Amazon ECR 사용 | AWS 환경과 이미지 저장소 연계 |
| Argo CD 사용 | Git 기반 선언적 배포 관리 |
| Recovery Test Namespace 분리 | 기존 서비스에 대한 장애 영향 최소화 |
| ReplicaSet 활용 | Pod 장애 시 원하는 Replica 수 유지 |
| HPA 활용 | CPU 사용률 변화에 따른 자동 확장 |
| Readiness Probe 활용 | 비정상 Pod의 요청 처리 제외 |
| Prometheus 활용 | Kubernetes 상태 관측 및 장애 알림 |
| k6 활용 | 반복 가능한 정량적 부하 테스트 |

### 14.3 아키텍처 검증의 핵심 결과

수동 Pod 복구의 평균 Ready 도달 시간은 19.101초, 자동 복구는 3.666초로 측정됐다.

HPA는 CPU 사용률 증가에 따라 실제로 Pod를 확장했으며, 잘못된 Deployment는 Readiness Probe를 통과하지 못해 기존 정상 Pod가 유지됐다.

또한 Prometheus를 통해 장애 상태가 Firing으로 전환되는 것을 확인했다.

이러한 결과를 통해 장애 유형별로 Kubernetes의 상태 유지·복구 메커니즘이 어떻게 동작하는지 검증했다.

---

## 15. 최종 구성 및 미검증 항목

### 15.1 최종 확정 구성

| 항목 | 최종 구성 |
| --- | --- |
| AWS Region | ap-northeast-2 |
| EKS Version | 1.35 |
| Worker Node | t3.large × 2 |
| VPC CIDR | 10.0.0.0/16 |
| Subnet | Public Subnet × 2 |
| NAT Gateway | 미사용 |
| Container Registry | Amazon ECR |
| CI | GitHub Actions |
| CD | Argo CD |
| Monitoring | Prometheus / Grafana |
| Alerting | PrometheusRule / Alertmanager |
| HPA CPU Target | 60% |
| HPA Min / Max | 1 / 3 |
| Kubernetes Metrics | EKS Metrics Server Add-on |
| Load Test | EKS 내부 k6 Job |

### 15.2 미검증 및 향후 개선 사항

| 항목 | 최종 상태 |
| --- | --- |
| 자동 Pod 재생성 | 검증 완료 |
| HPA 자동 확장·축소 | 검증 완료 |
| HPA 응답 성능 개선 | 미입증 |
| Deployment 수동 Rollback | 검증 완료 |
| Deployment 자동 Rollback | 미구현 |
| 실제 서비스 무중단 | 정량 검증 미완료 |
| 서비스 전체 MTTD / MTTR | 정량 검증 미완료 |
| 사용자 요청 기반 Availability | 정량 검증 미완료 |
| 알림 전달 지연 시간 | 정량 검증 미완료 |
| 전체 환경 자동 재구축 | 완전한 재현성 검증 미완료 |
| gRPC 연결 재분산 효과 | 추가 검증 필요 |

### 최종 결론

**Terraform 기반 AWS 인프라 관리, GitOps 배포, Kubernetes 자동 복구 및 Prometheus 장애 관측을 연계한 운영 구조이다.**

Pod 장애, CPU 부하, 잘못된 배포 및 NotReady 상황을 직접 재현하여 각 구성요소의 동작을 확인했으며, 수동 복구 대비 자동 복구의 시간 차이를 정량적으로 측정했다.

이를 통해 단순한 애플리케이션 배포 환경을 넘어, **장애를 감지하고 시스템이 원하는 상태를 유지하며 복구 결과를 검증할 수 있는 Kubernetes 운영 환경**을 구성했다.
