| 버전 | 변경 내용 | 상태 |
| --- | --- | --- |
| v0.1 | Prometheus, Grafana, Metric 및 Alert 설계 | 완료 |
| v0.2 | kube-prometheus-stack 설치 및 Kubernetes Metric 수집 환경 구축 | 완료 |
| v0.3 | PrometheusRule, Alertmanager 연동 및 Pod NotReady 장애 탐지 검증 | 완료 |
| v1.0 | 최종 Monitoring 구성, 장애 관측 결과, 정량 지표 및 검증 한계 반영 | 최종 |

---

## 1. 문서 목적

AWS EKS 기반 Online Boutique 환경에서 Kubernetes 리소스 상태를 수집하고 장애 발생 및 복구 과정을 관찰하기 위한 모니터링 구조를 정의한다.

Prometheus를 통해 Node, Pod, Deployment 등의 운영 메트릭을 수집하고, Grafana를 통해 시스템 상태를 시각화하도록 구성하였다.

또한 PrometheusRule과 Alertmanager를 연계하여 Kubernetes 리소스의 비정상 상태를 감지하고 알림을 확인할 수 있는 환경을 구축하였다.

본 프로젝트에서는 단순히 CPU와 Memory 사용량을 확인하는 것을 넘어 다음 질문을 중심으로 모니터링을 설계하였다.

> **장애가 발생했을 때 Kubernetes의 어떤 상태가 변하며, 모니터링 시스템은 이를 감지할 수 있는가?**
> 

장애 발생부터 사용자 요청 정상화까지의 전체 시간을 정량적으로 측정하는 것은 최종 목표였으나, 이번 실험에서는 일부 복구 시간과 장애 감지 기능을 중심으로 검증하였다.

---

## 2. 설계 목표

### 2.1 핵심 목표

- Worker Node CPU / Memory 상태 수집
- Kubernetes Pod 및 Deployment 상태 확인
- Pod Ready / NotReady 상태 관찰
- Container Restart 상태 확인
- Desired Replica와 Available Replica 비교
- HPA CPU 사용률 및 Replica 변화 확인
- Prometheus 기반 장애 알림 규칙 구성
- Alertmanager를 통한 알림 수신 확인
- Grafana 기반 운영 상태 시각화
- k6를 통한 RPS, P95, Error Rate 측정
- 장애 감지와 Kubernetes 자동 복구의 역할 구분
- 향후 MTTD 및 MTTR 정량 분석에 필요한 관측 구조 마련

### 2.2 최종 검증 결과

| 목표 | 실제 결과 |
| --- | --- |
| Prometheus 구축 | 완료 |
| Grafana 구축 | 완료 |
| Node Metric 수집 환경 | 구성 완료 |
| Kubernetes Object Metric | 구성 완료 |
| Metrics Server | 설치 및 정상 동작 |
| HPA 관측 | Replica 1 → 2 → 1 확인 |
| PrometheusRule | 구성 완료 |
| Pod NotReady 탐지 | Firing 확인 |
| Alertmanager 연계 | 알림 그룹 확인 |
| RPS / P95 / Error Rate | k6 측정 완료 |
| MTTD | 정량 측정 미완료 |
| 서비스 전체 MTTR | 정량 측정 미완료 |
| Availability | 정량 측정 미완료 |

---

## 3. Monitoring 전체 구조

### 3.1 최종 모니터링 아키텍처

```
AWS EKS Cluster
       │
       ├── Worker Node
       │       │
       │       ▼
       │   Node Exporter
       │
       ├── Kubernetes Objects
       │       │
       │       ▼
       │  kube-state-metrics
       │
       └── Kubernetes Workloads
               │
               ▼
          Prometheus
               │
        ┌──────┴─────────┐
        │                │
        ▼                ▼
     Grafana         Alert Rules
                         │
                         ▼
                    Alertmanager
```

### 3.2 HPA용 메트릭 구조

```
Pod CPU 사용량
       │
       ▼
Metrics Server
       │
       ▼
Kubernetes Metrics API
       │
       ▼
HPA Controller
       │
       ▼
Deployment Replica 조정
```

Metrics Server와 Prometheus는 서로 역할이 다르다.

