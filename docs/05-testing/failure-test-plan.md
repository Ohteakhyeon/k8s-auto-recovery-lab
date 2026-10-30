| 버전 | 변경 내용 | 상태 |
| --- | --- | --- |
| v0.1 | Pod Failure, Resource Exhaustion, Deployment Failure 시나리오 및 측정 기준 설계 | 완료 |
| v0.2 | 로컬 Kubernetes Pod Failure 사전 검증 및 측정 방식 반영 | 완료 |
| v0.3 | AWS EKS 장애 시나리오, 수동·자동 복구 및 HPA 실험 구성 반영 | 완료 |
| v1.0 | 실제 수행 조건, 정량 측정 결과, 성공 기준 및 검증 한계 반영 | 최종 |

---

## 1. 문서 목적

Kubernetes 기반 Google Online Boutique 운영 환경에서 장애를 의도적으로 재현하고, Kubernetes의 자동 복구 및 장애 대응 기능을 검증하기 위한 테스트 기준과 수행 결과를 정의한다.

주요 검증 대상은 Pod Failure, CPU 부하에 따른 HPA 자동 확장, Deployment Failure 및 Prometheus 기반 장애 탐지이다.

실제 장애 테스트에서는 `recovery-test` Namespace에 독립된 실험 리소스를 구성하여 기존 Online Boutique 애플리케이션에 미치는 영향을 최소화하였다.

특히 수동 복구와 자동 복구의 Pod Ready 도달 시간, HPA OFF/ON 응답 성능, 수동 Rollback 시간 등을 측정하였다.

**본 테스트의 핵심 목적은 Kubernetes의 자동화 기능이 실제로 동작하는지 확인하고, 그 효과와 한계를 수치로 평가하는 것이다.**

---

## 2. 테스트 목표

### 2.1 주요 목표

- Kubernetes ReplicaSet 자동 복구 검증
- 수동·자동 Pod 복구 시간 비교
- HPA CPU 기반 Scale-out / Scale-in 검증
- HPA OFF/ON 성능 비교
- 잘못된 Deployment의 Readiness 실패 재현
- Rolling Update의 기존 정상 Pod 유지 확인
- 수동 Rollback 및 완료 시간 측정
- Prometheus와 Alertmanager의 장애 탐지 확인
- 실제 측정 결과와 초기 예상 효과 비교
- 재현 가능한 테스트 스크립트 및 결과 보존

### 2.2 최종 달성 결과

| 목표 | 실제 결과 |
| --- | --- |
| Pod 자동 복구 | 성공 |
| 수동·자동 복구 시간 비교 | 각 3회 측정 |
| HPA Scale-out | 1 → 2 확인 |
| HPA Scale-in | 2 → 1 확인 |
| HPA OFF/ON 성능 측정 | 완료 |
| HPA 성능 개선 | 미입증 |
| Readiness 실패 재현 | 성공 |
| 기존 정상 Pod 유지 | 확인 |
| 수동 Rollback | 성공 |
| Prometheus Firing | 확인 |
| 서비스 전체 MTTR | 정량 측정 미완료 |
| 전체 서비스 Availability | 정량 측정 미완료 |

---

## 3. 테스트 대상

### 3.1 초기 계획

| 시나리오 | 대상 서비스 | 주요 검증 |
| --- | --- | --- |
| Pod Failure | productcatalogservice | Self-Healing |
| Resource Exhaustion | frontend | HPA 및 안정성 |
| Deployment Failure | paymentservice | 장애 탐지 및 Rollback |

### 3.2 실제 테스트 대상

| Test ID | 대상 | 검증 항목 |
| --- | --- | --- |
| TC-01 | ProductCatalog 실험 Pod | 수동·자동 Pod 복구 |
| TC-02 | frontend | gRPC 재연결 및 HTTP 회복 |
| TC-03 | productcatalog-auto | HPA 자동 확장·축소 |
| TC-04 | productcatalog-hpa Service | HPA OFF/ON gRPC 성능 |
| TC-05 | productcatalog-rollout | Readiness 실패 및 Rollback |
| TC-06 | alert-test-pod | Prometheus 장애 알림 |

