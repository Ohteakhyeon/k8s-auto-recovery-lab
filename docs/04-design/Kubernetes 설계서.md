## 1. 문서 목적

Online Boutique 기존 Kubernetes Manifest를 분석하고 프로젝트 목표인 장애 탐지·자동 복구·자원 확장·배포 안정성 검증에 맞게 Kubernetes 구조를 재설계한다.

**주요 설계 대상**

- Deployment
- Service
- Namespace
- ConfigMap / Secret
- Resource Request / Limit
- Readiness / Liveness Probe
- HPA
- Self-Healing
- ServiceAccount
- 외부 노출 방식

---

## 2. 설계 목표

### 2.1 핵심 목표

- 애플리케이션을 Kubernetes 환경에 안정적으로 배포
- Pod 장애 발생 시 자동 복구
- 비정상 Pod에 대한 트래픽 차단
- CPU 부하 증가 시 HPA 기반 자동 확장
- Resource Request / Limit을 통한 자원 제어
- 서비스 간 통신 구조 유지
- 장애 실험이 가능하도록 설정값 명확화
- Prometheus 기반 상태 관측이 가능하도록 구성

### 2.2 프로젝트 검증 항목

| 검증 항목 | 관련 Kubernetes 기능 |
| --- | --- |
| Pod 장애 자동 복구 | Deployment / ReplicaSet |
| 비정상 Pod 트래픽 차단 | Readiness Probe |
| 비정상 Container 재시작 | Liveness Probe |
| CPU 부하 대응 | HPA |
| 자원 고갈 통제 | Resource Request / Limit |
| 내부 서비스 통신 | Service / ClusterIP |
| 외부 사용자 접근 | LoadBalancer 또는 Ingress |

---

## 3. 분석 대상 서비스

| 서비스 | 역할 | 프로젝트 활용 |
| --- | --- | --- |
| `frontend` | 사용자 요청 진입점 | Resource Exhaustion / HPA |
| `productcatalogservice` | 상품 정보 제공 | Pod Failure / Self-Healing |
| `checkoutservice` | 주문 흐름 조정 | 장애 전파 분석 |
| `paymentservice` | 결제 처리 | Deployment Failure / Rollback |

---

# 4. 기존 Kubernetes Manifest 분석

## 4.1 frontend

### 기존 설정

| 항목 | 설정 |
| --- | --- |
| Workload | Deployment |
| Replica | 1 |
| Image | `frontend` |
| Container Port | 8080 |
| 내부 Service | ClusterIP |
| 외부 Service | LoadBalancer |
| Readiness Probe | HTTP `/_healthz` |
| Liveness Probe | HTTP `/_healthz` |
| CPU Request | 100m |
| CPU Limit | 200m |
| Memory Request | 64Mi |
| Memory Limit | 128Mi |
| HPA | 없음 |
| ServiceAccount | `frontend` |

### 프로젝트 판단

| 항목 | 판단 |
| --- | --- |
| Deployment | 유지 |
| Readiness Probe | 유지 |
| Liveness Probe | 유지 |
| Resource 설정 | 실험 결과에 따라 조정 |
| Replica | HPA 적용을 고려해 재설계 |
| HPA | 직접 추가 |
| 외부 Service | AWS/EKS 구조에 맞게 재검토 |
| SecurityContext | 유지 |

### 활용 계획

Resource Exhaustion 테스트 대상으로 활용한다.

```
Traffic 증가
↓
frontend CPU 증가
↓
HPA 조건 충족
↓
Replica 증가
↓
P95 / Error Rate 변화 확인
```

---

## 4.2 productcatalogservice

### 기존 설정

| 항목 | 설정 |
| --- | --- |
| Workload | Deployment |
| Replica | 1 |
| Image | `productcatalogservice` |
| Container Port | 3550 |
| Service | ClusterIP |
| Readiness Probe | gRPC |
| Liveness Probe | gRPC |
| terminationGracePeriodSeconds | 5 |
| CPU Request | 100m |
| CPU Limit | 200m |
| Memory Request | 64Mi |
| Memory Limit | 128Mi |
| HPA | 없음 |

