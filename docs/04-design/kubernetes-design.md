| 버전 | 변경 내용 | 상태 |
| --- | --- | --- |
| v0.1 | Online Boutique Kubernetes Manifest 분석 및 설계 | 완료 |
| v0.2 | Namespace, Kustomize, 이미지 관리 및 로컬 배포 검증 | 완료 |
| v0.3 | Pod Failure 및 로컬 Self-Healing 사전 검증 | 완료 |
| v0.4 | AWS EKS 클러스터 및 Worker Node 기본 동작 검증 | 완료 |
| v0.5 | EKS Online Boutique 배포, Probe 및 HPA 구성 반영 | 완료 |
| v1.0 | Pod 자동 복구, HPA, 배포 실패 및 Rollback 실측 결과 반영 | 최종 |

---

## 1. 문서 목적

Google Online Boutique의 기존 Kubernetes Manifest를 분석하고, AWS EKS 기반 애플리케이션 운영 환경에 적용한 Kubernetes 리소스 구성과 장애 대응 기능을 정의한다.

Deployment, ReplicaSet, Service, Resource Request/Limit, Readiness/Liveness Probe, HPA 등의 기능을 활용하여 애플리케이션의 정상 상태를 유지하고 장애 상황에 대응할 수 있도록 구성하였다.

또한 실제 장애 상황을 재현하여 Kubernetes의 자동 복구, CPU 기반 자동 확장, 비정상 배포 차단 및 수동 Rollback 기능을 검증하였다.

**핵심 목적은 Kubernetes 리소스를 단순히 생성하는 것이 아니라, 장애 발생 시 각 구성요소가 어떤 역할을 수행하고 정상 상태를 어떻게 회복하는지 확인하는 것이다.**

---

## 2. 설계 목표

### 2.1 핵심 목표

- Online Boutique 마이크로서비스의 안정적인 배포
- Deployment와 ReplicaSet을 통한 Pod 상태 유지
- Pod 강제 삭제 시 자동 재생성 검증
- Readiness Probe를 통한 비정상 Pod 식별
- Liveness Probe를 통한 컨테이너 상태 점검
- CPU 기반 HPA Scale-out / Scale-in
- Resource Request / Limit을 통한 자원 관리
- Kubernetes Service 기반 내부 통신 유지
- Rolling Update 및 Rollback 검증
- Prometheus 기반 운영 상태 관측
- 수동·자동 Pod 복구 시간 정량 비교

### 2.2 기능별 검증 결과

| 검증 항목 | Kubernetes 기능 | 실제 결과 |
| --- | --- | --- |
| 애플리케이션 배포 | Deployment | 11개 Deployment 정상 실행 |
| Pod 자동 복구 | ReplicaSet | 삭제된 Pod 대체 생성 |
| 비정상 Pod 식별 | Readiness Probe | 신규 Pod NotReady 확인 |
| 컨테이너 상태 점검 | Liveness Probe | 설정 적용, 별도 재시작 실험 미실시 |
| CPU 기반 자동 확장 | HPA | Replica 1 → 2 |
| 자동 축소 | HPA | Replica 2 → 1 |
| 내부 통신 | Service / ClusterIP | gRPC 요청 정상 |
| 배포 실패 감지 | Deployment | ProgressDeadlineExceeded |
| 배포 복구 | Rollback | 수동 Rollback 성공 |
| 장애 관측 | PrometheusRule | Firing 확인 |

---

## 3. 분석 대상 서비스

| 서비스 | 역할 | 프로젝트 활용 |
| --- | --- | --- |
| frontend | 사용자 요청 진입점 | 이미지 배포, gRPC 재연결 개선 |
| productcatalogservice | 상품 정보 제공 | Pod Failure 및 Self-Healing |
| checkoutservice | 주문 흐름 조정 | 서비스 의존 관계 분석 |
| paymentservice | 결제 처리 | 초기 배포 실패 시나리오 분석 |

### 실제 장애 실험 대상

기존 Online Boutique 리소스를 직접 변경하는 대신, `recovery-test` Namespace에 독립된 실험 리소스를 구성하였다.

| 실험 리소스 | 역할 |
| --- | --- |
| productcatalog-manual | 수동 Pod 복구 실험 |
| productcatalog-auto | ReplicaSet 자동 복구 및 HPA |
| productcatalog-hpa | k6 gRPC 요청을 전달하는 ClusterIP Service |
| productcatalog-rollout | Readiness 실패 및 Rollback 실험 |
| alert-test-pod | Prometheus NotReady 알림 검증 |

이를 통해 기존 Online Boutique 서비스의 정상 상태를 유지하면서 장애를 재현하였다.

---

# 4. 기존 Kubernetes Manifest 분석

## 4.1 frontend

### 기존 설정

| 항목 | 설정 |
| --- | --- |
| Workload | Deployment |
| Replica | 1 |
| Container Port | 8080 |
| 내부 Service | ClusterIP |
| 외부 Service | LoadBalancer |
| Readiness Probe | HTTP `/_healthz` |
| Liveness Probe | HTTP `/_healthz` |
| CPU Request / Limit | 100m / 200m |
| Memory Request / Limit | 64Mi / 128Mi |
| HPA | 기본 Manifest에 없음 |
| ServiceAccount | frontend |

### 실제 프로젝트 적용

Frontend의 기존 Deployment 구조와 Probe 설정을 활용하였다.

로컬 Kubernetes에서는 직접 빌드한 Frontend 이미지를 적용하고 상품 조회, 장바구니 및 모의 주문 기능을 검증하였다.

AWS EKS에서는 GitHub Actions로 빌드한 이미지를 Amazon ECR에 저장하고, Argo CD가 관리하는 Kubernetes Manifest를 통해 배포하였다.

또한 Frontend의 gRPC 재연결 및 백오프 동작을 개선한 후 사용자 관점의 HTTP 정상 응답 회복 시간을 측정하였다.

