| 버전 | 변경 내용 | 상태 |
| --- | --- | --- |
| v0.1 | GitHub Actions, Container Registry, Argo CD 기반 CI/CD 설계 | 완료 |
| v0.2 | GitHub Actions 기반 Frontend 이미지 Build 및 Amazon ECR Push 검증 | 완료 |
| v0.3 | Argo CD GitOps 배포, Sync 및 Self-Heal 설정 반영 | 완료 |
| v0.4 | Readiness Probe 기반 배포 실패 및 수동 Rollback 결과 반영 | 완료 |
| v1.0 | 최종 CI/CD 구성, 실제 배포 흐름, 검증 결과 및 운영 한계 반영 | 최종 |

---

## 1. 문서 목적

Google Online Boutique 기반 애플리케이션의 소스 코드 관리부터 컨테이너 이미지 빌드, Amazon ECR 저장, Kubernetes 배포까지의 CI/CD 구조를 정의한다.

GitHub Actions를 이용하여 애플리케이션 이미지를 빌드하고 Amazon ECR에 업로드하는 CI 환경을 구성하였다.

또한 Argo CD를 이용하여 Git 저장소에 선언된 Kubernetes Manifest와 AWS EKS 클러스터의 상태를 동기화하는 GitOps 기반 CD 환경을 구성하였다.

이를 통해 이미지 생성과 Kubernetes 배포의 책임을 분리하고, 애플리케이션 변경 사항을 Git을 기준으로 관리할 수 있도록 설계하였다.

배포 안정성 검증에서는 Readiness Probe가 잘못 설정된 Deployment를 배포하여 Rolling Update와 수동 Rollback 동작을 확인하였다.

**본 문서의 핵심 목적은 CI/CD 파이프라인의 구성뿐 아니라 실제 배포 시 정상 상태를 확인하고, 잘못된 배포가 발생했을 때 복구할 수 있는 운영 절차를 검증하는 것이다.**

---

## 2. 설계 목표

### 2.1 핵심 목표

- GitHub 기반 애플리케이션 소스 코드 관리
- GitHub Actions를 통한 Docker 이미지 빌드
- Amazon ECR 기반 컨테이너 이미지 저장
- Git Commit SHA 기반 이미지 버전 식별
- Kubernetes Manifest 기반 배포 구성 관리
- Argo CD 기반 GitOps 배포
- Git과 Kubernetes 리소스 상태 동기화
- Kubernetes Rolling Update 동작 검증
- Readiness Probe를 이용한 잘못된 배포 차단
- Deployment Revision 기반 수동 Rollback 검증

### 2.2 목표 달성 결과

| 목표 | 최종 결과 |
| --- | --- |
| Docker 이미지 자동 빌드 | GitHub Actions 구성 및 실행 |
| Container Registry 연동 | Amazon ECR 사용 |
| 이미지 버전 식별 | Git SHA 기반 태그 활용 |
| Kubernetes 배포 관리 | Argo CD 적용 |
| GitOps 상태 동기화 | Synced / Healthy 확인 |
| Self-Heal 설정 | 구성 완료 |
| Rolling Update | 검증 완료 |
| 잘못된 배포 감지 | ProgressDeadlineExceeded 확인 |
| Rollback | 수동 Rollback 성공 |
| 자동 Rollback | 미구현 |
| 전체 CI/CD 소요 시간 | 별도 정량 측정 미완료 |

---

## 3. CI/CD 전체 흐름

### 3.1 최종 아키텍처

```
Developer
    │
    ▼
GitHub Repository
    │
    ├─────────────────────────────┐
    │                             │
    ▼                             ▼
GitHub Actions              Kubernetes Manifest
    │                             │
    ├── Source Checkout           │
    ├── Docker Build              │
    ├── Image Tag                 │
    └── Amazon ECR Push           │
              │                   ▼
              ▼                 Argo CD
          Amazon ECR              │
              │                   │
              └────────┬──────────┘
                       ▼
                 AWS EKS Cluster
                       │
                       ▼
                Online Boutique
                       │
                Kubernetes
                Deployment
                       │
                       ▼
                 Rolling Update
                       │
                       ▼
                Pod Ready 확인
```