### 프로젝트 판단

| 항목 | 판단 |
| --- | --- |
| Replica | Pod Failure Baseline으로 우선 1 유지 |
| Readiness Probe | 유지 |
| Liveness Probe | 유지 |
| Grace Period | 장애 테스트에서 영향 확인 |
| HPA | 우선 미적용 |
| Service | ClusterIP 유지 |
| Resource | 기본값 유지 후 필요 시 조정 |

### 활용 계획

Pod Failure 실험 대상으로 활용한다.

```
Pod 강제 삭제
↓
Replica 부족 발생
↓
Deployment Controller 감지
↓
새 Pod 생성
↓
gRPC Readiness 성공
↓
Service 정상 복귀
```

---

## 4.3 checkoutservice

### 기존 설정

| 항목 | 설정 |
| --- | --- |
| Workload | Deployment |
| Replica | 1 |
| Port | 5050 |
| Service | ClusterIP |
| Readiness Probe | gRPC |
| Liveness Probe | gRPC |
| CPU Request | 100m |
| CPU Limit | 200m |
| Memory Request | 64Mi |
| Memory Limit | 128Mi |

### 의존 서비스

```
productcatalogservice
shippingservice
paymentservice
emailservice
currencyservice
cartservice
```

### 프로젝트 판단

- 기존 Deployment 구조 유지
- Probe 유지
- HPA 우선 미적용
- 장애 실험의 직접 대상보다는 장애 전파 확인 지점으로 활용
- paymentservice 장애가 checkout 요청에 미치는 영향 관찰

---

## 4.4 paymentservice

### 기존 설정

| 항목 | 설정 |
| --- | --- |
| Workload | Deployment |
| Replica | 1 |
| Image | `paymentservice` |
| Port | 50051 |
| Service | ClusterIP |
| Readiness Probe | gRPC |
| Liveness Probe | gRPC |
| terminationGracePeriodSeconds | 5 |
| CPU Request | 100m |
| CPU Limit | 200m |
| Memory Request | 64Mi |
| Memory Limit | 128Mi |

### 프로젝트 판단

| 항목 | 판단 |
| --- | --- |
| Deployment | 유지 |
| Probe | 유지 |
| HPA | 우선 미적용 |
| Image | Registry + 명시적 Tag 적용 |
| Rollback | Argo CD와 연계 |
| Service | ClusterIP 유지 |

### 활용 계획

잘못된 배포 시나리오에 활용한다.

```
paymentservice:v1
↓
paymentservice:v2-broken 배포
↓
Checkout Error 증가
↓
장애 감지
↓
Rollback
↓
정상 버전 복구
```

---

# 5. 공통 Kubernetes 리소스 설계

## 5.1 Namespace

프로젝트 리소스를 다른 환경과 분리하기 위해 전용 Namespace를 사용한다.

예정:

```
metadata:
  name: online-boutique
```

선정 이유:

- 리소스 논리적 분리
- 모니터링 대상 구분
- 운영 명령 단순화
- 향후 ResourceQuota 적용 가능

---

## 5.2 Deployment

Deployment는 애플리케이션의 원하는 Replica 상태를 유지한다.

주요 역할:

- Pod 생성
- Pod 장애 시 자동 재생성
- Rolling Update
- Replica 관리

본 프로젝트에서는 Self-Healing 검증의 핵심 리소스로 사용한다.

---

## 5.3 Service

내부 마이크로서비스 통신에는 `ClusterIP`를 사용한다.

```
frontend
↓
productcatalogservice:3550
```

와 같이 Service DNS를 사용하여 Pod IP 변경과 무관하게 통신하도록 구성한다.

외부 접근 방식은 AWS/EKS 설계 단계에서 최종 결정한다.