### 대상 변경 이유

기존 Online Boutique의 핵심 서비스를 직접 변경하면 사용자 요청이나 서비스 간 통신에 영향을 줄 수 있다.

따라서 실제 테스트에서는 별도의 `recovery-test` Namespace에서 ProductCatalog 기반 실험용 Deployment를 사용하였다.

PaymentService에 잘못된 버전을 배포하는 계획은 Readiness Probe 오류를 통한 Deployment Failure 실험으로 변경하였다.

---

# 4. 공통 테스트 환경

## 4.1 AWS EKS 환경

| 항목 | 구성 |
| --- | --- |
| Cloud | AWS |
| Region | ap-northeast-2 |
| Cluster | auto-recovery-eks |
| Kubernetes | EKS 1.35 |
| Worker Node | t3.large × 2 |
| Node Group | Managed Node Group |
| Application | Online Boutique v0.10.7 |
| Monitoring | Prometheus / Grafana / Alertmanager |
| Resource Metrics | Metrics Server |
| 부하 도구 | k6 |
| 실행 환경 | Windows PowerShell / EKS 내부 Job |

## 4.2 Namespace 구분

| Namespace | 용도 |
| --- | --- |
| online-boutique | 실제 쇼핑몰 서비스 |
| recovery-test | 장애 및 부하 테스트 |
| monitoring | 모니터링 및 알림 |
| argocd | GitOps 배포 관리 |

## 4.3 공통 통제 원칙

- 동일한 Kubernetes 클러스터 사용
- 동일한 ProductCatalog 이미지 버전 사용
- 동일한 테스트 스크립트 사용
- 동일한 CPU / Memory Request 및 Limit 유지
- 동일한 목표 요청 속도와 테스트 시간 사용
- 비교하고자 하는 HPA 적용 여부만 변경

단, 수동·자동 Pod 복구 실험은 실행 및 측정 조건이 완전히 동일하지 않았으므로 해석 시 해당 차이를 고려하였다.

---

# 5. 공통 측정 지표

| 지표 | 설명 | 측정 상태 |
| --- | --- | --- |
| MTTD | 장애 발생부터 탐지까지 평균 시간 | 미측정 |
| MTTR | 장애 발생부터 서비스 정상화까지 평균 시간 | 부분 검증 |
| Pod Ready Time | Pod가 Ready에 도달하는 데 걸린 시간 | 측정 |
| Recovery Time | 실험별 정상 상태 복귀 시간 | 부분 측정 |
| P95 Latency | 요청 응답시간 95백분위수 | 측정 |
| Error Rate | 실패 요청 비율 | k6 실험 측정 |
| RPS | 초당 요청 수 | 측정 |
| Availability | 서비스 가용률 | 장기간 측정 미실시 |
| Replica Count | Pod Replica 변화 | 측정 |
| CPU Utilization | CPU Request 기준 사용률 | HPA 검증 |
| Restart Count | 컨테이너 재시작 횟수 | 상태 확인, 별도 성능 분석 미실시 |

---

# 6. 시간 측정 기준

## 6.1 초기 공통 설계

```
T0 = 장애 발생 시각
T1 = Monitoring에서 최초 장애 탐지 시각
T2 = 수동/자동 복구 동작 시작
T3 = Pod 또는 Deployment Ready 시각
T4 = 실제 사용자 요청 정상화 시각
```

계획했던 계산 방식은 다음과 같다.

```
Detection Time = T1 - T0

Service Recovery Time = T4 - T0
```

반복 측정 시 각 소요 시간의 평균을 MTTD 또는 MTTR로 산출한다.

## 6.2 실제 측정 기준

이번 프로젝트에서는 다음과 같은 측정값을 확보하였다.