### 3.2 구성요소별 역할

| 구성요소 | 역할 |
| --- | --- |
| GitHub | 애플리케이션 소스 및 Kubernetes 설정 관리 |
| GitHub Actions | Docker 이미지 빌드 및 ECR 업로드 |
| Docker | 컨테이너 이미지 생성 |
| Amazon ECR | 이미지 저장 및 배포 이미지 제공 |
| Kubernetes Manifest | Deployment 및 이미지 버전 선언 |
| Argo CD | Git과 Kubernetes 상태 동기화 |
| AWS EKS | 애플리케이션 실행 및 Deployment 운영 |

### 3.3 설계 특징

CI와 CD를 분리하여 GitHub Actions가 Kubernetes 클러스터에 직접 배포하는 방식을 사용하지 않았다.

GitHub Actions는 컨테이너 이미지를 생성하고 저장하는 역할을 담당한다.

Argo CD는 Git에 선언된 Manifest를 기준으로 Kubernetes 리소스의 Desired State를 관리한다.

이미지가 ECR에 업로드되는 것만으로 Argo CD가 새로운 이미지 버전을 자동 선택하는 것은 아니며, Kubernetes Manifest의 이미지 참조가 변경되어야 새 버전의 배포가 진행될 수 있다.

---

## 4. CI와 CD 역할 분리

### 4.1 CI — GitHub Actions

```
Source Code 변경
        ↓
GitHub Push
        ↓
GitHub Actions
        ↓
Docker Image Build
        ↓
Image Tag 생성
        ↓
Amazon ECR Push
```

**담당 범위**

- 소스 코드 체크아웃
- Docker 빌드
- 이미지 태그 지정
- AWS 인증
- ECR 로그인
- 컨테이너 이미지 업로드

### 4.2 CD — Argo CD

```
Git Manifest
      ↓
Argo CD
      ↓
Desired State 비교
      ↓
Kubernetes Sync
      ↓
Deployment
      ↓
Pod Ready
```

**담당 범위**

- Git 저장소의 Kubernetes Manifest 참조
- 실제 클러스터 상태 비교
- Kubernetes 리소스 동기화
- 자동 동기화 및 Self-Heal 설정
- Application 상태 확인

### 4.3 역할 분리 결론

```
GitHub Actions
= Container Image Build / Push

Argo CD
= Kubernetes GitOps Deployment

Kubernetes
= Rolling Update / ReplicaSet / Probe
```

이를 통해 이미지 생성, 배포 상태 관리, Kubernetes 내부의 리소스 복구 기능을 분리하였다.

---

## 5. Repository 관리 방식

### 5.1 적용 방식

단일 GitHub Repository에서 애플리케이션 소스 코드, Dockerfile, Kubernetes Manifest, CI/CD 설정 및 장애 테스트 코드를 관리하였다.

**Repository**

`https://github.com/Ohteakhyeon/k8s-auto-recovery-lab`

### 5.2 주요 디렉터리

```
k8s-auto-recovery-lab/
│
├── src/
│   └── frontend/
│
├── kubernetes/
│   ├── online-boutique/
│   └── overlays/
│       └── eks/
│
├── argocd/
│
├── terraform/
│
├── monitoring/
│
├── tests/
│   ├── hpa/
│   ├── rollout/
│   ├── alerts/
│   └── results/
│
└── .github/
    └── workflows/
```

### 5.3 설계 판단

개인 프로젝트의 규모와 관리 복잡도를 고려하여 Application Repository와 GitOps Repository를 별도로 분리하지 않았다.

단일 Repository를 사용함으로써 애플리케이션 소스, 이미지 빌드 설정, Kubernetes Manifest 및 장애 테스트 기록을 연결하여 관리하였다.

다만 실제 운영 환경에서는 애플리케이션 소스와 배포 Manifest를 분리하는 구조도 검토할 수 있다.

---

## 6. CI Trigger 설계

### 6.1 초기 계획