### 검증 결과

| 항목 | 결과 |
| --- | --- |
| 로컬 이미지 적용 | 성공 |
| EKS Frontend 실행 | 정상 |
| Argo CD 배포 상태 | Synced / Healthy |
| 개선 전 HTTP 회복 시간 | 25.740초 |
| 개선 후 HTTP 회복 평균 | 6.389초 |

개선 전 1회, 개선 후 3회 측정이므로 결과의 원인을 단정하지 않고 실측값으로 기록하였다.

---

## 4.2 productcatalogservice

### 기존 설정

| 항목 | 설정 |
| --- | --- |
| Workload | Deployment |
| Replica | 1 |
| Container Port | 3550 |
| Service | ClusterIP |
| Readiness Probe | gRPC |
| Liveness Probe | gRPC |
| terminationGracePeriodSeconds | 5 |
| CPU Request / Limit | 100m / 200m |
| Memory Request / Limit | 64Mi / 128Mi |
| HPA | 기본 Manifest에 없음 |

### 실제 프로젝트 적용

ProductCatalog는 상품 정보를 제공하는 핵심 서비스로, Pod 자동 복구 실험의 기준 애플리케이션으로 선정하였다.

로컬 Kubernetes에서는 기존 Pod를 삭제한 뒤 ReplicaSet이 새 Pod를 생성하고 Service Endpoint가 갱신되는 것을 확인하였다.

AWS EKS에서는 `recovery-test` Namespace에 별도의 ProductCatalog Deployment를 구성하고 수동 복구와 자동 복구를 비교하였다.

또한 ProductCatalog 기반 HPA와 배포 실패 실험을 수행하였다.

### 검증 결과

- Pod 강제 삭제 후 ReplicaSet 자동 재생성
- 신규 Pod Ready 도달 시간 측정
- CPU 기반 HPA 자동 확장
- gRPC Readiness 실패 재현
- Rolling Update 실패 및 수동 Rollback

---

## 4.3 checkoutservice

### 기존 설정

| 항목 | 설정 |
| --- | --- |
| Workload | Deployment |
| Replica | 1 |
| Container Port | 5050 |
| Service | ClusterIP |
| Readiness Probe | gRPC |
| Liveness Probe | gRPC |
| CPU Request / Limit | 100m / 200m |
| Memory Request / Limit | 64Mi / 128Mi |

### 서비스 의존 관계

CheckoutService는 장바구니, 상품 조회, 결제, 배송 및 이메일 서비스와 통신하여 주문 처리 과정을 조정한다.

### 실제 프로젝트 적용

기존 Deployment 및 Probe 구조를 유지하였다.

로컬 Kubernetes에서 장바구니와 모의 주문 기능을 검증하여 주요 서비스 간 연결이 정상 동작하는 것을 확인하였다.

다만 CheckoutService를 직접 대상으로 하는 장애 전파 및 복구 시간 측정은 수행하지 않았다.

---

## 4.4 paymentservice

### 기존 설정

| 항목 | 설정 |
| --- | --- |
| Workload | Deployment |
| Replica | 1 |
| Container Port | 50051 |
| Service | ClusterIP |
| Readiness Probe | gRPC |
| Liveness Probe | gRPC |
| terminationGracePeriodSeconds | 5 |
| CPU Request / Limit | 100m / 200m |
| Memory Request / Limit | 64Mi / 128Mi |

### 초기 계획

PaymentService의 잘못된 버전을 배포하여 Checkout 요청 실패와 Rollback 과정을 검증할 계획이었다.

### 최종 변경 사항

실제 배포 실패 실험에서는 PaymentService가 아닌 별도의 `productcatalog-rollout` Deployment를 사용하였다.

Readiness Probe 포트를 의도적으로 잘못 설정하여 신규 Pod를 NotReady 상태로 유지하고, Rolling Update의 기존 정상 Pod 유지 및 수동 Rollback 동작을 검증하였다.

따라서 PaymentService의 잘못된 이미지를 실제 배포하거나 Checkout 오류율을 측정한 것으로 기록하지 않는다.

---

# 5. 공통 Kubernetes 리소스 설계

## 5.1 Namespace

Kubernetes 리소스를 목적에 따라 구분하고 장애 테스트의 영향을 최소화하기 위해 Namespace를 분리하였다.

| Namespace | 역할 |
| --- | --- |
| online-boutique | Online Boutique 애플리케이션 |
| recovery-test | 장애 복구 및 부하 테스트 |
| monitoring | Prometheus, Grafana, Alertmanager |
| argocd | GitOps 배포 관리 |
| kube-system | Kubernetes 시스템 구성요소 |

### Namespace 생성

```
kubectl create namespace online-boutique
kubectl get namespaces
```

### Kustomize를 이용한 Namespace 관리

서비스별 Manifest에 Namespace를 반복 지정하는 대신 Kustomize를 활용하였다.

```
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: online-boutique

resources:
  - adservice.yaml
  - cartservice.yaml
  - checkoutservice.yaml
  - currencyservice.yaml
  - emailservice.yaml
  - frontend.yaml
  - paymentservice.yaml
  - productcatalogservice.yaml
  - recommendationservice.yaml
  - shippingservice.yaml
```

위 내용은 주요 마이크로서비스 Manifest를 나타낸 예시이며, 실제 배포 구성에는 Redis 관련 리소스도 포함된다.

### 실제 EKS 적용

EKS에서는 `kubernetes/overlays/eks`를 Argo CD Application의 배포 경로로 사용하였다.

Kustomize와 Argo CD를 결합하여 Git에 선언된 Namespace와 이미지 구성을 기준으로 애플리케이션을 관리하였다.

---

## 5.2 Deployment

Deployment는 원하는 Pod 수와 Pod Template을 선언하는 리소스이다.

Kubernetes는 Deployment 하위에 ReplicaSet을 생성하고, ReplicaSet을 통해 지정된 Pod 수를 유지한다.