| 실험 | 측정 기준 |
| --- | --- |
| Pod 수동 복구 | 수동 복구 절차 시작부터 Ready 확인까지 |
| Pod 자동 복구 | 장애 주입 후 대체 Pod Ready 확인까지 |
| Frontend gRPC 복구 | 장애 이후 HTTP 정상 응답 회복 |
| Deployment Rollback | 롤백 명령 실행부터 Rollout 완료 확인까지 |
| Prometheus Alert | Firing 상태 확인, 시간 차이 미측정 |

**Pod Ready 시간과 서비스 전체 MTTR은 서로 다른 지표**이므로 구분하여 기록하였다.

---

# 7. 테스트 전 Baseline

## 7.1 목적

장애 및 부하 테스트 이전에 정상 상태의 기준을 확인한다.

## 7.2 확인 항목

- Worker Node Ready
- Deployment 및 Pod Ready
- Service 통신
- Metrics Server 정상
- HPA 상태
- Prometheus 모니터링 상태
- 기본 gRPC 요청 성공 여부

## 7.3 실제 사전 검증

Online Boutique 11개 Deployment가 정상 실행되고, Argo CD Application이 Synced / Healthy 상태임을 확인하였다.

또한 EKS 내부에서 k6 gRPC Smoke Test를 수행하여 ProductCatalog Service에 요청을 전달할 수 있는지 확인하였다.

## 7.4 Baseline의 한계

별도의 5분간 정상 트래픽 Baseline에 대해 CPU, Memory, P95, RPS를 통합 기록한 자료는 확보하지 않았다.

따라서 실제 실험 조건과 k6 결과를 기준으로 성능을 비교하되, 별도의 장기 Baseline 수치가 존재한다고 기록하지 않는다.

---

# 8. Scenario 01 — Pod Failure

## 8.1 목적

Pod를 강제로 삭제한 후 Kubernetes ReplicaSet이 신규 Pod를 자동 생성하는 과정을 검증하고, 수동 복구 방식과 Ready 도달 시간을 비교한다.

## 8.2 사전 조건

- AWS EKS 정상 동작
- ProductCatalog 실험용 Pod Ready
- 자동 복구 대상 Deployment 정상
- Readiness / Liveness Probe 정상
- 복구 시간 측정 스크립트 준비

## 8.3 장애 발생 방법

```
kubectl delete pod <pod-name> -n recovery-test
```

## 8.4 자동 복구 흐름

```
기존 Pod 정상
      ↓
Pod 강제 삭제
      ↓
Desired Replica 불일치
      ↓
ReplicaSet 자동 감지
      ↓
새 Pod 생성
      ↓
Readiness Probe 성공
      ↓
새 Pod Ready
```

## 8.5 실제 측정 결과

| 회차 | 수동 복구 | 자동 복구 |
| --- | --- | --- |
| 1회 | 34.358초 | 4.183초 |
| 2회 | 12.013초 | 4.144초 |
| 3회 | 10.933초 | 2.670초 |
| 평균 | **19.101초** | **3.666초** |

## 8.6 결과 분석

자동 복구 방식의 평균 Pod Ready 도달 시간은 수동 복구 대비 약 80.8% 짧게 측정되었다.

수동 복구는 운영자의 개입과 복구 명령 실행에 영향을 받지만, 자동 복구에서는 ReplicaSet이 원하는 Replica 수를 유지하도록 대체 Pod를 생성한다.

다만 수동과 자동의 실험 조건이 완전히 같지 않으므로 이 결과를 동일 조건의 전체 서비스 MTTR 개선율로 단정하지 않는다.

## 8.7 성공 기준 평가

| 성공 기준 | 결과 |
| --- | --- |
| 새 Pod 자동 생성 | 달성 |
| Readiness 복귀 | 달성 |
| Ready 도달 시간 측정 | 달성 |
| 수동·자동 비교 | 달성 |
| 사용자 요청 정상화 시간 비교 | 부분 검증 |
| 전체 서비스 MTTR 개선 | 추가 검증 필요 |

---

# 9. Scenario 02 — Resource Exhaustion / HPA

## 9.1 목적

