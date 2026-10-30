| 버전 | 변경 내용 | 상태 |
| --- | --- | --- |
| v0.1 | Dockerfile 구조, Multi-stage Build, 이미지 관리 및 최적화 설계 | 완료 |
| v0.2 | Frontend 이미지 빌드 및 로컬 Kubernetes 실행 검증 | 완료 |
| v0.3 | Amazon ECR, GitHub Actions 및 이미지 태그 관리 반영 | 완료 |
| v1.0 | 실제 이미지 구성, 빌드·배포 흐름, Kubernetes 연계 및 검증 결과 반영 | 최종 |

---

## 1. 문서 목적

Google Online Boutique의 주요 마이크로서비스 Dockerfile 구조를 분석하고, 컨테이너 이미지의 빌드 방식과 실행 환경, 이미지 관리 및 Kubernetes 연계 방식을 정의한다.

기존 오픈소스 애플리케이션을 새로 개발하는 대신 제공된 Dockerfile의 구조를 이해하고, 필요한 서비스를 직접 빌드하여 로컬 Kubernetes 및 AWS EKS 환경에서 정상 동작하는지 검증하였다.

또한 GitHub Actions와 Amazon ECR을 연계해 이미지 빌드·저장 과정을 자동화하고, Argo CD를 통해 Kubernetes 배포 상태를 관리하는 구조를 구성하였다.

**핵심 목표는 Docker 이미지 자체의 성능 최적화보다, 재현 가능한 컨테이너 실행 환경을 확보하고 Kubernetes 기반 장애 복구 실험에 활용하는 것이다.**

---

## 2. 분석 대상

Google Online Boutique의 주요 서비스 중 Frontend, ProductCatalog, Checkout, Payment의 Dockerfile을 분석하였다.

| 서비스 | 주요 역할 | 프로젝트 활용 |
| --- | --- | --- |
| frontend | 사용자 요청 진입점 | 직접 이미지 빌드, ECR 연동, gRPC 재연결 개선 |
| productcatalogservice | 상품 정보 제공 | Pod Failure 및 자동 복구 실험 |
| checkoutservice | 주문 흐름 조정 | 서비스 의존 관계 및 실행 구조 분석 |
| paymentservice | 결제 처리 | Dockerfile 분석 및 배포 실패 시나리오 초기 설계 |

### 실제 구현 범위

초기에는 Frontend의 Resource Exhaustion과 PaymentService의 잘못된 버전 배포를 계획하였다.

그러나 최종 장애 실험에서는 Online Boutique의 정상 서비스에 미치는 영향을 최소화하기 위해 별도의 `recovery-test` Namespace에 ProductCatalog 기반 실험 리소스를 구성하였다.

따라서 실제 구현 범위는 다음과 같이 구분한다.

- **frontend:** Docker 이미지 직접 빌드, 로컬 기능 검증, GitHub Actions 및 ECR 연동
- **productcatalogservice:** 기존 공식 이미지를 활용한 Pod 복구, HPA, 배포 실패 실험
- **checkoutservice:** Dockerfile 및 서비스 의존 관계 분석
- **paymentservice:** Dockerfile 분석, 배포 장애 실험 대상에서는 제외

---

## 3. Docker 이미지 설계 개요

### 3.1 Multi-stage Build

Online Boutique의 분석 대상 Dockerfile은 Build 단계와 Runtime 단계를 분리하는 Multi-stage Build 구조를 사용한다.

```
Application Source
        │
        ▼
Build Stage
        │
        ├── Dependency 설치
        ├── Source Code 복사
        └── Binary / Runtime Dependency 생성
        │
        ▼
Runtime Stage
        │
        ├── 실행에 필요한 파일 복사
        └── Application 실행
        │
        ▼
Container Image
```

Build 단계에서는 애플리케이션 컴파일에 필요한 도구와 라이브러리를 사용하며, Runtime 단계에는 실제 실행에 필요한 구성요소만 포함한다.

이 구조를 통해 이미지 크기와 실행 환경의 복잡도를 줄일 수 있다.

### 3.2 서비스별 Runtime 설계

| 구분 | Go 기반 서비스 | Node.js 기반 서비스 |
| --- | --- | --- |
| 대상 | frontend, productcatalogservice, checkoutservice | paymentservice |
| Build 환경 | Go Alpine | Node Alpine |
| Runtime 환경 | Distroless | Alpine + Node.js |
| 실행 방식 | 컴파일된 Binary 실행 | Node.js 애플리케이션 실행 |
| 최적화 방향 | 불필요한 Build Tool 제거 | Production Dependency 중심 구성 |