### 실제 배포 결과

| 항목 | 결과 |
| --- | --- |
| 애플리케이션 | Online Boutique v0.10.7 |
| Namespace | online-boutique |
| Deployment | 11개 |
| 정상 상태 | 11개 Pod Running / Ready |
| 관리 방식 | Kustomize + Argo CD |
| Argo CD | Synced / Healthy |

### 상태 확인

```
kubectl get deployments -n online-boutique
kubectl get pods -n online-boutique
```

### 설계 특징

Online Boutique의 기본 Deployment 구조를 유지하면서, 장애 테스트는 별도의 Namespace에 독립된 Deployment를 생성하여 수행하였다.

이를 통해 기존 애플리케이션을 안정적으로 운영하면서 ReplicaSet 및 HPA 동작을 검증하였다.

---

## 5.3 Service

Kubernetes Service는 Pod IP가 변경되더라도 애플리케이션이 안정적인 주소를 통해 통신할 수 있도록 한다.

### 적용 구조

| 영역 | Service 방식 | 활용 |
| --- | --- | --- |
| Online Boutique 내부 | ClusterIP | 마이크로서비스 간 통신 |
| 로컬 Frontend 접근 | port-forward | 브라우저 기능 검증 |
| ProductCatalog 부하 테스트 | ClusterIP | EKS 내부 k6 gRPC 요청 |
| 외부 LoadBalancer | 초기 Manifest 분석 | 최종 실험에서 필수 경로로 사용하지 않음 |

### 실제 부하 테스트 경로

```
k6 Job
   │
   ▼
productcatalog-hpa Service
   │
   ▼
productcatalog-auto Pod
   │
   ▼
ProductCatalog gRPC 3550
```

ProductCatalog Service는 Pod 이름이나 IP가 아닌 `app=productcatalog-auto` 라벨을 기준으로 요청 대상을 선택하도록 구성하였다.

### 검증 결과

EKS 내부 k6 Job에서 ClusterIP Service를 통해 ProductCatalog gRPC API를 정상 호출하였다.

HPA OFF/ON 각각 18,001건의 요청을 성공적으로 처리하였다.

다만 신규 Pod로 요청이 실제로 어느 정도 분산됐는지는 별도로 정량화하지 않았다.

---

## 5.4 AWS EKS Kubernetes 환경

### 인프라 구성

| 항목 | 실제 구성 |
| --- | --- |
| EKS Cluster | auto-recovery-eks |
| Kubernetes | 1.35 |
| Region | ap-northeast-2 |
| Node 관리 | EKS Managed Node Group |
| Worker Node | t3.large × 2 |
| Operating System | Amazon Linux 2023 |
| Container Runtime | containerd |
| VPC | 10.0.0.0/16 |
| Node Subnet | Public Subnet 2개 |
| Network | AWS VPC CNI |
| Metrics API | Metrics Server EKS Add-on |

### 클러스터 연결

```
aws eks update-kubeconfig `
  --region ap-northeast-2 `
  --name auto-recovery-eks `
  --profile k8s-lab
```

### Node 확인

```
kubectl get nodes -o wide
```

### 시스템 Pod 확인

```
kubectl get pods -n kube-system
```

### 최종 검증 결과

- EKS API 연결 성공
- Worker Node 2개 Ready
- CoreDNS, kube-proxy, VPC CNI 정상 실행
- Metrics Server 정상 동작
- Online Boutique 11개 Deployment 정상 실행
- Argo CD Application Synced / Healthy 확인

초기 v0.4에서는 EKS 기본 구축까지만 검증했으나, 최종 단계에서는 실제 Online Boutique 배포 및 장애 테스트까지 진행하였다.

---

# 6. Resource Request / Limit 설계

## 6.1 기본 설정

ProductCatalog 실험용 Deployment의 Resource 설정은 다음과 같다.

| 항목 | 값 |
| --- | --- |
| CPU Request | 100m |
| CPU Limit | 200m |
| Memory Request | 64Mi |
| Memory Limit | 128Mi |

### Kubernetes Resource 설정

```
resources:
  requests:
    cpu: 100m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 128Mi
```

## 6.2 Request와 Limit의 역할

**Request**

Scheduler가 Pod를 Node에 배치할 때 참고하는 자원 요구량이다.

CPU 기반 HPA에서는 CPU Request가 사용률 계산의 기준으로 사용된다.

**Limit**

컨테이너가 사용할 수 있는 자원의 상한을 지정한다.

CPU Limit 초과 시 CPU Throttling이 발생할 수 있으며, Memory Limit 초과 시 OOM으로 인해 컨테이너가 종료될 수 있다.

## 6.3 실제 프로젝트 적용

ProductCatalog의 CPU Request를 100m로 설정하고, HPA 목표 CPU Utilization을 60%로 지정하였다.

즉, HPA가 참조하는 CPU 사용률 기준은 CPU Limit이 아니라 CPU Request이다.

### 검증 결과

k6 부하를 발생시킨 결과 HPA가 CPU 사용률 상승을 감지하여 Replica를 1개에서 2개로 확장하였다.

다만 CPU Throttling이나 OOM 발생을 의도적으로 유도하여 별도의 복구 시간을 측정하지는 않았다.

---

# 7. Readiness / Liveness Probe 설계

## 7.1 Readiness Probe

Readiness Probe는 Pod가 요청을 처리할 준비가 되었는지 확인한다.

Readiness Probe가 실패하면 해당 Pod는 Ready 상태가 아니며, 일반적인 Kubernetes Service의 요청 대상에서 제외된다.

### ProductCatalog 적용 설정

```
readinessProbe:
  grpc:
    port: 3550
  periodSeconds: 10
  timeoutSeconds: 1
  failureThreshold: 3