Metrics Server는 HPA가 활용하는 리소스 메트릭을 제공하며, Prometheus는 운영 메트릭의 수집·저장과 알림 규칙 평가에 활용된다.

### 3.3 장애 탐지와 자동 복구의 관계

```
            Pod 장애
               │
       ┌───────┴────────┐
       │                │
       ▼                ▼
Kubernetes Controller  Prometheus
       │                │
       ▼                ▼
  Pod 재생성         Alert Rule
       │                │
       ▼                ▼
 Pod Ready          Alertmanager
       │                │
       └───────┬────────┘
               ▼
         운영 상태 분석
```

**Prometheus가 Pod를 직접 재생성하는 것은 아니다.**

Pod 자동 복구는 Kubernetes Controller 또는 kubelet이 수행하며, Prometheus는 상태 변화를 관측하고 알림을 발생시킨다.

---

## 4. 모니터링 대상

| 영역 | 수집 또는 확인 대상 | 활용 목적 |
| --- | --- | --- |
| Infrastructure | Node CPU, Memory, 상태 | 자원 사용 및 Node 상태 확인 |
| Kubernetes | Pod, Deployment, Replica, Restart | 장애 및 복구 과정 관찰 |
| HPA | CPU Utilization, Replica | 자동 확장 검증 |
| Application | RPS, P95, Error Rate | 부하 테스트 결과 분석 |
| Alerting | Pod NotReady, Container Restart, Deployment Unavailable | 장애 알림 검증 |

애플리케이션 성능 지표는 이번 프로젝트에서 주로 k6 테스트 결과로 측정하였다.

---

# 5. Infrastructure Metric

## 5.1 Node CPU

### 목적

Worker Node의 CPU 사용량을 관찰하고 부하 테스트 및 Pod 확장 과정에서 자원 상태를 확인한다.

### 주요 메트릭

```
1 - avg by (instance) (
  rate(node_cpu_seconds_total{mode="idle"}[5m])
)
```

위 PromQL은 Node Exporter의 CPU Idle 시간을 이용해 CPU 사용 비율을 계산하는 예시다.

### 활용

- Worker Node CPU 사용률 확인
- CPU 부하 및 확장 실험 시 참고
- Node 간 자원 상태 비교

---

## 5.2 Node Memory

### 목적

Worker Node의 전체 메모리와 사용 가능한 메모리를 확인하여 메모리 압박 가능성을 관찰한다.

### 주요 메트릭

```
node_memory_MemTotal_bytes
```

```
node_memory_MemAvailable_bytes
```

메모리 사용률 계산 예시:

```
1 - (
  node_memory_MemAvailable_bytes
  /
  node_memory_MemTotal_bytes
)
```

### 활용

- Node 메모리 사용률 확인
- Pod 증가 시 메모리 사용 변화 관찰
- 자원 부족 상황 분석

---

## 5.3 Node 상태

### 확인 대상

- Ready / NotReady
- MemoryPressure
- DiskPressure
- PIDPressure

### 주요 메트릭 예시

```
kube_node_status_condition{
  condition="Ready",
  status="true"
}
```

### 실제 프로젝트 범위

Worker Node 2개가 Ready 상태임을 확인하였다.

Node 장애를 직접 유발하거나 Node 자동 교체를 측정하는 실험은 수행하지 않았다.

---

# 6. Kubernetes Metric

## 6.1 Pod 상태

### 목적

Pod 장애 발생과 복구 과정에서 상태가 어떻게 변화하는지 확인한다.

### 관찰 항목

- Pod Running / Pending / Failed
- Pod Ready / NotReady
- Pod 생성 및 삭제
- 신규 Pod 생성 후 정상 상태 복귀

### 메트릭 예시

```
kube_pod_status_ready{
  namespace="recovery-test",
  condition="true"
}
```

값이 1이면 Ready, 0이면 NotReady 상태를 나타낸다.

### 실제 검증

실험용 Pod의 Readiness Probe 실패를 유도하여 `0/1 Running` 상태를 재현하였다.

해당 상태가 Prometheus 알림 규칙을 통해 Firing으로 전환되는 것을 확인하였다.

---

## 6.2 Container Restart