### 3.3 Docker와 Kubernetes 역할 구분

Docker는 애플리케이션과 실행에 필요한 환경을 이미지로 패키징한다.

Kubernetes는 해당 이미지를 이용하여 Pod를 생성하고, Deployment·ReplicaSet·Probe 등을 통해 실행 상태를 관리한다.

```
Dockerfile
    ↓
Docker Image
    ↓
Container Registry
    ↓
Kubernetes Deployment
    ↓
Pod / Container 실행
```

따라서 Docker 이미지 빌드와 Kubernetes의 자동 복구는 서로 다른 역할이며, 본 프로젝트에서는 두 기능을 연계하여 검증하였다.

---

## 4. 서비스별 Dockerfile 분석

### 4.1 frontend

#### 역할

사용자 요청을 최초로 수신하고 상품 조회, 장바구니, 주문 등의 기능을 제공하는 Go 기반 Frontend 서비스이다.

여러 Backend Microservices와 통신하므로 사용자 관점의 응답 회복을 관찰하기에 중요한 서비스이다.

#### Docker 구성

| 항목 | 분석 내용 |
| --- | --- |
| 언어 | Go |
| Build Image | `golang:1.27.0-alpine` |
| Runtime Image | `gcr.io/distroless/static` |
| Build 방식 | Multi-stage Build |
| Dependency | `go.mod`, `go.sum` |
| Dependency 설치 | `go mod download` |
| 실행 파일 | `/src/server` |
| Container Port | 8080 |
| Dockerfile 환경 변수 | `GOTRACEBACK=single` |

#### Build 흐름

```
go.mod / go.sum
        ↓
go mod download
        ↓
Source Code Copy
        ↓
Go Binary Build
        ↓
/go/bin/frontend
        ↓
Distroless Runtime
        ↓
/src/server 실행
```

#### 이미지 최적화 요소

- Multi-stage Build 적용
- Alpine 기반 Build Image 사용
- Distroless Runtime Image 사용
- Runtime Image에서 Build Tool 제거
- `CGO_ENABLED=0`을 통한 정적 빌드 구성
- `ldflags="-s -w"`를 통한 바이너리 크기 최적화
- Dependency 파일 우선 복사로 Docker Layer Cache 활용

#### 실제 프로젝트 적용

Frontend 이미지를 직접 빌드하여 로컬 Kubernetes에서 실행을 검증하였다.

이후 GitHub Actions를 이용한 이미지 빌드 및 Amazon ECR 연동을 구성하고, EKS의 Frontend Deployment에 프로젝트 전용 이미지를 적용하였다.

또한 gRPC 재연결 및 백오프 동작을 변경한 이미지의 배포를 검증하였다.

---

### 4.2 productcatalogservice

#### 역할

상품 목록과 상세 정보를 제공하는 Go 기반 서비스이다.

본 프로젝트에서 Pod Failure, ReplicaSet 자동 복구, HPA, 배포 실패 검증의 주요 실험 대상으로 활용하였다.

#### Docker 구성

| 항목 | 분석 내용 |
| --- | --- |
| 언어 | Go |
| Build Image | `golang:1.27.0-alpine` |
| Runtime Image | `gcr.io/distroless/static` |
| Build 방식 | Multi-stage Build |
| Dependency | `go.mod`, `go.sum` |
| 실행 파일 | `/src/server` |
| Container Port | 3550 |
| 추가 파일 | `products.json` |
| Dockerfile 환경 변수 | `GOTRACEBACK=single` |

#### Build 흐름

```
Go Source
    ↓
Dependency Download
    ↓
ProductCatalog Binary Build
    ↓
Distroless Runtime
    ↓
Binary + products.json
    ↓
/src/server 실행
```

#### 이미지 최적화 요소

- Multi-stage Build 적용
- Alpine 기반 Build Image
- Distroless Runtime Image
- Runtime에서 컴파일 도구 제외
- `CGO_ENABLED=0`
- `ldflags="-s -w"`
- Dependency Layer Cache 활용

#### 실제 프로젝트 적용

Pod 복구 및 HPA 테스트에서는 기존 공식 이미지를 사용하였다.

```
us-central1-docker.pkg.dev/online-boutique-ci/microservices-demo/productcatalogservice:v0.10.7
```

공식 이미지를 활용하여 Docker 이미지 자체의 변경 없이 Kubernetes의 자동 복구 및 확장 기능을 검증할 수 있도록 구성하였다.