```

### 실제 검증

배포 실패 테스트에서 Readiness Probe의 gRPC 포트를 의도적으로 `3551`로 변경하였다.

```
readinessProbe:
  grpc:
    port: 3551
  periodSeconds: 5
  timeoutSeconds: 1
  failureThreshold: 3
```

애플리케이션은 정상 포트인 3550에서 실행 중이었으므로 신규 Pod가 Ready 상태에 도달하지 못하였다.

**검증 결과**

- 기존 정상 Pod: `1/1 Running`
- 신규 잘못된 Pod: `0/1 Running`
- 기존 정상 Pod 유지 확인

---

## 7.2 Liveness Probe

Liveness Probe는 실행 중인 컨테이너의 정상 동작 여부를 확인한다.

설정된 횟수 이상 실패하면 kubelet이 해당 컨테이너를 재시작할 수 있다.

### 적용 설정

```
livenessProbe:
  grpc:
    port: 3550
  periodSeconds: 10
  timeoutSeconds: 1
  failureThreshold: 3
```

### 검증 범위

Liveness Probe 설정이 적용된 것은 확인하였다.

하지만 Liveness 실패를 의도적으로 발생시켜 kubelet의 컨테이너 재시작 시간이나 서비스 영향 범위를 측정하는 독립 실험은 수행하지 않았다.

따라서 Liveness 기반 복구 시간은 이번 프로젝트의 정량 성과에 포함하지 않는다.

---

## 7.3 Probe 역할 비교

| 구분 | Readiness Probe | Liveness Probe |
| --- | --- | --- |
| 목적 | 요청 처리 준비 상태 확인 | 컨테이너 정상 동작 확인 |
| 실패 시 동작 | Service 요청 대상에서 제외 | 조건 충족 시 컨테이너 재시작 |
| Pod 재생성 | 직접 수행하지 않음 | 직접 수행하지 않음 |
| 프로젝트 활용 | 배포 실패 실험 | 정상 설정 적용 |
| 별도 실패 실험 | 수행 | 미수행 |

---

# 8. HPA 설계

## 8.1 설계 목적

CPU 사용률 증가 시 Kubernetes가 Pod Replica 수를 자동으로 조정하는지 검증한다.

초기에는 Frontend를 대상으로 HPA를 적용할 계획이었으나, 최종 실험에서는 독립된 ProductCatalog Deployment를 사용하였다.

## 8.2 실제 HPA 설정

| 항목 | 실제 설정 |
| --- | --- |
| HPA | productcatalog-auto |
| Target Deployment | productcatalog-auto |
| Namespace | recovery-test |
| minReplicas | 1 |
| maxReplicas | 3 |
| Metric | CPU Utilization |
| Target | 60% |
| CPU Request | 100m |

### HPA YAML

```
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: productcatalog-auto
  namespace: recovery-test
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: productcatalog-auto
  minReplicas: 1
  maxReplicas: 3
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
```

## 8.3 자동 확장 흐름

```
k6 gRPC 부하 증가
        ↓
ProductCatalog CPU 사용률 증가
        ↓
Metrics Server 메트릭 제공
        ↓
HPA Controller CPU 사용률 평가
        ↓
Desired Replica 증가
        ↓
Deployment / ReplicaSet
        ↓
신규 Pod 생성
```

## 8.4 HPA 동작 검증

상태 확인 명령어:

```
kubectl get hpa -n recovery-test

kubectl describe hpa productcatalog-auto -n recovery-test

kubectl top pods -n recovery-test
```

실제 이벤트:

```
SuccessfulRescale
New size: 2
reason: cpu resource utilization above target
```

### 검증 결과

- 초기 Replica: 1개
- 부하 증가 후 Replica: 2개
- 부하 종료 후 Replica: 1개
- CPU 기반 자동 확장·축소 확인

## 8.5 HPA OFF/ON 성능 비교

EKS 내부 k6 Job에서 동일한 부하를 발생시켰다.

| 항목 | HPA OFF | HPA ON |
| --- | --- | --- |
| 테스트 시간 | 180초 | 180초 |
| 목표 RPS | 100 | 100 |
| 총 요청 | 18,001 | 18,001 |
| 평균 gRPC 응답 | 0.853ms | 0.921ms |
| P95 | 1.25ms | 1.38ms |
| 오류율 | 0% | 0% |

### 분석

HPA의 CPU 기반 자동 확장·축소 기능은 정상 동작하였다.

그러나 해당 부하 조건에서는 HPA ON 상태의 P95 응답시간 개선이 나타나지 않았다.

기존 gRPC 연결을 재사용하는 방식 때문에 신규 Pod로 요청이 충분히 분산되지 않았을 가능성이 있으며, Pod 1개로도 100 RPS를 정상 처리했다는 점에서 부하 수준의 한계도 존재한다.

따라서 이번 실험은 **HPA 자동 확장 기능 검증 성공, 성능 개선 효과 미입증**으로 평가하였다.

---

# 9. Self-Healing 설계

## 9.1 Kubernetes Self-Healing 구성

본 프로젝트에서는 Self-Healing을 단일 기능이 아니라 여러 Kubernetes 구성요소의 조합으로 정의하였다.

### Pod 삭제

```
Pod 삭제
    ↓
Desired Replica 수 불일치
    ↓
ReplicaSet Controller 감지
    ↓
새 Pod 생성
    ↓
Readiness Probe 통과
    ↓
Pod Ready
```

### 컨테이너 비정상

```
Liveness Probe 실패
    ↓
kubelet이 컨테이너 재시작
```

### 요청 처리 준비 실패

```
Readiness Probe 실패
    ↓
Pod NotReady
    ↓