### 목적

컨테이너가 비정상 종료되거나 Liveness Probe 실패로 재시작되는 상황을 관찰한다.

### 주요 메트릭

```
kube_pod_container_status_restarts_total
```

### 활용

- 컨테이너 재시작 횟수 확인
- 비정상 종료 여부 분석
- Liveness Probe 및 OOM 관련 장애 진단

### 실제 적용

Container Restart 증가를 감지하는 PrometheusRule을 구성하였다.

다만 Liveness Probe 실패를 의도적으로 발생시켜 재시작 알림의 동작과 복구 시간을 측정하는 독립 실험은 수행하지 않았다.

---

## 6.3 Replica

### 목적

Deployment의 원하는 Replica 수와 실제 사용 가능한 Replica 수를 비교한다.

### 주요 메트릭

```
kube_deployment_spec_replicas
```

```
kube_deployment_status_replicas_available
```

### 관찰 흐름

```
Desired Replica = 1
Available Replica = 0
         │
         ▼
ReplicaSet 자동 복구
         │
         ▼
Desired Replica = 1
Available Replica = 1
```

### 실제 활용

Pod Failure 실험에서 ReplicaSet이 삭제된 Pod를 대체 생성하는 것을 확인하였다.

Deployment Failure 실험에서는 신규 Pod가 Ready 상태에 도달하지 못했지만 기존 정상 Pod가 유지되는 것을 확인하였다.

---

## 6.4 HPA

### 실제 실험 대상

초기 설계에서는 Frontend를 대상으로 HPA를 구성할 계획이었으나, 실제 실험에서는 `recovery-test` Namespace의 `productcatalog-auto` Deployment를 사용하였다.

### 최종 설정

| 항목 | 값 |
| --- | --- |
| 대상 Deployment | productcatalog-auto |
| CPU Target | 60% |
| minReplicas | 1 |
| maxReplicas | 3 |
| 실제 확장 | 1 → 2 |
| 실제 축소 | 2 → 1 |

### 확인 명령어

```
kubectl get hpa -n recovery-test
kubectl describe hpa productcatalog-auto -n recovery-test
kubectl top pods -n recovery-test
```

### 실제 검증

`SuccessfulRescale` 이벤트를 통해 HPA가 CPU 사용률을 기준으로 Replica 수를 변경한 것을 확인하였다.

---

## 6.5 Resource 사용량

### 목적

Pod의 CPU 및 Memory 사용량을 Request / Limit과 비교한다.

### ProductCatalog 실험 설정

| 항목 | 값 |
| --- | --- |
| CPU Request | 100m |
| CPU Limit | 200m |
| Memory Request | 64Mi |
| Memory Limit | 128Mi |

### 활용

- CPU 사용률 확인
- HPA Target 충족 여부 분석
- Resource Request 대비 실제 사용량 비교

### 검증 한계

HPA 자동 확장은 검증했지만 CPU Throttling이나 Memory OOM 발생에 대한 정량 실험은 수행하지 않았다.

---

# 7. Application Metric

## 7.1 Request Rate

### 목적

부하 테스트에서 초당 요청 수를 확인하여 동일한 요청 속도가 유지됐는지 검증한다.

### 측정 방식

EKS 내부의 k6 Job을 사용하여 ProductCatalog gRPC API에 요청을 발생시켰다.

### 실제 결과

| 항목 | HPA OFF | HPA ON |
| --- | --- | --- |
| 목표 RPS | 100 | 100 |
| 실제 RPS | 약 100.0045 | 약 100.0047 |
| 총 요청 | 18,001 | 18,001 |

두 조건에서 목표 요청 속도가 유지되는 것을 확인하였다.

---

## 7.2 Error Rate

### 목적

전체 요청 중 실패한 요청의 비율을 계산하여 서비스 안정성을 평가한다.

### 계산식

```
Error Rate (%)
=
실패 요청 수 / 전체 요청 수 × 100
```

### 실제 결과

| 항목 | HPA OFF | HPA ON |
| --- | --- | --- |
| 총 요청 | 18,001 | 18,001 |
| 실패 요청 | 0 | 0 |
| Error Rate | 0% | 0% |