CPU 부하 증가 시 HPA가 Deployment의 Replica 수를 자동으로 확장·축소하는지 검증하고, HPA 적용 전후의 응답 성능을 비교한다.

## 9.2 테스트 대상

| 항목 | 설정 |
| --- | --- |
| Deployment | productcatalog-auto |
| Namespace | recovery-test |
| HPA Target | CPU 60% |
| minReplicas | 1 |
| maxReplicas | 3 |
| CPU Request | 100m |
| CPU Limit | 200m |

## 9.3 부하 방식

EKS 내부의 k6 Job에서 ProductCatalog gRPC API를 호출하였다.

| 항목 | 조건 |
| --- | --- |
| 부하 모델 | Constant Arrival Rate |
| 요청 속도 | 100 RPS |
| Duration | 180초 |
| Pre-allocated VUs | 20 |
| Max VUs | 40 |
| gRPC API | ListProducts |
| HPA OFF | Replica 1 |
| HPA ON | CPU 기반 자동 확장 |

## 9.4 예상 동작

```
k6 요청 증가
      ↓
CPU 사용률 상승
      ↓
HPA CPU Target 초과
      ↓
Desired Replica 증가
      ↓
새 Pod 생성
      ↓
Scale-out 확인
```

## 9.5 실제 HPA 동작

- 초기 Replica 1개
- CPU 사용률 증가
- `SuccessfulRescale` 이벤트 확인
- Replica 2개로 증가
- 부하 종료 이후 Replica 1개로 축소

## 9.6 HPA OFF/ON 성능 비교

| 항목 | HPA OFF | HPA ON |
| --- | --- | --- |
| 총 요청 | 18,001 | 18,001 |
| 평균 gRPC 응답 | 0.853ms | 0.921ms |
| P95 | 1.25ms | 1.38ms |
| 최대 응답 | 7.88ms | 13.56ms |
| 처리량 | 약 100 RPS | 약 100 RPS |
| 오류율 | 0% | 0% |

## 9.7 결과 분석

HPA의 CPU 기반 자동 확장·축소는 정상 동작하였다.

그러나 HPA ON 상태에서 P95는 1.38ms로 측정되어 OFF의 1.25ms보다 높았다.

이는 100 RPS 조건에서 단일 Pod도 모든 요청을 정상 처리했으며, 기존 gRPC 연결 재사용으로 인해 신규 Pod로 요청이 충분히 분산되지 않았을 가능성이 있기 때문이다.

다만 이러한 원인이 확정된 것은 아니므로 추가 검증이 필요하다.

**최종 판단: HPA 기능 검증 성공, 성능 개선 효과 미입증**

## 9.8 성공 기준 평가

| 성공 기준 | 결과 |
| --- | --- |
| CPU 기반 HPA 동작 | 달성 |
| Replica 증가 | 달성 |
| Scale-in | 달성 |
| P95 측정 | 달성 |
| Error Rate 측정 | 달성 |
| HPA ON 성능 개선 | 미달성 |
| 고부하 병목 개선 | 추가 검증 필요 |

---

# 10. Scenario 03 — Deployment Failure

## 10.1 목적

잘못된 Deployment가 배포되는 상황에서 Kubernetes Readiness Probe와 Rolling Update가 기존 정상 Pod를 유지하는지 검증하고 수동 Rollback 시간을 측정한다.

## 10.2 초기 계획과 변경

**초기 계획**

PaymentService의 `v2-broken` 이미지를 배포하고 실제 결제 요청 실패를 관찰할 예정이었다.

**실제 실험**

별도의 `productcatalog-rollout` Deployment에 잘못된 Readiness Probe 설정을 적용하였다.

## 10.3 장애 주입 조건

정상 포트:

```
readinessProbe:
  grpc:
    port: 3550
```

장애 포트:

```
readinessProbe:
  grpc:
    port: 3551
```

## 10.4 Rolling Update 설정

| 항목 | 값 |
| --- | --- |
| Deployment | productcatalog-rollout |
| Namespace | recovery-test |
| Replica | 1 |
| maxSurge | 1 |
| maxUnavailable | 0 |
| progressDeadlineSeconds | 120 |