Service 요청 대상에서 제외
```

각 기능은 서로 다른 장애 상황에 대응하므로 역할과 복구 범위를 구분하여 설계하였다.

---

## 9.2 로컬 Kubernetes 사전 검증

Docker Desktop Kubernetes에서 ProductCatalog Pod를 강제로 삭제한 후 새 Pod가 생성되는 것을 확인하였다.

| 검증 항목 | 결과 |
| --- | --- |
| 대상 | productcatalogservice |
| 장애 방식 | kubectl delete pod |
| 새 Pod 생성 | 성공 |
| Readiness 복귀 | 성공 |
| Service Endpoint 갱신 | 확인 |
| 상품 조회 기능 | 정상 |
| 복구 시간 측정 | 미실시 |

이 단계에서는 Kubernetes Self-Healing 기능의 기본 동작을 확인하였다.

---

## 9.3 AWS EKS 수동/자동 복구 비교

EKS의 `recovery-test` Namespace에서 독립된 수동·자동 복구 실험 리소스를 사용하였다.

### 측정 결과

| 회차 | 수동 복구 | 자동 복구 |
| --- | --- | --- |
| 1회 | 34.358초 | 4.183초 |
| 2회 | 12.013초 | 4.144초 |
| 3회 | 10.933초 | 2.670초 |
| 평균 | **19.101초** | **3.666초** |

### 결과 분석

ReplicaSet 자동 복구 환경에서 Pod Ready 도달 시간이 평균 3.666초로 측정되었다.

이는 수동 복구 평균 19.101초 대비 약 80.8% 짧은 결과이다.

다만 수동 복구에는 운영자의 상태 확인과 명령 실행 과정이 포함되었고, 수동·자동 실험의 명령 옵션과 측정 조건이 완전히 동일하지 않았다.

따라서 해당 결과는 **Pod Ready 도달 시간 비교**이며, 서비스 전체 MTTR이나 가용성 향상 수치로 직접 해석하지 않는다.

---

## 9.4 Frontend 사용자 관점 복구

Pod Ready 상태와 실제 사용자 요청의 정상 회복 시점이 다를 수 있다는 점을 확인하기 위해 Frontend의 HTTP 응답 회복 시간도 측정하였다.

| 구분 | HTTP 정상 응답 회복 시간 |
| --- | --- |
| 개선 전 기준 측정 | 25.740초 |
| 개선 후 1회 | 6.415초 |
| 개선 후 2회 | 6.382초 |
| 개선 후 3회 | 6.369초 |
| 개선 후 평균 | 6.389초 |

Frontend의 gRPC 재연결 및 백오프 동작을 변경한 후 HTTP 정상 응답 회복 시간이 감소하였다.

다만 개선 전 1회와 개선 후 3회의 측정 결과이므로 추가 반복 실험 없이 개선 원인을 단정하지 않는다.

---

## 9.5 로컬 Kubernetes와 EKS 검증 범위

| 검증 항목 | Docker Desktop Kubernetes | AWS EKS |
| --- | --- | --- |
| Online Boutique 배포 | 완료 | 완료 |
| Pod 자동 재생성 | 확인 | 확인 |
| 서비스 기능 검증 | 장바구니/주문 | 기본 정상 실행 |
| 수동/자동 Ready 시간 | 미측정 | 각 3회 측정 |
| HPA 자동 확장 | 미검증 | 검증 |
| HPA OFF/ON 성능 | 미검증 | 검증 |
| 배포 실패 / Rollback | 미검증 | 검증 |
| Prometheus Alert | 미검증 | 검증 |

---

# 10. SecurityContext 설계

컨테이너 실행 권한을 제한하고 불필요한 권한 상승을 방지하기 위해 SecurityContext를 적용하였다.

### 주요 설정

```
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
```

컨테이너 수준 설정:

```
securityContext:
  allowPrivilegeEscalation: false
  privileged: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
```

### 적용 목적

- Root 사용자 실행 방지
- Privilege Escalation 제한
- 불필요한 Linux Capability 제거
- 컨테이너 파일 시스템 변경 제한
- 애플리케이션 실행 권한 최소화

### 실제 적용

ProductCatalog 자동 복구 실험용 Deployment에 Non-root 및 Read-only Root Filesystem 설정을 적용하였다.

해당 설정으로 Pod가 정상 실행되고 Ready 상태에 도달하는 것을 확인하였다.

단, 컨테이너 취약점 스캔이나 침투 테스트를 통한 보안 효과 검증은 수행하지 않았다.

---

# 11. ConfigMap / Secret 설계

## 11.1 설정 관리 방향

Kubernetes Manifest에는 서비스 연결 주소 및 실행 환경 변수 등이 포함된다.

일반 설정과 민감정보를 구분해 관리하는 것을 기본 방향으로 설정하였다.

| 구분 | 관리 대상 |
| --- | --- |
| ConfigMap | 서비스 주소, 일반 설정, 테스트 스크립트 |
| Secret | 비밀번호, 토큰, 자격 증명 등 민감정보 |

## 11.2 실제 ConfigMap 활용

k6를 EKS 내부에서 실행하기 위해 테스트 스크립트와 Proto 파일을 ConfigMap으로 구성하였다.

**ConfigMap 이름**

```
k6-hpa-scripts
```

**포함 파일**

- `demo.proto`
- `grpc-cluster-smoke.js`
- `grpc-load-test.js`

### ConfigMap 생성

```
kubectl create configmap k6-hpa-scripts `
  -n recovery-test `
  --from-file=demo.proto=.\tests\hpa\demo.proto `
  --from-file=grpc-cluster-smoke.js=.\tests\hpa\grpc-cluster-smoke.js `
  --from-file=grpc-load-test.js=.\tests\hpa\grpc-load-test.js `
  --dry-run=client -o yaml |
  kubectl apply -f -
```

### 실제 활용

ConfigMap을 k6 Job 컨테이너의 `/scripts` 디렉터리에 마운트하고, 해당 스크립트로 ProductCatalog gRPC 부하 테스트를 실행하였다.

## 11.3 Secret 관리

본 프로젝트에서는 AWS 인증에 IAM Identity Center 기반 SSO를 사용하였다.