두 조건 모두 요청 실패가 발생하지 않았다.

다만 이 결과는 해당 부하 조건에서의 측정값이며, 실제 운영 환경 전체의 가용성을 의미하지 않는다.

---

## 7.3 Latency

### 목적

서비스 응답시간을 측정하여 HPA 적용 전후의 성능 차이를 분석한다.

### 측정 지표

- Average Latency
- P95 Latency
- Maximum Latency

### 실제 결과

| 항목 | HPA OFF | HPA ON |
| --- | --- | --- |
| Average | 0.853ms | 0.921ms |
| P95 | 1.25ms | 1.38ms |
| Maximum | 7.88ms | 13.56ms |

### 결과 분석

HPA ON 상태에서 P95가 OFF보다 약 10.4% 높게 측정됐다.

이번 부하 조건에서는 HPA에 의한 응답시간 개선을 확인하지 못하였다.

또한 gRPC 연결 재사용에 따른 요청 분산 특성과 부하 수준의 한계가 있으므로, 단일 실험 결과만으로 HPA가 성능을 악화시킨다고 단정할 수 없다.

---

## 7.4 Availability

### 정의

서비스 Availability는 사용자 요청을 정상적으로 처리할 수 있는 상태를 의미한다.

요청 성공률을 이용하면 다음과 같은 참고 지표를 계산할 수 있다.

```
Request Success Rate (%)
=
성공 요청 / 전체 요청 × 100
```

### 실제 검증

HPA OFF/ON 테스트에서 요청 성공률은 모두 100%였다.

다만 이번 실험에서는 장기간 서비스 가용 시간을 측정하지 않았으므로 전체 서비스 Availability 지표는 산출하지 않았다.

---

# 8. 서비스별 핵심 관찰 지표

## 8.1 frontend

### 역할

사용자 요청의 진입점으로, 여러 Backend Microservices와 통신한다.

### 확인 지표

- HTTP 응답 정상화 시간
- Frontend Pod 상태
- gRPC 재연결 및 백오프 동작
- Kubernetes Deployment 상태

### 실제 결과

gRPC 재연결 동작 개선 후 HTTP 정상 응답 회복 시간이 평균 6.389초로 측정됐다.

다만 개선 전 측정 횟수가 1회이므로 결과를 동일 조건에서의 확정적인 개선율로 해석하지 않는다.

---

## 8.2 productcatalogservice

### 역할

상품 정보를 제공하는 서비스로, Pod Failure 및 HPA 실험의 기준 애플리케이션이다.

### 확인 지표

- Pod Ready 상태
- Replica 수
- Pod Ready 도달 시간
- CPU 사용률
- P95
- Error Rate

### 실제 결과

Pod 자동 복구, HPA 확장, gRPC 부하 테스트를 수행하였다.

---

## 8.3 checkoutservice

### 역할

주문 과정에서 여러 Backend Microservices를 호출한다.

### 확인 지표

- Pod Running / Ready
- 서비스 의존 관계
- 주문 기능 정상 여부

### 검증 범위

Online Boutique의 기본 주문 기능을 확인하였다.

CheckoutService를 대상으로 장애를 주입하거나 별도의 Request Error 및 P95를 측정하지는 않았다.

---

## 8.4 paymentservice

### 역할

주문 과정에서 결제 기능을 처리한다.

### 초기 계획

PaymentService의 잘못된 버전을 배포하여 Checkout 장애와 Error Rate를 관찰할 계획이었다.

### 최종 검증 범위

실제 Deployment Failure 실험은 별도 ProductCatalog Deployment를 대상으로 수행하였다.

따라서 PaymentService의 배포 실패 또는 결제 요청 오류율을 측정한 것으로 기록하지 않는다.

---

# 9. 장애 시나리오별 Monitoring 설계

## Scenario 01 — Pod Failure

### 대상

ProductCatalog 기반 실험용 Pod

### 관찰 흐름

```
Pod 정상
    ↓
Pod 강제 삭제
    ↓
Replica 불일치
    ↓
ReplicaSet 새 Pod 생성
    ↓
Readiness 성공
    ↓
Pod Ready
```

### 실제 결과