ProductCatalog 실험용 Deployment에는 CPU/Memory Request 및 Limit과 gRPC Readiness/Liveness Probe를 적용하였다.

---

### 4.3 checkoutservice

#### 역할

장바구니, 상품 조회, 결제, 배송 및 이메일 서비스와 통신하여 주문 과정을 조정하는 Go 기반 서비스이다.

여러 마이크로서비스에 의존하므로 서비스 간 연결 관계와 장애 영향 범위를 분석하는 데 활용하였다.

#### Docker 구성

| 항목 | 분석 내용 |
| --- | --- |
| 언어 | Go |
| Build Image | `golang:1.27.0-alpine` |
| Runtime Image | `gcr.io/distroless/static` |
| Build 방식 | Multi-stage Build |
| Dependency | `go.mod`, `go.sum` |
| 실행 파일 | `/src/checkoutservice` |
| Container Port | 5050 |
| Dockerfile 환경 변수 | `GOTRACEBACK=single` |

#### Build 흐름

```
Go Source
    ↓
go mod download
    ↓
CheckoutService Binary Build
    ↓
Distroless Runtime
    ↓
/src/checkoutservice 실행
```

#### 이미지 최적화 요소

- Multi-stage Build
- Alpine 기반 Build Image
- Distroless Runtime
- 정적 Go Binary
- Runtime Build Tool 제거
- `CGO_ENABLED=0`
- `ldflags="-s -w"`

#### 실제 프로젝트 적용

CheckoutService는 Dockerfile 구조와 서비스 의존 관계를 분석하고, Online Boutique의 정상 주문 흐름을 확인하는 데 활용하였다.

별도의 CheckoutService 전용 이미지 최적화 또는 장애 복구 성능 실험은 수행하지 않았다.

---

### 4.4 paymentservice

#### 역할

Checkout 과정에서 결제 처리를 담당하는 Node.js 기반 서비스이다.

초기에는 잘못된 버전 배포 및 Rollback 실험 대상으로 계획하였다.

#### Docker 구성

| 항목 | 분석 내용 |
| --- | --- |
| 언어 | Node.js |
| Build Image | `node:24.20.0-alpine` |
| Runtime Image | `alpine:3.24.1` |
| Build 방식 | Multi-stage Build |
| Dependency | `npm install --only=production` |
| 실행 명령어 | `node index.js` |
| Container Port | 50051 |
| Build Dependency | `python3`, `make`, `g++` |

#### Build 흐름

```
package.json / package-lock.json
        ↓
Production Dependency 설치
        ↓
node_modules 생성
        ↓
Runtime Alpine Image
        ↓
Node.js 설치
        ↓
Source + node_modules 복사
        ↓
node index.js 실행
```

#### 이미지 최적화 요소

- Build 및 Runtime 단계 분리
- Production Dependency 중심 구성
- Runtime에서 Build Tool 제외
- Alpine 기반 Runtime 사용
- Package Cache 최소화

#### 실제 프로젝트 적용

PaymentService의 Dockerfile 및 실행 구조를 분석하였다.

다만 최종 Deployment Failure 실험에서는 PaymentService의 잘못된 이미지를 생성하는 대신, ProductCatalog 전용 Deployment의 Readiness Probe 포트 오류를 이용하여 실패 상황을 재현하였다.

따라서 PaymentService 전용 `v2-broken` 이미지를 실제 배포한 것으로 기록하지 않는다.

---

## 5. 서비스별 Dockerfile 비교

| 항목 | frontend | productcatalogservice | checkoutservice | paymentservice |
| --- | --- | --- | --- | --- |
| 언어 | Go | Go | Go | Node.js |
| Build 환경 | Go Alpine | Go Alpine | Go Alpine | Node Alpine |
| Runtime 환경 | Distroless | Distroless | Distroless | Alpine |
| Multi-stage | 적용 | 적용 | 적용 | 적용 |
| Port | 8080 | 3550 | 5050 | 50051 |
| Dependency | Go Modules | Go Modules | Go Modules | npm |
| Dockerfile 분석 | 완료 | 완료 | 완료 | 완료 |
| 직접 이미지 빌드 검증 | 완료 | 공식 이미지 활용 | 별도 검증 없음 | 별도 검증 없음 |
| 장애 테스트 활용 | gRPC 복구 | Pod/HPA/Rollout | 의존 관계 분석 | 초기 계획 |

---

## 6. 기존 Dockerfile 평가

### 6.1 분석 결과