## 10.5 실제 진행 흐름

```
기존 정상 Pod
      ↓
잘못된 Revision 배포
      ↓
신규 Pod 생성
      ↓
Readiness 실패
      ↓
신규 Pod 0/1 Ready
      ↓
기존 정상 Pod 유지
      ↓
ProgressDeadlineExceeded
      ↓
수동 Rollback
      ↓
정상 Revision 복귀
```

## 10.6 실제 검증 결과

| 항목 | 결과 |
| --- | --- |
| 신규 Pod | 0/1 Ready |
| 기존 Pod | 1/1 Ready |
| Deployment Available | True |
| Deployment Progressing | False |
| 실패 이유 | ProgressDeadlineExceeded |
| Rollback 방식 | 수동 |
| Rollback Time | 16.360초 |

## 10.7 복구 명령어

```
kubectl rollout undo deployment/productcatalog-rollout -n recovery-test
```

상태 확인:

```
kubectl rollout status deployment/productcatalog-rollout -n recovery-test
```

## 10.8 성공 기준 평가

| 성공 기준 | 결과 |
| --- | --- |
| 잘못된 배포 재현 | 달성 |
| Readiness 실패 확인 | 달성 |
| 기존 정상 Pod 유지 | 달성 |
| 이전 Revision 복귀 | 달성 |
| Rollback Time 측정 | 달성 |
| 사용자 오류율 측정 | 미수행 |
| 자동 Rollback | 미구현 |

---

# 11. 반복 테스트

## 11.1 초기 계획

각 장애 시나리오에서 최소 3회 반복을 목표로 하였다.

## 11.2 실제 수행 횟수

| 실험 | 수행 횟수 |
| --- | --- |
| Pod 수동 복구 | 3회 |
| Pod 자동 복구 | 3회 |
| Frontend 개선 전 | 1회 |
| Frontend 개선 후 | 3회 |
| HPA OFF 부하 테스트 | 1회 |
| HPA ON 부하 테스트 | 1회 |
| Deployment Rollback | 1회 |
| Pod NotReady Alert | Firing 확인, 반복 횟수 별도 집계 없음 |

## 11.3 검증 한계

Pod 복구 외의 실험에서는 반복 측정 횟수가 제한적이었다.

따라서 HPA 성능 차이나 Rollback 시간의 일반적인 평균값을 산출하지 않고 실험에서 관측한 결과로 기록하였다.

---

# 12. 테스트 결과 기록 양식

실제 프로젝트에서 테스트별로 다음 항목을 기록하였다.

| 항목 | 기록 내용 |
| --- | --- |
| Test ID | TC-01 ~ TC-06 |
| Test Target | ProductCatalog / Frontend / Alert Pod |
| Failure Type | Pod 삭제, CPU 부하, Probe 오류 등 |
| Test Condition | Replica, HPA, RPS, Duration |
| Recovery Result | Ready 상태 및 복구 여부 |
| Pod Ready Time | 측정 가능한 실험에서 기록 |
| Rollback Time | 16.360초 |
| P95 | k6 결과 기록 |
| Error Rate | k6 결과 기록 |
| HPA Replica | 1 → 2 → 1 |
| Alert State | Firing 확인 |
| Evidence | kubectl 출력, 로그, Prometheus / Alertmanager 화면 |

테스트별 상세 결과는 별도의 장애 테스트 결과 보고서에서 관리한다.

---

# 13. Grafana 및 테스트 증거 수집

## 13.1 증거 수집 목표

장애 발생 전후 상태 변화와 복구 과정을 확인할 수 있는 자료를 확보한다.

## 13.2 실제 수집 자료

- Pod 자동 복구 측정 결과
- HPA 상태 및 SuccessfulRescale 이벤트
- HPA OFF/ON k6 로그
- Deployment ProgressDeadlineExceeded
- Rollback 완료 결과
- Prometheus Firing 화면
- Alertmanager 알림 그룹 화면

## 13.3 증거 자료 보관