| 항목 | 수동 복구 | 자동 복구 |
| --- | --- | --- |
| 평균 Pod Ready 시간 | 19.101초 | 3.666초 |

자동 복구 방식에서 평균 Pod Ready 도달 시간이 약 80.8% 짧게 측정됐다.

단, 수동·자동 실험의 실행 조건이 완전히 일치하지 않으므로 서비스 전체 MTTR 개선율로 해석하지 않는다.

---

## Scenario 02 — Resource Exhaustion / HPA

### 대상

`productcatalog-auto`

### 관찰 흐름

```
k6 부하 발생
      ↓
Pod CPU 사용률 증가
      ↓
HPA Target 평가
      ↓
Replica 1 → 2
      ↓
부하 종료
      ↓
Replica 2 → 1
```

### 실제 결과

- CPU Target 60%
- Scale-out / Scale-in 확인
- HPA OFF/ON 각각 18,001건 처리
- Error Rate 0%
- P95 개선 미확인

CPU 기반 HPA 동작은 검증했지만 서비스 성능 개선은 입증하지 못하였다.

---

## Scenario 03 — Deployment Failure

### 대상

`productcatalog-rollout`

### 장애 방식

정상 gRPC 포트 3550 대신 Readiness Probe 포트를 3551로 설정하였다.

### 관찰 흐름

```
기존 정상 Pod
       ↓
잘못된 Deployment 적용
       ↓
신규 Pod Running
       ↓
Readiness 실패
       ↓
신규 Pod NotReady
       ↓
기존 Pod 유지
       ↓
ProgressDeadlineExceeded
       ↓
수동 Rollback
```

### 실제 결과

| 항목 | 결과 |
| --- | --- |
| 기존 Pod | 1/1 Ready |
| 신규 Pod | 0/1 Ready |
| 실패 이유 | ProgressDeadlineExceeded |
| Rollback Time | 16.360초 |

---

## Scenario 04 — Pod NotReady Alert

### 대상

`alert-test-pod`

### 장애 방식

Readiness Probe가 실패하도록 실험용 Pod를 구성하였다.

### 관찰 흐름

```
Pod 생성
    ↓
Readiness 실패
    ↓
Pod NotReady
    ↓
kube-state-metrics
    ↓
PrometheusRule 평가
    ↓
Alert Firing
    ↓
Alertmanager
```

### 실제 결과

- 실험용 Pod `0/1 Running` 확인
- Prometheus `RecoveryTestPodNotReady` Firing 확인
- Alertmanager 알림 그룹 표시 확인

장애 발생부터 Alertmanager 수신까지의 시간은 별도로 정량 측정하지 않았다.

---

# 10. Grafana Dashboard 구성

## 10.1 Cluster Overview

### 목적

EKS 클러스터의 Worker Node 및 Kubernetes 리소스 상태를 확인한다.

### 주요 관측 대상

- Node CPU
- Node Memory
- Pod 상태
- Container Restart
- Deployment Replica
- Node 상태

### 구현 범위

Grafana를 설치하고 Prometheus 기반 운영 메트릭을 확인할 수 있는 환경을 구성하였다.

다만 아래 패널을 모두 포함한 프로젝트 전용 Cluster Overview Dashboard를 별도로 제작·검증했다는 기록은 확보하지 않았다.

---

## 10.2 Application / Service

### 설계 대상

- RPS
- P95
- Error Rate
- Pod CPU
- Pod Memory
- HPA Replica

### 실제 측정 방식

이번 프로젝트에서는 Application RPS, P95 및 Error Rate를 주로 k6 결과로 측정하였다.

이를 모두 Prometheus에 수집하거나 Grafana의 단일 Dashboard에 연계했다고 기록하지 않는다.

---

## 10.3 Failure & Recovery

### 설계 목적

장애 발생과 복구 과정에서 다음 지표를 동일한 시간축으로 비교하는 Dashboard를 구성하는 것이다.

```
Pod Ready
Replica
Restart Count
CPU Usage
Error Rate
P95
```

### 최종 상태

장애 감지와 복구 동작은 개별 실험 및 Prometheus 알림으로 검증하였다.