Google Online Boutique의 주요 Dockerfile에는 다음과 같은 이미지 최적화 방식이 적용되어 있었다.

- Multi-stage Build
- Build / Runtime 환경 분리
- 경량 Alpine 이미지 활용
- Distroless Runtime Image 사용
- 실행 환경에서 불필요한 Build Tool 제거
- Production Dependency 중심 구성
- Go Binary 정적 빌드 및 크기 최적화

### 6.2 설계 판단

기존 Dockerfile에 이미 경량화 및 실행 환경 분리 구조가 적용되어 있었기 때문에 모든 서비스의 Dockerfile을 전면 재작성하지 않았다.

대신 Frontend를 중심으로 이미지 직접 빌드와 Kubernetes 배포를 검증하고, 다른 서비스는 기존 공식 이미지를 활용하여 장애 복구 실험에 집중하였다.

### 6.3 검증 한계

이번 프로젝트에서는 Docker 이미지 최적화 전후의 이미지 크기, 빌드 시간, 취약점 수 또는 실행 성능을 별도로 정량 비교하지 않았다.

따라서 Multi-stage Build와 Distroless 구조의 설계상 장점은 분석했지만, 프로젝트에서 이미지 크기나 빌드 시간을 실제로 개선했다고 주장하지 않는다.

---

## 7. 이미지 관리 및 CI/CD 연계

### 7.1 최종 이미지 관리 구조

```
Developer
    │
    ▼
GitHub Repository
    │
    ▼
GitHub Actions
    │
    ├── Source 확인
    ├── Docker Image Build
    └── Amazon ECR Push
                │
                ▼
         Amazon ECR
                │
                ▼
      Kubernetes Manifest
                │
                ▼
             Argo CD
                │
                ▼
         AWS EKS Cluster
                │
                ▼
        Frontend Deployment
```

GitHub Actions는 이미지 빌드와 ECR 업로드를 담당한다.

Argo CD는 Git 저장소의 Kubernetes Manifest를 기준으로 Deployment 상태를 동기화한다.

다만 이미지 빌드, ECR 업로드, Manifest 이미지 변경, Argo CD 배포는 서로 다른 처리 단계이며, 모든 단계가 단일 워크플로에서 자동 수행되는지 여부는 CI/CD 설계서의 실제 워크플로를 기준으로 확인한다.

### 7.2 Container Registry

최종 Container Registry로 Amazon ECR을 사용하였다.

**Frontend 이미지 저장소**

```
007053125976.dkr.ecr.ap-northeast-2.amazonaws.com/k8s-auto-recovery/frontend
```

**k6 이미지 저장소**

```
007053125976.dkr.ecr.ap-northeast-2.amazonaws.com/k8s-auto-recovery/k6
```

Frontend는 애플리케이션 배포용 이미지를 저장하고, k6는 EKS 내부 부하 테스트용 이미지를 저장하는 용도로 사용하였다.

### 7.3 이미지 태그 관리

초기에는 로컬 환경에서 이미지 빌드 및 실행 검증을 위해 다음 태그를 사용하였다.

```
frontend:local-v1
```

EKS 배포에서는 Git Commit 기반 이미지 식별 방식을 적용하였다.

Git Commit 기반 태그는 빌드 결과와 소스 코드 버전을 연결하고, 배포된 이미지의 출처를 추적하는 데 활용한다.

**실제 프로젝트에서 확인한 Frontend 이미지 식별자**

```
6c523ad28c5229d97c18de05b0a3d2c1bf2bb9d8
```

이는 테스트 과정에서 확인된 Frontend 이미지에 사용된 Git SHA 기반 태그이며, 이후 이미지 교체 및 배포 이력 분석의 기준으로 활용할 수 있다.

### 7.4 초기 계획과 변경 사항

| 초기 계획 | 최종 적용 |
| --- | --- |
| Container Registry 선정 예정 | Amazon ECR 선택 |
| Frontend 로컬 이미지 빌드 | 완료 |
| GitHub Actions 이미지 빌드 | 구성 완료 |
| Argo CD 연동 | 구성 완료 |
| Git SHA 기반 이미지 관리 | 적용 |
| PaymentService v2-broken 이미지 | 미사용 |
| 전체 서비스 이미지 재빌드 | 수행하지 않음 |

---

## 8. Kubernetes 연계 설계

### 8.1 이미지 실행 환경과 Kubernetes 설정

Dockerfile은 애플리케이션 이미지의 실행 환경을 정의하며, Kubernetes Manifest는 실제 Pod 운영 조건을 정의한다.