```
Feature Branch
      ↓
Pull Request
      ↓
Test
      ↓
Merge
      ↓
main Push
      ↓
Docker Build / Push
```

### 6.2 실제 프로젝트 적용

GitHub Actions를 이용해 Frontend 이미지 빌드 및 ECR 업로드 워크플로를 구성하였다.

최종적으로 프로젝트 전용 Frontend 이미지를 ECR에 저장하고 EKS 배포에 활용하였다.

### 6.3 검증 범위

Frontend 이미지의 빌드·푸시 동작은 확인하였다.

다만 Pull Request 검증과 main 브랜치 병합에 따른 모든 CI Trigger 조합을 별도로 시험한 기록은 확보하지 않았다.

따라서 전체 Branch 전략이 완전히 검증된 것으로 기록하지 않는다.

---

## 7. GitHub Actions Workflow

### 7.1 주요 수행 단계

```
GitHub Actions
      │
      ▼
Source Checkout
      │
      ▼
AWS 인증
      │
      ▼
Amazon ECR Login
      │
      ▼
Docker Image Build
      │
      ▼
Git Commit SHA 기반 Tag
      │
      ▼
Image Push
```

### 7.2 CI 구성 요소

| 단계 | 역할 |
| --- | --- |
| Checkout | GitHub 소스 코드 가져오기 |
| AWS 인증 | ECR 접근을 위한 AWS 인증 |
| ECR Login | Docker Registry 인증 |
| Docker Build | Frontend 이미지 생성 |
| Image Tag | 이미지 버전 식별 |
| Docker Push | Amazon ECR에 이미지 업로드 |

### 7.3 실제 검증

GitHub Actions를 통해 Frontend 이미지를 빌드하고 ECR로 업로드하는 과정을 구성하였다.

Frontend의 gRPC 재연결 및 백오프 동작을 변경한 이후 새 이미지를 배포하는 흐름도 검증하였다.

### 7.4 미검증 항목

- Workflow 단계별 실행 시간 비교
- 모든 Pull Request Trigger 검증
- 자동화된 통합 테스트의 전체 범위
- CI 실패 시 후속 배포 자동 차단 검증

---

## 8. Container Registry 설계

### 8.1 초기 검토

초기에는 GHCR과 Amazon ECR을 비교하였다.

### 8.2 최종 선택 — Amazon ECR

AWS EKS와의 연계를 고려하여 Amazon ECR을 선택하였다.

**선정 이유**

- AWS 환경 내에서 이미지 저장 및 관리
- IAM 기반 Registry 접근 제어
- GitHub Actions와 연계
- EKS Worker Node의 이미지 Pull에 활용

### 8.3 이미지 Repository

**Frontend**

```
007053125976.dkr.ecr.ap-northeast-2.amazonaws.com/k8s-auto-recovery/frontend
```

**k6**

```
007053125976.dkr.ecr.ap-northeast-2.amazonaws.com/k8s-auto-recovery/k6
```

Frontend 이미지는 애플리케이션 배포에 사용하였다.

k6 이미지는 EKS 내부에서 실행할 부하 테스트 Job에 사용하였다.

---

## 9. Image Tag 전략

### 9.1 설계 목적

`latest`만 사용하는 방식은 이미지 버전 추적과 이전 버전 복구에 불리할 수 있다.

따라서 Git Commit 기반의 이미지 태그를 활용하여 소스 코드와 빌드 결과를 연결하였다.

### 9.2 태그 방식

```
frontend:<git-sha>
```

### 9.3 실제 확인한 이미지 식별자

```
6c523ad28c5229d97c18de05b0a3d2c1bf2bb9d8
```

Frontend 개선 버전 배포 시 확인한 Git SHA 기반 이미지 식별자이다.

### 9.4 태그 관리의 장점

- 이미지와 Git Commit 연결
- 배포된 버전 식별
- 이전 이미지 버전 추적
- 장애 발생 시 복구 대상 식별

단, Git Commit 태그만으로 이미지 내용이 불변임을 보장하지는 않으므로 실제 운영 환경에서는 Image Digest 기반 관리도 고려할 수 있다.