그러나 장애 발생부터 사용자 요청 회복까지의 전체 시점을 하나의 Grafana Dashboard에 시각화하는 작업은 최종 검증 범위에 포함되지 않았다.

향후 개선 대상으로 유지한다.

---

# 11. Alert 설계

## 11.1 Online Boutique 기본 알림 규칙

`monitoring/rules/pod-alerts.yaml`에 Kubernetes 리소스 상태를 감지하는 알림 규칙을 구성하였다.

| Alert | 감지 대상 | 설정 |
| --- | --- | --- |
| OnlineBoutiquePodNotReady | Pod Ready 실패 | 1분 지속 |
| OnlineBoutiqueContainerRestart | Container Restart 증가 | 즉시 평가 |
| OnlineBoutiqueDeploymentUnavailable | Deployment 가용 Replica 부족 | 1분 지속 |

### 적용 목적

- Pod가 장시간 Ready 상태에 도달하지 못하는 상황 감지
- 컨테이너 재시작 증가 감지
- Deployment에서 사용 가능한 Replica 부족 감지

---

## 11.2 실험용 NotReady Alert

실제 Firing 검증을 위해 별도의 PrometheusRule을 사용하였다.

**PrometheusRule 파일**

```
tests/alerts/recovery-test-alert.yaml
```

### 주요 설정

```
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: recovery-test-alert
  namespace: monitoring
  labels:
    release: monitoring
spec:
  groups:
    - name: recovery-test.rules
      rules:
        - alert: RecoveryTestPodNotReady
          expr: |
            kube_pod_status_ready{
              namespace="recovery-test",
              pod=~"alert-test-.*",
              condition="true"
            } == 0
          for: 30s
          labels:
            severity: warning
```

### 설정 설명

- `namespace="recovery-test"`: 실험 Namespace만 선택
- `pod=~"alert-test-.*"`: 실험용 Pod 이름 패턴 선택
- `condition="true"`: Pod Ready 조건 확인
- `== 0`: Ready가 아닌 상태 감지
- `for: 30s`: 조건이 30초 동안 유지되면 Firing
- `release: monitoring`: PrometheusRule 선택 라벨

### 실제 검증

Pod의 Readiness 실패를 유도한 후 Prometheus Alerts 화면에서 `RecoveryTestPodNotReady`가 Firing 상태로 전환되는 것을 확인하였다.

---

## 11.3 Alertmanager

### 역할

Prometheus에서 발생한 알림을 수신하고 그룹화하여 관리한다.

### 실제 결과

`recovery-test` Namespace와 관련된 알림 그룹이 Alertmanager에 표시되는 것을 확인하였다.

### 검증 한계

- 외부 이메일 발송 여부는 확인하지 않음
- Slack 또는 기타 외부 알림 채널 미검증
- 알림 전달 지연 시간 미측정
- Resolved 전환까지의 정확한 소요 시간 미측정

---

# 12. MTTD 측정 설계

## 12.1 정의

MTTD(Mean Time To Detect)는 장애 발생 시점부터 모니터링 시스템이 장애를 감지한 시점까지의 평균 시간을 의미한다.

```
MTTD = 평균 (장애 탐지 시각 - 장애 발생 시각)
```

### 측정 기준

- T0: 장애 발생
- T1: Prometheus Alert Firing 시각

### 실제 검증

Prometheus에서 장애 알림 Firing을 확인하였다.

다만 장애 주입 시각과 Firing 전환 시각을 반복 측정하여 기록하지 않았으므로 MTTD를 정량적으로 산출하지 않았다.

### 참고

실험용 Alert의 `for: 30s`는 알림 조건이 유지되어야 하는 설정 시간이며, 실제 MTTD가 정확히 30초라는 의미는 아니다.

Prometheus의 Scrape 및 Rule Evaluation 주기에 따라 Firing 시각은 달라질 수 있다.

---

# 13. MTTR 측정 설계

## 13.1 정의

MTTR(Mean Time To Recovery)은 장애가 발생한 시점부터 정상 상태가 복구될 때까지의 평균 시간을 의미한다.

본 프로젝트에서는 서비스 관점의 복구 시간과 Kubernetes 리소스의 복구 시간을 구분하였다.

### Pod Ready 시간