| 항목 | Dockerfile | Kubernetes Manifest |
| --- | --- | --- |
| Base Image | 정의 | 이미지 참조 |
| Build 과정 | 정의 | 직접 관리하지 않음 |
| 실행 명령 | 정의 가능 | 필요 시 재정의 |
| 환경 변수 | 기본값 설정 가능 | Deployment에서 설정·재정의 |
| 컨테이너 포트 | 문서화 가능 | containerPort 및 Service 연결 |
| CPU/Memory | 일반적으로 별도 운영 설정 | Request / Limit |
| Readiness Probe | 일반적으로 별도 운영 설정 | Pod 준비 상태 확인 |
| Liveness Probe | 일반적으로 별도 운영 설정 | 컨테이너 상태 확인 |
| Replica 수 | 해당 없음 | Deployment |
| HPA | 해당 없음 | CPU 기반 Replica 조정 |

### 8.2 ProductCatalog 실험 환경

ProductCatalog 테스트용 Deployment에는 다음과 같은 실행 조건을 적용하였다.

| 항목 | 설정 |
| --- | --- |
| Image | 공식 ProductCatalog v0.10.7 |
| Application Port | 3550 |
| CPU Request | 100m |
| CPU Limit | 200m |
| Memory Request | 64Mi |
| Memory Limit | 128Mi |
| Readiness Probe | gRPC 3550 |
| Liveness Probe | gRPC 3550 |
| 실행 사용자 | Non-root |
| Root Filesystem | Read-only |

이를 통해 컨테이너 이미지 변경 없이 Kubernetes의 ReplicaSet 자동 복구, HPA 및 배포 실패 대응을 검증할 수 있었다.

### 8.3 이미지 버전과 GitOps 상태 관리

로컬에서 `kubectl set image`를 직접 실행하면 Kubernetes의 실제 Deployment 설정과 Git에 저장된 Manifest 사이에 차이가 생길 수 있다.

이에 EKS 환경에서는 Git을 기준으로 이미지 버전과 Kubernetes Manifest를 관리하고, Argo CD를 통해 배포 상태를 동기화하는 방향으로 구성하였다.

---

## 9. 설계 결론

Online Boutique의 Dockerfile은 Multi-stage Build와 경량 Runtime Image를 사용하여 Build와 실행 환경이 분리된 구조를 제공한다.

기존 Dockerfile을 분석하고 Frontend 이미지를 직접 빌드하여 로컬 Kubernetes에서 정상 동작을 검증하였다.

이후 GitHub Actions와 Amazon ECR을 연동하고, Argo CD 기반 배포 구조를 구성하였다.

또한 ProductCatalog의 기존 공식 이미지를 활용해 이미지 변경과 Kubernetes 장애 복구 기능을 분리하여 검증하였다.

**Docker 설계의 핵심은 컨테이너 실행 환경을 일관되게 구성하고, 이미지 버전을 추적할 수 있도록 관리하여 Kubernetes 배포 및 장애 대응의 기반을 마련하는 데 있다.**

---

## 10. 구현 및 검증 결과

### 10.1 구현 목적

Dockerfile을 통해 생성한 이미지가 Kubernetes 환경에서 정상적으로 실행되는지 확인하고, 이미지 빌드부터 Registry 저장 및 Kubernetes 배포까지의 연결 과정을 검증한다.

### 10.2 구현 환경

| 항목 | 실제 구성 |
| --- | --- |
| 개발 환경 | Windows PowerShell |
| Docker | Docker Desktop |
| 로컬 Kubernetes | Docker Desktop Kubernetes |
| Cloud Kubernetes | Amazon EKS 1.35 |
| 애플리케이션 | Google Online Boutique v0.10.7 |
| 직접 빌드 대상 | frontend |
| 로컬 이미지 태그 | frontend |
| Cloud Registry | Amazon ECR |
| CI | GitHub Actions |
| CD | Argo CD |
| 추가 실험용 이미지 | Grafana k6 2.2.0 |

### 10.3 주요 구현 과정

**① 기존 Dockerfile 분석**

```
Get-Content .\src\frontend\Dockerfile
```

Frontend의 Base Image, Multi-stage Build, 환경 변수, 실행 파일 및 Port 구성을 확인하였다.

**② Frontend 이미지 직접 빌드**

```
docker build -t frontend:local-v1 .\src\frontend
```

**③ 이미지 생성 확인**

```
docker images frontend
```