---

## 10. Manifest Image Version 관리

### 10.1 설계 목적

Kubernetes Manifest에 사용할 이미지 Registry와 Tag를 명시하여 배포 상태를 Git에서 추적할 수 있도록 구성하였다.

### 10.2 이미지 설정 예시

```
images:
  - name: frontend
    newName: 007053125976.dkr.ecr.ap-northeast-2.amazonaws.com/k8s-auto-recovery/frontend
    newTag: <git-sha>
```

위 YAML은 이미지 버전 관리 구조를 설명하기 위한 예시이며, 실제 배포 시에는 빌드된 이미지의 Tag를 사용한다.

### 10.3 GitOps 배포 흐름

```
Image Build / Push
       ↓
ECR에 이미지 저장
       ↓
Manifest Image Tag 변경
       ↓
Git Repository 반영
       ↓
Argo CD Sync
       ↓
Kubernetes Rolling Update
```

### 10.4 실제 검증 범위

GitHub Actions를 통한 이미지 빌드·푸시와 Argo CD 기반 배포 상태 동기화를 확인하였다.

다만 **CI가 이미지 태그를 자동으로 Manifest에 커밋하는 단계까지 구현했는지는 현재 기록에서 확인되지 않는다.**

따라서 Manifest 이미지 태그의 완전 자동 갱신은 검증 완료 항목에 포함하지 않는다.

---

## 11. Argo CD 설계

### 11.1 역할

Argo CD는 Git Repository를 기준으로 Kubernetes 리소스의 원하는 상태와 실제 상태를 비교하고 동기화하는 GitOps 기반 CD 도구이다.

### 11.2 실제 적용 구성

| 항목 | 설정 |
| --- | --- |
| CD Tool | Argo CD |
| Kubernetes Cluster | auto-recovery-eks |
| Application | online-boutique |
| Source | GitHub Repository |
| Manifest 관리 | Kustomize |
| Manifest 경로 | kubernetes/overlays/eks |
| 배포 Namespace | online-boutique |
| Sync | 자동 동기화 설정 |
| Self-Heal | 설정 적용 |

### 11.3 동기화 구조

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
Desired / Actual 비교
       │
       ▼
Kubernetes Sync
       │
       ▼
Deployment / Service
```

### 11.4 실제 검증

Argo CD Application `online-boutique`가 다음 상태임을 확인하였다.

```
Sync Status  : Synced
Health Status: Healthy
```

### 11.5 Self-Heal의 역할

Argo CD Self-Heal은 Git에 선언된 리소스 상태와 실제 클러스터 리소스 상태 사이에 차이가 발생했을 때 이를 다시 동기화하는 기능이다.

다만 Kubernetes ReplicaSet의 Pod 자동 재생성과는 서로 다른 기능이다.

또한 Self-Heal을 활성화했다고 해서 잘못된 애플리케이션 버전이 자동으로 이전 버전으로 Rollback되는 것은 아니다.

---

## 12. 배포 전략

### 12.1 Rolling Update

Kubernetes Deployment의 Rolling Update를 활용하여 신규 Revision을 단계적으로 배포하였다.

```
기존 Revision
      │
      ▼
새로운 Pod 생성
      │
      ▼
Readiness Probe
      │
      ├── 성공 → 신규 Pod 사용 가능
      │
      └── 실패 → 신규 Pod NotReady
                         │
                         ▼
                   기존 Pod 유지
```

### 12.2 배포 실패 테스트 설정

| 항목 | 설정 |
| --- | --- |
| Deployment | productcatalog-rollout |
| Namespace | recovery-test |
| Replica | 1 |
| Strategy | RollingUpdate |
| maxSurge | 1 |
| maxUnavailable | 0 |
| progressDeadlineSeconds | 120 |

### 12.3 검증 결과

신규 Pod의 Readiness Probe가 실패했지만 기존 정상 Pod가 유지되었다.

이를 통해 Rolling Update의 가용 Replica 유지 동작을 확인하였다.

다만 사용자 요청을 연속적으로 측정하지 않았으므로 무중단 배포를 정량적으로 검증했다고 해석하지 않는다.

---

## 13. Readiness Probe와 배포 연계

### 13.1 역할

Readiness Probe는 Pod가 사용자 요청을 처리할 준비가 되었는지 판단한다.

Readiness Probe에 실패한 Pod는 일반적인 Kubernetes Service의 요청 대상에서 제외된다.

### 13.2 정상 설정

```
readinessProbe:
  grpc:
    port: 3550