후보:

- LoadBalancer Service
- Ingress + AWS Load Balancer Controller

---

# 6. Resource Request / Limit 설계

초기에는 기존 Online Boutique 설정을 Baseline으로 활용한다.

| 항목 | 초기값 |
| --- | --- |
| CPU Request | 100m |
| CPU Limit | 200m |
| Memory Request | 64Mi |
| Memory Limit | 128Mi |

단, Resource Exhaustion 테스트 결과를 바탕으로 값을 조정한다.

### 설정 목적

**Request**

Scheduler가 Pod를 배치할 때 필요한 최소 자원 판단에 사용.

**Limit**

컨테이너가 사용할 수 있는 최대 자원을 제한.

Resource 설정 변경 전후 다음 지표를 비교한다.

- CPU Usage
- CPU Throttling
- Memory Usage
- OOM 여부
- P95 Latency
- Error Rate

---

# 7. Readiness / Liveness Probe 설계

## Readiness Probe

목적:

> Pod가 사용자 요청을 처리할 준비가 되었는지 확인
> 

실패 시:

```
Pod Running
하지만
Service Endpoint에서 제외
```

프로젝트에서는 **서비스 복구 완료 시점**을 판단하는 중요한 기준으로 사용한다.

## Liveness Probe

목적:

> 애플리케이션 프로세스가 정상적으로 동작하는지 확인
> 

지속적인 실패 시 Container를 재시작한다.

### 서비스별 Probe

| 서비스 | Probe 방식 |
| --- | --- |
| frontend | HTTP |
| productcatalogservice | gRPC |
| checkoutservice | gRPC |
| paymentservice | gRPC |

---

# 8. HPA 설계

Resource Exhaustion 실험을 위해 우선 `frontend`에 HPA를 적용한다.

초기 설계 예시:

| 항목 | 값 |
| --- | --- |
| 대상 | frontend |
| minReplicas | 2 |
| maxReplicas | 6 |
| 기준 | CPU Utilization |
| Target | TBD |

Target CPU 값은 Baseline 부하 테스트 이후 결정한다.

### 예상 동작

```
Traffic 증가
↓
CPU 사용률 상승
↓
HPA Target 초과
↓
frontend Replica 증가
↓
부하 분산
↓
Latency/Error Rate 안정화
```

---

# 9. Self-Healing 설계

프로젝트에서 Self-Healing은 하나의 기능이 아니라 여러 Kubernetes 기능의 조합으로 본다.

### Pod 자체 삭제

```
Pod 삭제
↓
Deployment의 Desired Replica 불일치
↓
ReplicaSet이 새 Pod 생성
```

### 애플리케이션 비정상

```
Liveness Probe 실패
↓
Container Restart
```

### 아직 요청 처리가 불가능한 Pod

```
Readiness Probe 실패
↓
Service Endpoint 제외
```

따라서 장애 복구 실험에서는 각 기능을 구분하여 측정한다.

---

# 10. SecurityContext 설계

기존 Online Boutique의 보안 설정을 유지한다.

주요 설정:

```
runAsNonRoot: true
allowPrivilegeEscalation: false
privileged: false
capabilities.drop: ALL
readOnlyRootFilesystem: true
```

유지 이유:

- Root 권한 실행 방지
- 불필요한 Linux Capability 제거
- Privilege Escalation 방지
- Container FileSystem 변조 최소화

---

# 11. ConfigMap / Secret 설계

기존 manifest는 다수의 서비스 연결 정보를 `env` 값으로 직접 관리하고 있다.

프로젝트에서는 설정 성격에 따라 다음과 같이 분리 여부를 검토한다.

### ConfigMap 후보

- 서비스 주소
- 일반 애플리케이션 설정
- 환경 구분 값

### Secret 후보

- 인증 정보
- Token
- Credential
- 외부 서비스 Secret

실제 민감정보가 없는 Online Boutique 기본 설정은 모두 Secret으로 옮길 필요는 없음.

