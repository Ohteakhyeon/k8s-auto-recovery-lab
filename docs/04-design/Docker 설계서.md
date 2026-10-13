## 1. 문서 목적

Google Online Boutique의 핵심 마이크로서비스에 적용된 Dockerfile 구조를 분석하고, 컨테이너 이미지의 빌드 방식·실행 환경·최적화 요소를 확인한다.

애플리케이션 자체를 새로 개발하기보다, 기존 오픈소스의 컨테이너 구조를 이해하고 이를 Kubernetes 기반 장애 복구 실험에 활용하는 것을 목표로 함.

---

## 2. 분석 대상

| 서비스 | 주요 역할 | 프로젝트 활용 |
| --- | --- | --- |
| frontend | 사용자 요청 진입점 | Resource Exhaustion 실험 |
| productcatalogservice | 상품 정보 제공 | Pod Failure 실험 |
| checkoutservice | 주문 흐름 조정 | 서비스 의존성 및 장애 전파 분석 |
| paymentservice | 결제 처리 | Deployment Failure 및 Rollback 실험 |

---

## 3. Docker 이미지 설계 개요

Online Boutique의 주요 서비스는 **Multi-stage Build**를 사용하여 Build 환경과 Runtime 환경을 분리하고 있다.

Go 기반 서비스는 Build 단계에서 `golang:alpine` 이미지를 사용하고, 최종 실행 단계에서는 `distroless/static` 이미지를 사용한다.

Node.js 기반 `paymentservice`는 Build 단계에서 `node:alpine`을 사용하고, Runtime 단계에서는 Alpine 이미지에 Node.js만 설치하여 실행 환경을 최소화한다.

```
Application Source
       ↓
Build Stage
       ↓
Dependency Install
       ↓
Binary / Runtime Dependency 생성
       ↓
Runtime Stage
       ↓
필요한 파일만 복사
       ↓
Container Image
```

---

## 4. 서비스별 Dockerfile 분석

### 4.1 frontend

#### 역할

사용자 요청을 최초로 받아 여러 마이크로서비스를 호출하는 웹 Frontend 서비스

| 항목 | 내용 |
| --- | --- |
| 언어 | Go |
| Build Image | `golang:1.27.0-alpine` |
| Runtime Image | `gcr.io/distroless/static` |
| Build 방식 | Multi-stage Build |
| Dependency | `go.mod`, `go.sum` → `go mod download` |
| 실행 파일 | `/src/server` |
| Container Port | `8080` |
| Dockerfile 환경변수 | `GOTRACEBACK=single` |

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
Distroless Runtime으로 복사
       ↓
/src/server 실행
```

#### 이미지 최적화 요소

- Multi-stage Build 적용
- Alpine 기반 Build Image 사용
- Distroless Runtime Image 사용
- Build Tool을 Runtime Image에서 제거
- `CGO_ENABLED=0` 적용
- `ldflags="-s -w"`를 통한 바이너리 크기 감소
- Dependency 파일을 먼저 복사하여 Docker Layer Cache 활용

---

### 4.2 productcatalogservice

#### 역할

상품 목록과 상품 정보를 제공하는 서비스로, Pod Failure 장애 실험 대상으로 활용한다.

#### Docker 구성

| 항목 | 내용 |
| --- | --- |
| 언어 | Go |
| Build Image | `golang:1.27.0-alpine` |
| Runtime Image | `gcr.io/distroless/static` |
| Build 방식 | Multi-stage Build |
| Dependency | `go.mod`, `go.sum` → `go mod download` |
| 실행 파일 | `/src/server` |
| Container Port | `3550` |
| 추가 파일 | `products.json` |
| Dockerfile 환경변수 | `GOTRACEBACK=single` |

#### Build 흐름

```
Go Source
    ↓
Dependency Download
    ↓
productcatalogservice Binary Build
    ↓
Distroless Runtime
    ↓
Binary + products.json 복사
    ↓
/src/server 실행
```

#### 이미지 최적화 요소

- Multi-stage Build
- Alpine 기반 Build Image
- Distroless Runtime Image
- Build Tool 제외
- `CGO_ENABLED=0`
- `ldflags="-s -w"`
- Dependency Layer Cache 활용

---

### 4.3 checkoutservice

#### 역할

장바구니, 상품, 결제, 배송, 이메일 등의 여러 서비스를 호출하여 주문 과정을 조정하는 서비스이다.

서비스 간 의존 관계가 많기 때문에 장애 전파를 분석하기에 중요한 서비스이다.

#### Docker 구성

| 항목 | 내용 |
| --- | --- |
| 언어 | Go |
| Build Image | `golang:1.27.0-alpine` |
| Runtime Image | `gcr.io/distroless/static` |
| Build 방식 | Multi-stage Build |
| Dependency | `go.mod`, `go.sum` → `go mod download` |
| 실행 파일 | `/src/checkoutservice` |
| Container Port | `5050` |
| Dockerfile 환경변수 | `GOTRACEBACK=single` |

#### Build 흐름

```
Go Source
    ↓