**④ 로컬 Kubernetes 이미지 적용**

```
kubectl set image deployment/frontend <container-name>=frontend:local-v1
```

위 명령은 로컬 이미지 교체 검증 단계에서 사용한 형식이며, 실제 실행 시에는 Kubernetes Deployment의 컨테이너 이름 및 Namespace가 일치해야 한다.

**⑤ 배포 및 Pod 상태 확인**

```
kubectl rollout status deployment/frontend
kubectl get pods
```

**⑥ Frontend 기능 확인**

```
kubectl port-forward deployment/frontend 8080:8080
```

브라우저에서 애플리케이션에 접속하여 상품 조회, 장바구니 및 주문 기능을 검증하였다.

**⑦ Amazon ECR 로그인 및 이미지 Push**

Frontend는 GitHub Actions 기반 빌드·푸시 흐름을 구성하였다.

별도로 EKS 내부 k6 테스트를 위해 Docker 이미지를 ECR에 업로드하였다.

```
docker pull --platform linux/amd64 grafana/k6:2.2.0
```

EKS Worker Node 아키텍처에 맞춰 Linux amd64 이미지를 사용하였다.

이후 ECR에 인증하고 테스트용 k6 이미지를 Push하였다.

**⑧ Kubernetes Job에서 이미지 사용**

ECR에 저장한 k6 이미지를 참조하는 Kubernetes Job을 생성하여 EKS 내부에서 gRPC 부하 테스트를 실행하였다.

### 10.4 검증 결과

| 검증 항목 | 결과 |
| --- | --- |
| Frontend Dockerfile 분석 | 완료 |
| Frontend 이미지 로컬 빌드 | 성공 |
| 로컬 Kubernetes 이미지 교체 | 성공 |
| Frontend Pod Running / Ready | 확인 |
| 장바구니 기능 | 정상 |
| 모의 주문 기능 | 정상 |
| Amazon ECR 연동 | 성공 |
| GitHub Actions CI | 구성 및 빌드·푸시 연동 |
| Argo CD 배포 상태 | Synced / Healthy |
| ECR k6 이미지 | Push 성공 |
| EKS 내부 k6 Job | 정상 실행 |
| gRPC 요청 테스트 | 성공 |
| HPA OFF/ON 테스트 | 각 18,001건, 오류율 0% |

### 10.5 구현 과정에서 확인한 문제

**① Windows PowerShell ECR 인증 오류**

PowerShell에서 ECR 인증 정보를 Docker 로그인 명령어로 전달하는 과정에서 오류가 발생하였다.

`cmd /c` 방식으로 인증 파이프라인을 실행하여 로그인에 성공하였다.

**② k6 gRPC Proto 파일 로딩 오류**

k6 실행 환경에서 Proto 파일의 상대 경로가 일치하지 않아 파일 로딩 오류가 발생하였다.

ConfigMap에 Proto 파일과 테스트 스크립트를 포함하고, 실제 실행 경로에 맞춰 파일 참조를 수정하였다.

**③ 이미지 아키텍처 확인**

EKS Worker Node에서 실행 가능한 이미지 아키텍처를 고려하여 Linux amd64 기반 k6 이미지를 사용하였다.

### 10.6 최종 평가 및 개선 방향

이번 프로젝트에서는 Frontend 이미지를 직접 빌드하고 Kubernetes에 적용했으며, GitHub Actions 및 ECR 연동을 통해 Cloud 환경의 이미지 관리 구조를 구성하였다.

또한 k6 이미지를 별도로 ECR에 저장하고 Kubernetes Job으로 실행하여 부하 테스트 환경까지 확장하였다.

다만 이미지 최적화 전후 크기, 빌드 시간, 취약점 수 등은 정량적으로 비교하지 않았다.

향후 개선 방향은 다음과 같다.

- Docker 이미지 크기 및 빌드 시간 비교
- 이미지 취약점 스캔 도입
- 이미지 버전 및 Digest 기반 추적 강화
- 서비스별 이미지 빌드 파이프라인 표준화
- CI/CD 실패 시 이미지 및 배포 검증 절차 강화

### 최종 결론

**기존 Dockerfile을 분석하는 단계에서 시작해 이미지 직접 빌드, Amazon ECR 저장, GitHub Actions 자동화 및 Kubernetes 배포까지 연계하였다. 이를 통해 컨테이너 이미지를 단순한 실행 파일이 아니라 버전 추적과 배포 안정성을 확보하기 위한 운영 구성요소로 관리하는 과정을 검증하였다.**