```
Pod Ready Time
=
신규 Pod Ready 도달 시각 - 실험 시작 시각
```

### 서비스 관점 Recovery Time

```
Service Recovery Time
=
사용자 요청 정상화 시각 - 장애 발생 시각
```

### 실제 측정 결과

| 항목 | 결과 |
| --- | --- |
| 수동 Pod Ready 평균 | 19.101초 |
| 자동 Pod Ready 평균 | 3.666초 |
| Frontend 개선 후 HTTP 회복 평균 | 6.389초 |
| 수동 Deployment Rollback | 16.360초 |

### 결과 해석

Pod Ready 시간은 Kubernetes 리소스의 정상 상태 도달 시간이다.

반면 서비스 Recovery Time은 사용자 요청이 실제로 정상 처리되는 시점을 기준으로 한다.

이번 실험에서는 일부 복구 시간을 측정했지만 전체 서비스의 장애 발생부터 완전 정상화까지의 MTTR을 통합 산출하지는 않았다.

---

# 14. Prometheus 배포 방식

## 14.1 최종 배포 방식

Prometheus 및 Grafana는 Helm 기반 `kube-prometheus-stack`으로 구성하였다.

### 설치 Namespace

```
monitoring
```

### 주요 구성요소

- Prometheus
- Grafana
- Alertmanager
- kube-state-metrics
- Prometheus Node Exporter
- Prometheus Operator

### 구조

```
Helm
  │
  ▼
kube-prometheus-stack
  │
  ├── Prometheus
  ├── Grafana
  ├── Alertmanager
  ├── kube-state-metrics
  ├── Node Exporter
  └── Prometheus Operator
```

### 실제 검증

Monitoring Namespace에서 관련 Pod가 정상 동작하는 것을 확인하였다.

Prometheus Alerts와 Alertmanager를 통해 장애 알림 흐름을 검증하였다.

---

## 14.2 PrometheusRule 선택 설정

Prometheus가 알림 규칙을 선택하도록 다음 설정을 사용하였다.

```
ruleSelector:
  matchLabels:
    release: monitoring
```

실험용 PrometheusRule에 동일한 라벨을 설정해 규칙이 적용되도록 구성하였다.

### 알림 규칙 평가

프로젝트에서 확인한 Prometheus Rule Evaluation Interval은 30초였다.

따라서 실험 알림의 실제 Firing 시각은 Pod 상태 메트릭 수집 주기, Rule Evaluation Interval 및 `for` 설정의 영향을 받는다.

---

# 15. Metric 수집 구조

## 15.1 Node Metric

```
Worker Node
     │
     ▼
Node Exporter
     │
     ▼
Prometheus
     │
     ▼
Grafana
```

### 주요 활용

- Node CPU
- Node Memory
- Node 리소스 상태 확인

---

## 15.2 Kubernetes Object Metric

```
Pod / Deployment / Node 상태
             │
             ▼
       kube-state-metrics
             │
             ▼
         Prometheus
             │
             ▼
          Alert Rules
```

### 주요 활용

- Pod Ready
- Container Restart
- Deployment Available Replica
- Node 상태

---

## 15.3 HPA Metric

```
Pod CPU
   │
   ▼
Metrics Server
   │
   ▼
Metrics API
   │
   ▼
HPA
   │
   ▼
Replica 조정
```

Prometheus는 HPA 실험의 관측 도구로 활용할 수 있지만, 이번 HPA의 CPU 사용률 판단은 Metrics Server를 기반으로 이루어졌다.

---

## 15.4 Application Metric / k6

```
k6 Job
   │
   ▼
ProductCatalog gRPC
   │
   ▼
k6 Result
   │
   ├── RPS
   ├── P95
   ├── Error Rate
   └── Request Duration
```

이번 프로젝트의 k6 부하 테스트 결과는 로그 파일로 보존하였다.

- `tests/results/hpa-off-k6.log`
- `tests/results/hpa-on-k6.log`

k6 결과를 Prometheus에 직접 전송하는 통합은 검증하지 않았다.

---

# 16. 로그와 Trace 범위

## 16.1 Logs

기본적인 Kubernetes 로그 확인은 `kubectl logs`를 사용하였다.