go mod download
    ↓
checkoutservice Binary Build
    ↓
Distroless Runtime
    ↓
/src/checkoutservice 실행
```

#### 이미지 최적화 요소

- Multi-stage Build
- Alpine 기반 Build Image
- Distroless Runtime
- 정적 Binary 구성
- Build Tool 제거
- `CGO_ENABLED=0`
- `ldflags="-s -w"`

---

### 4.4 paymentservice

#### 역할

Checkout 과정에서 결제 처리를 담당하는 Node.js 기반 서비스이다.

잘못된 버전 배포 및 Rollback 실험 대상으로 활용할 예정

#### Docker 구성

| 항목 | 내용 |
| --- | --- |
| 언어 | Node.js |
| Build Image | `node:24.20.0-alpine` |
| Runtime Image | `alpine:3.24.1` |
| Build 방식 | Multi-stage Build |
| Dependency | `npm install --only=production` |
| 실행 파일 | `node index.js` |
| Container Port | `50051` |
| Build Dependency | `python3`, `make`, `g++` |

#### Build 흐름

```
package.json
package-lock.json
       ↓
Production Dependency 설치
       ↓
node_modules 생성
       ↓
Runtime Alpine Image
       ↓
Node.js 설치
       ↓
node_modules + Source Copy
       ↓
node index.js 실행
```

#### 이미지 최적화 요소

- Build Stage와 Runtime Stage 분리
- Runtime에 Build Tool을 포함하지 않음
- Production Dependency만 설치
- Alpine 기반 Runtime 사용
- `-no-cache` 옵션을 활용하여 불필요한 Package Cache 제거

---

## 5. 서비스별 비교

| 항목 | frontend | productcatalogservice | checkoutservice | paymentservice |
| --- | --- | --- | --- | --- |
| 언어 | Go | Go | Go | Node.js |
| Build Image | Go Alpine | Go Alpine | Go Alpine | Node Alpine |
| Runtime Image | Distroless | Distroless | Distroless | Alpine |
| Multi-stage | O | O | O | O |
| Port | 8080 | 3550 | 5050 | 50051 |
| Dependency | Go Modules | Go Modules | Go Modules | npm |
| 주요 실험 | Resource Exhaustion | Pod Failure | 장애 전파 | Deployment Failure |

---

## 6. 기존 Dockerfile 평가

분석 결과 Online Boutique의 핵심 서비스 Dockerfile에는 이미 다음과 같은 컨테이너 이미지 최적화 방식이 적용되어 있다.

- Multi-stage Build
- Build/Runtime 환경 분리
- 경량 Alpine 이미지 활용
- Distroless Runtime 활용
- Runtime Image에서 Build Tool 제거
- 운영에 필요한 Dependency만 포함
- Go Binary 크기 최적화

따라서 프로젝트에서는 Dockerfile 자체를 전면 재작성하기보다, 기존 Dockerfile 구조를 유지하면서 Kubernetes 기반 배포 및 장애 복구 실험에 집중한다.

필요할 경우 장애 실험 또는 CI/CD 테스트를 위해 일부 서비스 이미지만 별도로 수정하여 사용할 예정

---

## 7. 이미지 관리 계획

컨테이너 이미지는 CI 과정에서 빌드하고 Container Registry에 저장한다.

초기 계획은 다음과 같다.

```
Source Code
    ↓
GitHub Actions
    ↓
Docker Build
    ↓
Container Registry
    ↓
Kubernetes Deployment
```

이미지 태그는 향후 CI/CD 설계 단계에서 최종 결정하며, 최소한 `latest`만 사용하는 방식은 피하고 버전 또는 Git Commit 기반 태그를 적용할 예정

예:

```
frontend:v1.0.0
frontend:<git-sha>
paymentservice:v1.0.0
paymentservice:v2-broken
```

`paymentservice:v2-broken`과 같은 테스트용 이미지는 Deployment Failure 시나리오에서 활용할 수 있다.

---

## 8. Kubernetes 연계 시 확인 사항

Dockerfile 분석 이후 Kubernetes Manifest에서 다음 설정을 추가로 확인

- Container Image
- Container Port
- 환경변수
- Resource Request / Limit
- Readiness Probe
- Liveness Probe
- Replica 수
- Service 연결
- HPA 적용 여부

특히 Dockerfile의 `ENV`만으로는 서비스 전체 환경변수를 확인할 수 없으므로, Kubernetes Deployment의 `env` 설정을 별도로 분석한다.

---

## 9. 설계 결론

Online Boutique의 Dockerfile은 이미 운영 환경을 고려한 Multi-stage Build와 경량 Runtime 구조를 사용하고 있어 이미지 최적화 수준이 높은 편이다.

프로젝트에서는 이를 그대로 활용하되, 컨테이너 이미지를 Kubernetes 환경에 배포하고 장애 상황에서의 Self-Healing, Resource Scaling, Deployment Rollback을 검증하는 데 중점을 둔다.