```

### 13.3 오류 설정

```
readinessProbe:
  grpc:
    port: 3551
```

### 13.4 실제 결과

| 구분 | 상태 |
| --- | --- |
| 기존 정상 Pod | 1/1 Ready |
| 신규 오류 Pod | 0/1 Ready |
| Deployment Progressing | False |
| Failure Reason | ProgressDeadlineExceeded |
| Deployment Available | True |

신규 Pod는 Ready 상태로 전환되지 못했지만, 기존 정상 Pod가 유지되어 Deployment의 가용 Replica가 남아 있는 것을 확인하였다.

---

## 14. Deployment Failure 실험

### 14.1 초기 계획

PaymentService의 잘못된 버전을 빌드하고 Argo CD를 통해 배포한 뒤, 서비스 오류와 Rollback 과정을 관찰할 계획이었다.

### 14.2 실제 변경 사항

최종 실험에서는 기존 쇼핑몰 서비스에 대한 영향을 최소화하기 위해 별도의 ProductCatalog Deployment를 이용하였다.

잘못된 애플리케이션 이미지 대신 Readiness Probe 포트 오류를 유도하였다.

### 14.3 실제 장애 주입

정상 설정:

```
readinessProbe:
  grpc:
    port: 3550
```

장애 설정:

```
readinessProbe:
  grpc:
    port: 3551
```

### 14.4 장애 확인

```
kubectl get pods -n recovery-test

kubectl describe deployment productcatalog-rollout -n recovery-test

kubectl rollout status deployment/productcatalog-rollout -n recovery-test
```

### 14.5 검증 결과

- 신규 Pod `0/1 Ready`
- 기존 Pod `1/1 Ready`
- Rolling Update 진행 실패
- `ProgressDeadlineExceeded` 확인
- 기존 정상 Revision 유지

---

## 15. Broken Version 설계 변경

### 15.1 초기 계획

```
paymentservice:v1
       ↓
paymentservice:v2-broken
       ↓
Payment Request Error
       ↓
Rollback
```

기존 설계는 컨테이너가 Running 상태여도 애플리케이션 기능이 실패할 수 있다는 점을 검증하기 위한 시나리오였다.

### 15.2 최종 실험

```
ProductCatalog 정상 Deployment
             ↓
Readiness Probe 오류 적용
             ↓
신규 Pod Running
             ↓
Readiness 실패
             ↓
신규 Pod NotReady
             ↓
기존 Pod 유지
             ↓
수동 Rollback
```

### 15.3 실험 한계

이번 실험은 애플리케이션 내부 기능 오류나 PaymentService의 결제 실패를 재현한 것은 아니다.

따라서 컨테이너는 Ready지만 실제 비즈니스 기능은 실패하는 상황을 검증한 것으로 기록하지 않는다.

---

## 16. Rollback 전략

### 16.1 초기 검토

- Argo CD Revision Rollback
- Git Revert
- Kubernetes Deployment Rollback

### 16.2 실제 적용

이번 프로젝트에서 실제 검증한 방식은 Kubernetes의 `kubectl rollout undo`이다.

```
kubectl rollout undo deployment/productcatalog-rollout -n recovery-test
```

### 16.3 복구 흐름

```
신규 Revision NotReady
          │
          ▼
ProgressDeadlineExceeded 확인
          │
          ▼
kubectl rollout undo
          │
          ▼
이전 Deployment 설정 복구
          │
          ▼
Rollout Status 확인
          │
          ▼