```
kubectl logs <pod-name> -n <namespace>
```

Pod 이벤트 및 상태 분석에는 다음 명령어를 활용하였다.

```
kubectl describe pod <pod-name> -n <namespace>
```

## 16.2 Tracing

분산 추적 시스템은 이번 프로젝트의 구현 범위에 포함하지 않았다.

Loki, Tempo 및 OpenTelemetry 연동은 향후 개선 항목으로 분류하였다.

## 16.3 설계 판단

이번 프로젝트에서는 장애 복구 기능과 그 결과를 검증하는 것이 주요 목적이므로 Metrics 기반 모니터링을 중심으로 구성하였다.

---

# 17. Monitoring 책임 분리

| 영역 | 담당 도구 | 프로젝트 적용 |
| --- | --- | --- |
| Node Metric | Node Exporter | 구성 |
| Kubernetes Object Metric | kube-state-metrics | 구성 |
| Resource Metrics API | Metrics Server | 검증 |
| Metric 저장·조회 | Prometheus | 검증 |
| 시각화 | Grafana | 구성 |
| Alert 평가 | PrometheusRule | 검증 |
| Alert 수신 | Alertmanager | 확인 |
| 부하 성능 측정 | k6 | 검증 |
| 로그 확인 | kubectl logs | 사용 |
| 배포 상태 확인 | kubectl / Argo CD | 사용 |

---

# 18. 최종 구성 및 미검증 항목

## 18.1 최종 적용 구성

| 항목 | 최종 상태 |
| --- | --- |
| Prometheus 설치 | kube-prometheus-stack |
| 설치 Namespace | monitoring |
| Grafana | 설치 완료 |
| Alertmanager | 설치 완료 |
| Node Exporter | 구성 완료 |
| kube-state-metrics | 구성 완료 |
| Metrics Server | EKS Add-on |
| HPA 관측 | 검증 완료 |
| Pod NotReady Alert | Firing 확인 |
| Alertmanager 알림 그룹 | 확인 |
| P95 측정 방식 | k6 |
| Error Rate 측정 방식 | k6 |
| RPS 측정 방식 | k6 |
| Alert 평가 주기 | 30초 |

## 18.2 미검증 및 개선 항목

| 항목 | 상태 |
| --- | --- |
| 프로젝트 전용 통합 Dashboard | 별도 검증 기록 없음 |
| 애플리케이션 자체 Prometheus Metric | 수집 검증 미완료 |
| k6 → Prometheus Metric 연계 | 미구현 |
| MTTD 정량 측정 | 미완료 |
| 전체 서비스 MTTR | 미완료 |
| 장기간 Availability | 미완료 |
| 외부 이메일 / Slack 알림 | 미검증 |
| Alertmanager Resolved 시간 | 미측정 |
| Loki / Tempo | 미구현 |

---

# 19. 설계 결론

AWS EKS 환경에 Prometheus, Grafana 및 Alertmanager 기반 모니터링 체계를 구축하였다.

Node Exporter와 kube-state-metrics를 활용하여 Kubernetes 리소스 상태를 수집할 수 있도록 구성하고, Metrics Server 기반 HPA 동작도 검증하였다.

또한 실험용 Pod의 Readiness Probe 실패를 유도하여 Prometheus에서 NotReady 알림이 Firing 상태로 전환되는 것을 확인하고, Alertmanager에서 관련 알림 그룹을 확인하였다.

애플리케이션 성능은 k6를 이용해 P95, RPS, Error Rate를 측정했으며, 이를 Kubernetes의 Pod 복구 및 HPA 실험 결과와 함께 분석하였다.

### 최종 결론 한 줄

**Kubernetes가 ReplicaSet과 HPA로 장애 복구 및 자원 확장을 수행하는 동안, Prometheus는 리소스의 비정상 상태를 감지하고 Alertmanager는 이를 확인할 수 있는 알림 체계를 제공했습니다. 결국 안정적인 인프라 운영의 핵심은 장애를 자동으로 복구하는 기능뿐 아니라, 그 과정과 결과를 관측하고 검증할 수 있는 환경을 함께 구축하는 데 있었습니다.**