Terraform State 및 실제 변수 파일은 Git 관리 대상에서 제외하였다.

다만 Kubernetes Secret 기반의 별도 인증 시스템을 구현하거나 External Secrets 연동을 검증하지는 않았다.

---

# 12. 이미지 관리 설계

## 12.1 기존 이미지 구성

Online Boutique의 기본 Manifest에는 다음과 같이 단순 이미지 이름을 사용하는 구성이 존재하였다.

```
image: frontend
```

프로젝트에서는 실제 Registry 경로와 이미지 버전을 명시적으로 관리하기 위해 Kustomize를 사용하였다.

---

## 12.2 로컬 Kubernetes 이미지 관리

로컬 Frontend 검증에서는 직접 빌드한 이미지를 사용하였다.

```
frontend:local-v1
```

나머지 서비스에는 공식 Online Boutique v0.10.7 이미지를 적용하였다.

### Kustomize 이미지 설정 예시

```
images:
  - name: frontend
    newName: frontend
    newTag: local-v1

  - name: paymentservice
    newName: us-central1-docker.pkg.dev/online-boutique-ci/microservices-demo/paymentservice
    newTag: v0.10.7
```

이를 통해 서비스별 원본 Manifest의 이미지 경로를 반복 수정하지 않고 배포 환경별 이미지 구성을 관리하였다.

---

## 12.3 AWS EKS 이미지 관리

EKS에서는 Amazon ECR을 사용하였다.

### Frontend 이미지 저장소

```
007053125976.dkr.ecr.ap-northeast-2.amazonaws.com/k8s-auto-recovery/frontend
```

### 이미지 관리 방식

- GitHub Actions에서 이미지 빌드 및 ECR Push
- Git Commit SHA 기반 이미지 식별
- Kubernetes Manifest에서 이미지 버전 지정
- Argo CD를 통한 GitOps 배포 관리

### 실제 검증

Frontend 이미지 빌드 및 EKS 적용을 확인하였다.

Argo CD Application은 `Synced / Healthy` 상태로 확인되었다.

---

## 12.4 ImagePullPolicy

로컬에서 직접 빌드한 이미지를 사용하는 과정에서는 다음 정책을 활용하였다.

```
imagePullPolicy: IfNotPresent
```

`IfNotPresent`는 Node에 이미지가 이미 존재하면 이를 사용하고, 없을 경우 Registry에서 가져오도록 하는 설정이다.

EKS에서도 이미지 태그와 Pull 정책이 배포 결과에 영향을 줄 수 있으므로 이미지 관리 전략을 명확히 하는 것이 중요하다.

---

# 13. 변경 항목 정리

| 항목 | 초기 설계 | 실제 구현 |
| --- | --- | --- |
| Namespace | online-boutique | online-boutique, recovery-test 등 분리 |
| Manifest 관리 | YAML / Kustomize | Kustomize + Argo CD |
| Image Registry | 선정 예정 | Amazon ECR |
| Frontend Image | local-v1 | 로컬 이미지 + ECR 이미지 |
| Replica | 기본 1개 | 기본값 유지, HPA 실험 별도 |
| Readiness / Liveness | 기본 설정 활용 | 적용 및 Readiness 실패 검증 |
| Resource | 기본값 유지 | 실험용 Request / Limit 명시 |
| HPA | frontend 적용 예정 | productcatalog-auto 적용 |
| HPA Target | TBD | CPU 60% |
| Monitoring | 미구성 | Prometheus / Grafana |
| Rollback | Argo CD 연계 예정 | kubectl rollout undo 검증 |
| EKS Cluster | 구축 예정 | EKS 1.35 구축 |
| Worker Node | 예정 | t3.large × 2 |
| Metrics Server | 미반영 | EKS Add-on 설치 |
| EKS Online Boutique | 미배포 | 11개 Deployment 정상 실행 |
| EKS 장애 테스트 | 예정 | Pod, HPA, Rollout, Alert 검증 |

---

# 14. 장애 시나리오와 Kubernetes 기능 연결

| 장애 시나리오 | 실제 대상 | Kubernetes 기능 | 검증 결과 |
| --- | --- | --- | --- |
| Pod Failure | productcatalog-manual / auto | ReplicaSet | 자동 복구 시간 측정 |
| HTTP 회복 지연 | frontend | Deployment, gRPC 연결 | 응답 회복 시간 비교 |
| CPU 부하 | productcatalog-auto | Metrics Server, HPA | Scale-out / Scale-in |
| 성능 비교 | ProductCatalog Service | Service, HPA, k6 | P95 / RPS / 오류율 |
| 배포 실패 | productcatalog-rollout | Readiness, Rolling Update | 신규 Pod NotReady |
| Rollback | productcatalog-rollout | Deployment Revision | 수동 복구 16.360초 |
| NotReady Alert | alert-test-pod | Pod Ready, PrometheusRule | Firing 확인 |

---

# 15. 검증 계획 및 실제 수행 결과

## 15.1 정상 상태

**검증 항목**

- Pod Running
- Pod Ready
- Deployment Available
- Service 연결
- Argo CD Synced / Healthy

**실제 결과**

Online Boutique 11개 Deployment가 정상 실행됐고 Argo CD Application이 Synced / Healthy 상태임을 확인하였다.

---

## 15.2 Pod Failure

**검증 방법**

Pod를 강제로 삭제하고 신규 Pod의 생성 및 Ready 도달 시간을 측정하였다.

```
kubectl delete pod <pod-name> -n recovery-test
```

**실제 결과**

- 수동 복구 평균: 19.101초
- 자동 복구 평균: 3.666초
- 평균 소요 시간 차이: 약 80.8% 단축

---

## 15.3 CPU 부하 / HPA

**검증 방법**

k6로 ProductCatalog gRPC 요청을 발생시키고 HPA의 Replica 변경을 관찰하였다.

**실제 결과**