정상 상태 복귀
```

### 16.4 실제 결과

| 항목 | 결과 |
| --- | --- |
| Rollback 대상 | productcatalog-rollout |
| 방법 | kubectl rollout undo |
| 복구 방식 | 수동 |
| 측정 시간 | 16.360초 |
| 결과 | 정상 Revision 복귀 |

해당 시간은 수동 Rollback 명령 실행부터 배포 완료 확인까지의 시간이다.

실제 사용자 서비스 중단 시간 또는 전체 MTTR과 동일하지 않다.

### 16.5 GitOps 운영 시 주의사항

Argo CD가 관리하는 Deployment를 `kubectl rollout undo`로 직접 변경하면 Git의 Desired State와 실제 클러스터 상태가 달라질 수 있다.

따라서 GitOps 운영 환경에서는 Git Manifest를 정상 버전으로 복구하고 Argo CD를 통해 동기화하는 방식이 적합하다.

이번 Rollback 실험은 Argo CD 관리 대상과 분리된 `recovery-test` Namespace에서 수행하였다.

---

## 17. CI/CD Secret 관리

### 17.1 관리 원칙

AWS 인증 정보, Registry Credential 및 Token 등의 민감정보를 GitHub Repository에 직접 저장하지 않는다.

### 17.2 AWS 인증

개발 PC에서는 IAM Identity Center 기반 SSO를 사용하였다.

GitHub Actions에서는 별도의 AWS 인증 구성이 필요하다.

### 17.3 적용 및 검증 범위

GitHub Actions와 ECR 간 인증이 이루어져 이미지 Push가 성공한 것은 확인하였다.

다만 GitHub Actions의 인증이 OIDC 기반인지, GitHub Secrets 기반 자격 증명을 사용했는지는 현재 제공된 기록만으로 확정할 수 없다.

따라서 사용한 인증 방식과 IAM 권한 범위는 실제 Workflow YAML을 기준으로 별도 검증할 필요가 있다.

### 17.4 향후 개선

- GitHub OIDC 기반 단기 자격 증명 사용 검증
- IAM 최소 권한 적용
- Registry Push 권한과 EKS 배포 권한 분리
- GitHub Actions Secret 관리 및 접근 범위 점검

---

## 18. CI/CD 측정 지표

### 18.1 계획 지표

| 지표 | 측정 내용 | 실제 측정 상태 |
| --- | --- | --- |
| Build Time | 이미지 빌드 소요 시간 | 미측정 |
| Push Time | ECR 업로드 소요 시간 | 미측정 |
| Deployment Time | 배포 시작부터 Pod Ready까지 | 별도 통합 측정 미완료 |
| Failure Detection Time | 잘못된 배포부터 실패 판정까지 | 별도 수치 미기록 |
| Rollback Time | 복구 시작부터 배포 완료까지 | 측정 완료 |
| Error Rate | 배포 과정의 요청 실패 비율 | 미측정 |
| MTTR | 서비스 장애부터 정상화까지 | 전체 서비스 기준 미측정 |

### 18.2 실제 정량 결과

**수동 Rollback Time**

`16.360초`

### 18.3 해석

Rollback Time은 실제 측정하였으나, Build Time, Push Time, Deployment Time 및 배포 장애 중 요청 오류율은 별도 수치를 확보하지 않았다.

따라서 전체 CI/CD 과정의 처리 속도 개선이나 자동 Rollback 효과는 이번 프로젝트의 정량 성과에 포함하지 않는다.

---

## 19. CI/CD 장애 대응 흐름

### 19.1 정상 배포

```
Git Manifest 변경
        ↓
Argo CD Sync
        ↓
Kubernetes Deployment
        ↓
Rolling Update
        ↓
Readiness 성공
        ↓
정상 배포
```

### 19.2 잘못된 배포

```
잘못된 Deployment 설정
        ↓
신규 Pod 생성
        ↓
Readiness 실패
        ↓
신규 Pod NotReady
        ↓
기존 Pod 유지
        ↓
ProgressDeadlineExceeded
        ↓
운영자 확인
        ↓
수동 Rollback
        ↓