GitHub Repository의 테스트 디렉터리와 결과 파일을 통해 주요 실험 기록을 보존하였다.

```
tests/
├── recovery-comparison/
├── hpa/
├── rollout/
├── alerts/
└── results/
```

## 13.4 증거 수집 한계

모든 장애 시나리오의 장애 발생부터 복구 완료까지를 하나의 Grafana Dashboard에서 연속적으로 시각화한 자료는 확보하지 않았다.

따라서 명령어 출력, 실험 로그 및 Prometheus/Alertmanager 화면을 조합하여 검증하였다.

---

# 14. 명령어 및 실행 로그 기록

## 14.1 Kubernetes 상태 확인

```
kubectl get pods -n recovery-test
kubectl get deployments -n recovery-test
kubectl get events -n recovery-test
```

## 14.2 Pod 장애 실험

```
kubectl delete pod <pod-name> -n recovery-test
kubectl get pods -n recovery-test -w
```

## 14.3 HPA 확인

```
kubectl get hpa -n recovery-test
kubectl describe hpa productcatalog-auto -n recovery-test
kubectl top pods -n recovery-test
```

## 14.4 Deployment Rollback

```
kubectl rollout history deployment/productcatalog-rollout -n recovery-test
kubectl rollout status deployment/productcatalog-rollout -n recovery-test
kubectl rollout undo deployment/productcatalog-rollout -n recovery-test
```

## 14.5 k6 결과 확인

```
kubectl logs job/k6-hpa-off -n recovery-test
kubectl logs job/k6-hpa-on -n recovery-test
```

## 14.6 Monitoring 확인

```
kubectl get pods -n monitoring
kubectl get prometheusrules -n monitoring
```

---

# 15. 테스트 통제 조건

## 15.1 비교 원칙

동일한 환경에서 비교하고자 하는 독립 변수만 변경하는 것을 목표로 하였다.

## 15.2 HPA OFF/ON 통제 조건

| 항목 | 통제 |
| --- | --- |
| Cluster | 동일 |
| 서비스 | ProductCatalog |
| 이미지 버전 | 동일 |
| CPU Request / Limit | 동일 |
| k6 Script | 동일 |
| 요청 속도 | 100 RPS |
| Duration | 180초 |
| Target Service | 동일 |
| HPA 적용 | OFF / ON |

## 15.3 통제의 한계

HPA OFF/ON에서 설정된 부하 조건은 동일했지만, 실제 CPU 사용률, 노드 자원 상태, 신규 Pod 요청 분산 및 실행 시점의 환경 변동까지 완전히 통제한 것은 아니다.

또한 Pod 수동·자동 복구 비교에서는 실행 절차의 차이가 존재하였다.

따라서 결과를 해석할 때 실험 조건의 차이와 반복 횟수의 한계를 함께 고려한다.

---

# 16. 테스트 결과 판단 원칙

## 16.1 기능 검증과 성능 개선 구분

자동화 기능이 동작한 사실과 성능이 개선된 사실은 구분하여 평가한다.

### Pod 자동 복구

ReplicaSet 자동 복구는 정상 동작하였고 수동 방식보다 평균 Ready 도달 시간이 짧았다.

### HPA

Scale-out / Scale-in은 성공했지만 P95 개선은 확인되지 않았다.

### Deployment

기존 정상 Pod 유지와 수동 Rollback은 성공했지만 자동 Rollback은 구현하지 않았다.

### Monitoring

Prometheus Firing을 확인했지만 MTTD를 정량 측정하지 않았다.

## 16.2 최종 평가 원칙

다음 요소를 함께 기록한다.

1. 실험 조건
2. 장애 발생 방식
3. Kubernetes 동작
4. 측정 결과
5. 검증 한계
6. 향후 개선 방향

---

# 17. 최종 구성 및 미검증 항목