- CPU 목표: 60%
- Replica: 1 → 2 → 1
- SuccessfulRescale 이벤트 확인
- HPA OFF/ON 각 18,001건 요청 성공

단, HPA의 성능 개선은 입증하지 못하였다.

---

## 15.4 Deployment Failure

**검증 방법**

Readiness Probe 포트를 잘못 지정한 신규 Revision을 배포하였다.

**실제 결과**

- 기존 Pod: 1/1 Ready 유지
- 신규 Pod: 0/1 Ready
- ProgressDeadlineExceeded 확인
- 수동 Rollback 성공
- Rollback 소요 시간: 16.360초

---

## 15.5 Monitoring Alert

**검증 방법**

Readiness Probe 오류가 있는 테스트용 Pod를 생성하고 PrometheusRule의 Firing을 확인하였다.

**실제 결과**

- 테스트 Pod NotReady 확인
- RecoveryTestPodNotReady Firing 확인
- Alertmanager 관련 알림 그룹 확인

알림 발생부터 수신까지의 지연 시간은 별도로 정량 측정하지 않았다.

---

# 16. 최종 구성 및 미검증 항목

## 16.1 최종 확정 구성

| 항목 | 설정 |
| --- | --- |
| Kubernetes | AWS EKS 1.35 |
| Region | ap-northeast-2 |
| Worker Node | t3.large × 2 |
| Manifest 관리 | Kustomize |
| GitOps CD | Argo CD |
| Container Registry | Amazon ECR |
| Pod 자동 복구 | Deployment / ReplicaSet |
| Probe | Readiness / Liveness |
| HPA 대상 | productcatalog-auto |
| HPA minReplicas | 1 |
| HPA maxReplicas | 3 |
| HPA CPU Target | 60% |
| Resource Metrics | Metrics Server |
| Monitoring | Prometheus / Grafana |
| Alerting | Alertmanager |

## 16.2 미검증 및 향후 개선 사항

| 항목 | 상태 |
| --- | --- |
| Pod 자동 재생성 | 검증 완료 |
| HPA 자동 확장·축소 | 검증 완료 |
| HPA 응답 성능 개선 | 미입증 |
| Readiness 실패 | 검증 완료 |
| Liveness 실패 후 자동 재시작 시간 | 미측정 |
| 수동 Rollback | 검증 완료 |
| 자동 Rollback | 미구현 |
| 전체 서비스 MTTD / MTTR | 정량 측정 미완료 |
| 실제 서비스 Availability | 정량 측정 미완료 |
| gRPC 신규 Pod 부하 분산 | 추가 검증 필요 |

---

# 17. 최종 설계 결론

본 프로젝트에서는 Online Boutique의 기존 Kubernetes Manifest를 분석하고, Kustomize와 Argo CD를 활용하여 AWS EKS 환경에 애플리케이션을 배포하였다.

또한 별도의 실험 Namespace에서 ReplicaSet 자동 복구, HPA, Readiness Probe 및 Rolling Update의 동작을 검증하였다.

Pod 자동 복구는 수동 방식보다 평균 Ready 도달 시간이 짧게 측정됐으며, HPA는 CPU 부하에 따라 Replica 수를 자동으로 조정하였다.

잘못된 배포에서는 신규 Pod가 Ready 상태에 도달하지 못했지만 기존 정상 Pod를 유지했고, 운영자의 수동 Rollback으로 정상 상태를 복원하였다.

**결국 Kubernetes 운영 안정성의 핵심은 Pod를 실행하는 것에 그치지 않고, Desired State와 실제 상태의 차이를 감지하고 정상 상태를 유지하도록 설계하는 데 있다.**

---

# 18. Kubernetes 구현 및 검증 결과

## 18.1 구현 환경

| 항목 | 내용 |
| --- | --- |
| 운영체제 | Windows |
| 로컬 Kubernetes | Docker Desktop Kubernetes |
| Cloud Kubernetes | AWS EKS |
| Kubernetes Version | 1.35 |
| 애플리케이션 | Online Boutique v0.10.7 |
| Registry | Amazon ECR 및 공식 Registry |
| Namespace | online-boutique / recovery-test |
| Manifest 관리 | Kustomize |
| CD | Argo CD |
| Monitoring | Prometheus / Grafana |

---

## 18.2 주요 구현 과정

**① Namespace 생성**

```
kubectl create namespace online-boutique
```

**② Kustomize Manifest 검증**

```
kubectl kustomize .\kubernetes\online-boutique\
```

**③ Dry-run 검증**

```
kubectl apply -k .\kubernetes\online-boutique\ --dry-run=client
```

**④ 로컬 Kubernetes 배포**

```
kubectl apply -k .\kubernetes\online-boutique\
```

**⑤ AWS EKS 연결**

```
aws eks update-kubeconfig `
  --region ap-northeast-2 `
  --name auto-recovery-eks `
  --profile k8s-lab