정상 Revision 복귀
```

### 19.3 실제 복구 명령어

```
kubectl rollout history deployment/productcatalog-rollout -n recovery-test

kubectl describe deployment productcatalog-rollout -n recovery-test

kubectl rollout undo deployment/productcatalog-rollout -n recovery-test

kubectl rollout status deployment/productcatalog-rollout -n recovery-test
```

---

## 20. 책임 영역

| 영역 | 담당 도구 | 검증 내용 |
| --- | --- | --- |
| Source 관리 | GitHub | 소스 및 Manifest 관리 |
| CI | GitHub Actions | 이미지 빌드·푸시 |
| Image Build | Docker | Frontend 이미지 생성 |
| Image 저장 | Amazon ECR | 이미지 업로드 |
| Manifest 관리 | GitHub / Kustomize | 이미지 및 리소스 정의 |
| CD | Argo CD | GitOps Sync |
| Rolling Update | Kubernetes Deployment | 신규 Pod 배포 |
| Pod 복구 | ReplicaSet | Desired Replica 유지 |
| 배포 복구 | kubectl rollout undo | 수동 Rollback |
| 모니터링 | Prometheus / Grafana | 리소스 상태 관측 |
| 알림 | Alertmanager | 장애 알림 관리 |

---

## 21. 최종 구성 및 미검증 항목

### 21.1 구현 완료 항목

| 항목 | 실제 결과 |
| --- | --- |
| Registry | Amazon ECR |
| Frontend Docker Build | 완료 |
| GitHub Actions 이미지 Push | 완료 |
| Git SHA 기반 이미지 식별 | 적용 |
| Kubernetes Manifest 관리 | Kustomize |
| Argo CD Application | online-boutique |
| Argo CD Auto Sync | 설정 |
| Argo CD Self-Heal | 설정 |
| Argo CD 배포 상태 | Synced / Healthy |
| Rolling Update | 검증 |
| Readiness 실패 | 재현 |
| 수동 Rollback | 성공 |

### 21.2 미구현 및 추가 검증 항목

| 항목 | 상태 |
| --- | --- |
| CI의 Manifest 이미지 태그 자동 Commit | 검증 필요 |
| Pull Request 전체 Trigger | 미검증 |
| Build / Push 시간 | 미측정 |
| GitHub Actions AWS 인증 방식 | 실제 Workflow 확인 필요 |
| Argo CD 자동 Rollback | 미구현 |
| Git Revert 기반 Rollback | 미검증 |
| Canary / Blue-Green | 미구현 |
| 배포 중 실제 사용자 오류율 | 미측정 |
| 전체 CI/CD 배포 시간 | 미측정 |

---

## 22. 설계 결론

GitHub Actions를 이용하여 Frontend Docker 이미지를 빌드하고 Amazon ECR에 업로드하는 CI 환경을 구성하였다.

또한 Argo CD를 통해 Git에 선언된 Kubernetes Manifest를 AWS EKS 클러스터와 동기화하고, Online Boutique Application의 Synced / Healthy 상태를 확인하였다.

배포 실패 실험에서는 Readiness Probe가 잘못 설정된 신규 Pod가 Ready 상태에 도달하지 못했으며, 기존 정상 Pod가 유지되는 것을 확인하였다.

이후 `kubectl rollout undo`를 실행하여 정상 Revision으로 복구했으며, 16.360초의 수동 Rollback 시간을 측정하였다.

이를 통해 이미지 빌드, 배포 상태 관리, Kubernetes Rolling Update 및 장애 복구 절차를 각각 검증하였다.

### 최종 결론 한 줄

**GitHub Actions는 이미지 빌드를 자동화하고 Argo CD는 Git 기반 배포 상태를 관리했으며, 잘못된 배포에서는 Readiness Probe가 비정상 Pod를 차단하고 수동 Rollback으로 정상 상태를 복구했습니다. 결국 안정적인 CI/CD의 핵심은 빠른 배포 자체보다, 변경 이력을 추적하고 실패한 배포를 안전하게 복구할 수 있는 구조에 있었습니다.**