| 항목 | 최종 상태 |
| --- | --- |
| k6 부하 모델 | Constant Arrival Rate |
| k6 목표 부하 | 100 RPS |
| k6 Duration | 180초 |
| k6 Pre-allocated VUs | 20 |
| k6 Max VUs | 40 |
| HPA CPU Target | 60% |
| HPA Replica | Min 1 / Max 3 |
| HPA 실제 확장 | 1 → 2 |
| HPA 실제 축소 | 2 → 1 |
| Pod 복구 반복 | 수동/자동 각 3회 |
| Rollback 방식 | kubectl rollout undo |
| Automatic Rollback | 미구현 |
| MTTD | 미측정 |
| 서비스 전체 MTTR | 미측정 |
| 장기간 Availability | 미측정 |
| HPA 성능 개선 | 미입증 |
| Pod NotReady Alert | Firing 확인 |

---

# 18. 테스트 완료 기준 및 최종 평가

## 18.1 기능 검증 기준

| 항목 | 결과 |
| --- | --- |
| Pod Failure | 완료 |
| 수동·자동 Pod 복구 비교 | 완료 |
| HPA 확장·축소 | 완료 |
| HPA OFF/ON 성능 측정 | 완료 |
| Deployment Failure | 완료 |
| 수동 Rollback | 완료 |
| Prometheus Pod NotReady Alert | 완료 |

## 18.2 정량 검증 기준

| 항목 | 결과 |
| --- | --- |
| Pod Ready Time | 측정 완료 |
| HPA P95 | 측정 완료 |
| HPA Error Rate | 측정 완료 |
| HPA RPS | 측정 완료 |
| Rollback Time | 측정 완료 |
| MTTD | 미측정 |
| 전체 서비스 MTTR | 미측정 |
| Availability | 미측정 |
| 배포 장애 중 사용자 오류율 | 미측정 |

## 18.3 최종 평가

주요 Kubernetes 자동 복구 및 장애 대응 기능은 실험을 통해 검증하였다.

특히 Pod 자동 복구는 수동 복구보다 평균 Ready 도달 시간이 짧게 측정되었으며, HPA의 CPU 기반 확장과 Deployment의 비정상 배포 차단 동작도 확인하였다.

다만 일부 정량 지표와 반복 측정 기준은 초기 계획을 모두 충족하지 못하였다.

이에 테스트 단계는 **핵심 기능 검증 완료, 일부 정량 검증 미완료**로 평가하였다.

---

# 19. 최종 결과물

## 19.1 Pod Failure

| 방식 | 평균 Pod Ready 도달 시간 |
| --- | --- |
| 수동 복구 | 19.101초 |
| 자동 복구 | 3.666초 |
| 시간 단축 | 약 80.8% |

## 19.2 Resource Exhaustion / HPA

| 항목 | HPA OFF | HPA ON |
| --- | --- | --- |
| P95 | 1.25ms | 1.38ms |
| Error Rate | 0% | 0% |
| HPA Scale-out | 해당 없음 | 1 → 2 |

## 19.3 Deployment Failure

| 항목 | 결과 |
| --- | --- |
| 신규 Pod | 0/1 Ready |
| 기존 Pod | 1/1 Ready |
| Deployment 실패 | ProgressDeadlineExceeded |
| 수동 Rollback | 16.360초 |

## 19.4 Monitoring Alert

| 항목 | 결과 |
| --- | --- |
| 장애 유형 | Pod NotReady |
| Prometheus | Firing 확인 |
| Alertmanager | 관련 알림 그룹 확인 |
| MTTD | 미측정 |

## 19.5 최종 결론

**같은 Pod 장애 상황에서 수동 복구는 평균 19.101초가 소요된 반면, Kubernetes 자동 복구는 평균 3.666초로 약 80.8% 짧게 측정됐다. 또한 HPA의 자동 확장, 잘못된 배포의 차단 및 Prometheus 장애 탐지를 검증했다. 결국 안정적인 인프라의 핵심은 장애 발생 이후의 수동 대응에만 의존하는 것이 아니라, 시스템이 원하는 상태를 스스로 유지하고 그 복구 효과를 실제 수치로 검증할 수 있도록 설계하는 데 있다.**