```

**⑥ Worker Node 확인**

```
kubectl get nodes -o wide
```

**⑦ Online Boutique 상태 확인**

```
kubectl get deployments -n online-boutique
kubectl get pods -n online-boutique
```

**⑧ Argo CD 배포 상태 확인**

```
kubectl get application online-boutique -n argocd
```

**⑨ CPU 메트릭 확인**

```
kubectl top nodes
kubectl top pods -n recovery-test
```

**⑩ HPA 상태 확인**

```
kubectl get hpa -n recovery-test
kubectl describe hpa productcatalog-auto -n recovery-test
```

**⑪ Rollback 수행**

```
kubectl rollout undo deployment/productcatalog-rollout -n recovery-test
```

---

## 18.3 로컬 Kubernetes 검증 결과

| 검증 항목 | 결과 |
| --- | --- |
| Namespace 생성 | 성공 |
| Kustomize 변환 | 성공 |
| Dry-run | 성공 |
| Deployment | 11개 정상 |
| Pod | 11개 Ready |
| Service | 12개 생성 |
| 상품 조회 | 정상 |
| 장바구니 | 정상 |
| 모의 주문 | 정상 |

---

## 18.4 AWS EKS 검증 결과

| 검증 항목 | 결과 |
| --- | --- |
| EKS Cluster 생성 | 성공 |
| Worker Node | 2개 Ready |
| Online Boutique | 11개 Deployment 정상 |
| Argo CD | Synced / Healthy |
| Metrics Server | 정상 |
| Pod 자동 복구 | 성공 |
| HPA 자동 확장 | 성공 |
| Deployment 실패 판정 | 확인 |
| 수동 Rollback | 성공 |
| Prometheus Firing | 확인 |

---

## 18.5 실험 결과 분석

### Pod 복구

ReplicaSet은 Pod 삭제 이후 원하는 Replica 수를 유지하기 위해 신규 Pod를 자동 생성하였다.

자동 복구 평균 Ready 도달 시간은 3.666초로 측정됐다.

### HPA

CPU 사용률 증가에 따라 Pod가 자동 확장됐고 부하 종료 이후 축소됐다.

다만 성능 비교에서는 P95 개선이 확인되지 않았다.

### Deployment

Readiness Probe 오류가 있는 신규 Pod는 Ready 상태에 도달하지 못했고 기존 정상 Pod가 유지됐다.

수동 Rollback에는 16.360초가 소요됐다.

### Monitoring

PrometheusRule을 통해 실험용 Pod의 NotReady 상태를 감지하고 Firing 전환을 확인하였다.

---

# 19. 트러블슈팅 요약

## 19.1 Kustomize 적용 옵션 오류

**문제**

Kustomize 기반 배포 디렉터리에 `kubectl apply -f`를 사용하여 Namespace 및 이미지 설정이 정상 반영되지 않았다.

일부 Pod에서 ImagePullBackOff 및 ErrImagePull이 발생하였다.

**원인**

Kustomize 변환을 수행하는 `-k` 옵션 대신 일반 YAML 적용 옵션인 `-f`를 사용하였다.

**해결**

Kustomize 설정을 적용할 수 있도록 명령어를 수정하였다.

```
kubectl apply -k .\kubernetes\online-boutique\
```

이후 `online-boutique` Namespace에 11개 Deployment가 정상 실행되는 것을 확인하였다.

---

## 19.2 frontend.yaml 문법 오류

**문제**

Kustomize Manifest 변환 중 YAML 파싱 오류와 이미지 설정 관련 오류가 발생하였다.

**원인**

YAML 들여쓰기 오류, Tab 문자 사용, 중복 이미지 선언 및 `imagePullPolicy` 필드 오타가 확인되었다.

**해결**

YAML 들여쓰기를 Space로 통일하고 중복 설정을 제거하였다.

```
imagePullPolicy: IfNotPresent
```

검증:

```
kubectl kustomize .\kubernetes\online-boutique\
```

이후 정상적인 Manifest 생성 및 Kubernetes 배포를 확인하였다.

---

## 19.3 Metrics Server 미구성

**문제**

EKS에서 HPA 실험을 준비하는 과정에서 CPU 및 Memory 사용량을 정상적으로 조회할 수 없었다.

**원인**

클러스터에 Metrics Server가 구성되지 않아 Metrics API가 사용 가능하지 않았다.

**해결**

Metrics Server를 EKS Add-on으로 설치하였다.

이후 `kubectl top nodes`, `kubectl top pods`가 정상 동작했으며 HPA 자동 확장 실험을 진행할 수 있었다.

---

## 19.4 HPA 성능 개선 미확인

**문제**

HPA가 Pod를 1개에서 2개로 확장했지만 동일한 부하 조건에서 P95 개선이 나타나지 않았다.

**원인 또는 한계**

기존 gRPC 연결의 재사용과 낮은 부하 수준 때문에 신규 Pod 확장이 응답 성능 개선으로 이어지지 않았을 가능성이 있다.

**결과**

HPA의 기능 동작은 성공적으로 검증했으나 성능 개선은 확인되지 않았다.

추가 실험에서는 gRPC 연결 분산과 높은 부하 조건을 고려할 필요가 있다.

---

## 19.5 잘못된 Deployment 배포

**문제**

Readiness Probe 포트를 잘못 설정한 신규 Pod가 `0/1 Ready` 상태로 유지됐다.

**원인**

실험 목적으로 실제 gRPC 포트 3550 대신 3551을 지정하였다.

**해결**

기존 정상 Pod가 유지되는 것을 확인하고, Deployment의 `ProgressDeadlineExceeded`를 확인한 뒤 수동 Rollback을 실행하였다.

```
kubectl rollout undo deployment/productcatalog-rollout -n recovery-test
```

**결과**

정상 Revision으로 복귀했으며 Rollback 소요 시간은 16.360초로 측정됐다.

---

## 19.6 PrometheusRule 선택 라벨

**문제**

실험용 PrometheusRule이 Prometheus의 규칙 선택 조건을 충족하는지 확인할 필요가 있었다.

**확인 사항**

Prometheus의 Rule Selector는 다음과 같이 설정돼 있었다.

```
ruleSelector:
  matchLabels:
    release: monitoring
```

**해결**

실험용 PrometheusRule에 동일한 라벨을 추가하여 규칙이 선택되도록 구성하였다.

이후 `RecoveryTestPodNotReady`의 Firing 상태를 확인하였다.

---

## 최종 결론

**같은 Pod 장애 상황에서 수동 복구는 평균 19.101초가 소요된 반면, Kubernetes 자동 복구는 평균 3.666초로 약 80.8% 짧게 측정됐다. 결국 안정적인 Kubernetes 운영의 핵심은 장애 발생 후 수동으로 대응하는 것뿐만 아니라, 시스템이 원하는 상태를 스스로 유지하고 복구하도록 설계하는 데 있다.**