---

# 12. 이미지 관리 설계

기존:

```
image: frontend
```

프로젝트 적용 후 예:

```
image: ghcr.io/<user>/frontend:<git-sha>
```

이미지 태그는 CI/CD 설계서에서 최종 확정한다.

목표:

- 어떤 Commit이 배포되었는지 추적 가능
- Rollback 용이
- `latest` 의존 제거

---

# 13. 변경 항목 정리

| 항목 | 기존 | 프로젝트 적용 |
| --- | --- | --- |
| Namespace | 기본 | 전용 Namespace 적용 |
| frontend Replica | 1 | HPA 기반 관리 |
| HPA | 없음 | frontend 추가 |
| Probe | 존재 | 유지 |
| Resource | 존재 | Baseline 후 조정 |
| Service | ClusterIP/LoadBalancer | 내부 ClusterIP 유지, 외부 방식 재설계 |
| Image Tag | 단순 이름 | Registry + Git SHA/버전 |
| Monitoring | 기본 없음 | Prometheus 연계 |
| Rollback | 별도 없음 | Argo CD 연계 |
| Alert | 없음 | Prometheus Alert 설계 |

---

# 14. 장애 시나리오와 Kubernetes 기능 연결

| 장애 시나리오 | 대상 | Kubernetes 기능 | 측정 지표 |
| --- | --- | --- | --- |
| Pod Failure | productcatalogservice | Deployment / ReplicaSet / Readiness | MTTR, Pod Ready Time, Error Rate |
| Resource Exhaustion | frontend | Resource / HPA | CPU, Replica, P95, Error Rate |
| Deployment Failure | paymentservice | Deployment / Probe / Argo CD | Error Rate, Rollback Time, MTTR |

---

# 15. 검증 계획

Kubernetes 설계 적용 후 다음을 검증한다.

### 정상 상태

```
Pod Running
Pod Ready
Service Endpoint 정상
```

### Pod 장애

```
kubectl delete pod <pod-name>
```

확인:

- 새 Pod 생성 여부
- Ready 복귀 시간
- 서비스 Error Rate
- MTTR

### Resource 부하

k6를 이용하여 Traffic을 증가시킨다.

확인:

- CPU Usage
- HPA 동작
- Replica 변화
- P95
- Error Rate

### Deployment 실패

오류 버전의 paymentservice를 배포한다.

확인:

- 사용자 요청 실패
- 장애 감지 시간
- Rollback 시간
- 정상화 시간

---

# 16. 미확정 항목

설계 단계에서 아직 확정하지 않은 값은 억지로 결정하지 않고 `TBD`로 관리한다.

| 항목 | 상태 |
| --- | --- |
| HPA CPU Target | TBD |
| frontend min/max Replica | Baseline Test 후 확정 |
| 최종 Resource 값 | Baseline Test 후 확정 |
| 외부 노출 방식 | AWS 아키텍처 설계 후 확정 |
| Registry | CI/CD 설계 단계에서 확정 |
| Namespace 명칭 | 확정 예정 |

---

# 17. 최종 설계 결론

Online Boutique의 기존 Kubernetes Manifest에는 Deployment, Service, Resource Request/Limit, Readiness/Liveness Probe, SecurityContext 등 기본적인 운영 설정이 이미 적용되어 있다.

따라서 프로젝트에서는 기존 Manifest를 전면 재작성하기보다 이를 Baseline으로 활용하고, 프로젝트 목표에 맞게 다음 항목을 추가·변경한다.

```
HPA
+ Image Version 관리
+ Prometheus Monitoring
+ Argo CD
+ 장애 복구 검증
+ 장애 측정 지표
```

이를 통해 단순한 Kubernetes 배포가 아니라 **장애 발생 시 상태를 감지하고 자동으로 복구하며, 그 효과를 정량적으로 측정할 수 있는 운영 환경**을 구축하는 것을 목표로 한다.
