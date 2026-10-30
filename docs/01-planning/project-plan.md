| 버전 | 변경 내용 | 상태 |
| --- | --- | --- |
| v0.1 | 프로젝트 배경, 문제 정의, 목표, 성공 기준 및 수행 범위 작성 | 완료 |
| v0.2 | AWS EKS 실습 환경, Kubernetes 운영 구성 및 장애 시나리오 구체화 | 완료 |
| v1.0 | 실제 구축 환경, 장애 테스트 결과, 성과 및 검증 한계 반영 | 최종 |

## 1. 프로젝트 기본 정보

| 항목 | 내용 |
| --- | --- |
| 프로젝트명 | 장애를 발견하는 인프라에서, 스스로 복구하는 인프라로 |
| 부제 | Kubernetes 기반 장애 탐지·자동 복구 체계 구축 및 MTTR 개선 검증 |
| 프로젝트 유형 | 개인 프로젝트 |
| 프로젝트 기간 | 2026.10.13 ~ 2026.10.28 (주요 구축·실험 기준) |
| GitHub | https://github.com/Ohteakhyeon/k8s-auto-recovery-lab |
| 사용 오픈소스 | Google Online Boutique (microservices-demo) |
| 주요 기술 | Docker, Kubernetes, Terraform, GitHub Actions, Argo CD, Prometheus, Grafana, k6 |

---

## 2. 프로젝트 배경

### 작성 목적

서비스 운영 환경에서는 단순히 애플리케이션을 정상적으로 배포하는 것뿐만 아니라, 장애를 빠르게 감지하고 복구하여 서비스 중단 시간을 최소화하는 것이 중요하다.

기존의 수동 장애 대응 방식은 운영자가 장애를 직접 인지하고 원인을 분석한 후 복구 작업을 수행해야 하므로, 대응 과정에서 시간과 운영 부담이 발생한다.

Kubernetes는 ReplicaSet, Deployment, Readiness/Liveness Probe, HPA 등의 기능을 통해 원하는 리소스 상태를 유지하고 장애 상황에 대응할 수 있다.

그러나 자동 복구 기능이 존재한다는 사실만으로 실제 복구 시간이 단축되거나 서비스 가용성이 향상되었다고 판단할 수는 없다.

이에 본 프로젝트에서는 AWS EKS 환경에 마이크로서비스 애플리케이션을 배포하고, 장애를 직접 재현하여 **수동 복구와 자동 복구의 소요 시간, CPU 기반 자동 확장, 배포 실패 대응 및 모니터링 동작을 검증**하고자 했다.

---

## 3. 문제 정의

> 서비스 장애 발생 시 수동 대응에 의존하면 복구 시간이 운영자의 개입과 판단에 영향을 받으며, 장애 유형에 맞는 복구 체계가 없다면 서비스 안정성을 유지하기 어려울 수 있다.
> 

### 세부 문제

| 문제 | 설명 | 검증 방향 |
| --- | --- | --- |
| 장애 탐지 지연 | 장애 상태를 운영자가 직접 확인해야 할 수 있음 | Prometheus 알림 |
| 수동 복구 의존 | Pod 장애 발생 시 운영자가 직접 재생성 | 수동/자동 시간 비교 |
| 복구 시간 편차 | 운영자의 확인·조치 시간에 따라 결과가 달라짐 | 반복 측정 |
| 자원 변화 대응 | CPU 부하 증가 시 단일 Pod의 처리 능력에 의존 | HPA 자동 확장 |
| 배포 장애 | 잘못된 설정이 신규 Pod의 정상 실행을 방해 | Readiness / Rolling Update |
| 운영 상태 불일치 | 실제 AWS 구성과 Terraform 관리 대상이 달라질 수 있음 | Terraform Import / Plan |

### 핵심 검증 질문

**Kubernetes의 자동 복구 기능은 수동 대응보다 얼마나 빠르게 정상 상태를 회복하며, 장애 유형별로 어떤 기능이 운영 안정성을 유지하는 데 기여하는가?**

---

## 4. 프로젝트 목표

### 최종 목표

AWS EKS 기반 애플리케이션 운영 환경에서 Kubernetes의 장애 대응 기능을 구현하고, 수동 복구와 자동 복구를 비교하여 효과와 한계를 정량적으로 검증한다.

### 세부 목표 및 달성 결과

| 영역 | 목표 | 최종 결과 |
| --- | --- | --- |
| Application | 오픈소스 쇼핑몰 서비스 배포 | 11개 Deployment 정상 실행 확인 |
| Docker | 컨테이너 이미지 분석 및 빌드 | Frontend 이미지 빌드 및 ECR 연계 |
| Kubernetes | Pod 자동 복구 구현 | ReplicaSet 자동 재생성 확인 |
| Recovery | 수동·자동 복구 시간 비교 | 평균 19.101초 / 3.666초 |
| HPA | CPU 기반 자동 확장·축소 | Replica 1 → 2 → 1 확인 |
| Deployment | 잘못된 배포 탐지 및 복구 | 실패 감지 및 수동 Rollback |
| Terraform | AWS 인프라 코드 관리 | 최종 Plan `No changes` |
| CI | GitHub Actions 구성 | 이미지 빌드 및 ECR 연동 |
| CD | Argo CD GitOps 배포 | Synced / Healthy 확인 |
| Monitoring | Prometheus / Grafana 구성 | 메트릭 및 모니터링 환경 구축 |
| Alerting | 장애 알림 검증 | Prometheus Firing 확인 |
| Load Test | 동일 조건의 성능 비교 | HPA OFF/ON P95 및 오류율 측정 |

---

## 5. 프로젝트 범위

### 5.1 구현 범위

| 영역 | 적용 내용 |
| --- | --- |
| Application | Google Online Boutique |
| Container | Docker 이미지 빌드 및 ECR 저장 |
| Orchestration | Kubernetes Deployment, Service, ReplicaSet, Probe, HPA |
| Infrastructure | AWS VPC, IAM, EKS, EC2 Node Group, EKS Add-on |
| IaC | Terraform |
| CI | GitHub Actions |
| CD | Argo CD |
| Monitoring | Prometheus, Grafana, kube-state-metrics, Node Exporter |
| Alerting | PrometheusRule, Alertmanager |
| Load Test | k6 기반 gRPC 부하 테스트 |
| Failure Test | Pod Failure, CPU 부하, Deployment Failure, Pod NotReady |

### 5.2 실험 환경 분리

실제 애플리케이션과 장애 테스트 환경을 분리하여 운영 환경에 대한 영향을 최소화했다.

- `online-boutique`: Google Online Boutique 서비스 운영
- `recovery-test`: Pod 복구, HPA, 배포 실패 및 알림 검증
- `monitoring`: Prometheus, Grafana, Alertmanager 운영
- `argocd`: GitOps 배포 관리

### 5.3 검증 범위의 한계

이번 프로젝트에서는 Kubernetes의 자동 복구 및 장애 대응 기능을 각각 검증했다.

다만 자동 롤백, 모든 마이크로서비스의 장애 전파, 완전한 서비스 무중단 보장, 서비스 전체 MTTR 및 Availability 개선은 실증하지 않았다.

---

## 6. 장애 시나리오

### Scenario 01 — Pod Failure

**목적**

ReplicaSet 자동 복구와 수동 복구 방식의 Pod Ready 도달 시간을 비교한다.

**장애 방식**

```bash
kubectl delete pod <pod-name> -n recovery-test
```

**검증 내용**

- Pod 강제 삭제
- 수동 재생성 및 자동 재생성
- 새 Pod Ready 도달 시간 측정
- 각 조건 3회 반복
- 평균 복구 시간 비교

**실제 결과**

| 방식 | 평균 Pod Ready 도달 시간 |
| --- | --- |
| 수동 | 19.101초 |
| 자동 | 3.666초 |

자동 복구 방식의 평균 소요 시간이 수동 방식 대비 약 80.8% 짧게 측정됐다.

단, 수동과 자동의 명령 실행 및 측정 조건에 차이가 있으므로 서비스 전체 MTTR의 직접적인 개선율로 해석하지 않는다.

---

### Scenario 02 — Resource Exhaustion / HPA

**목적**

CPU 부하 증가 시 HPA가 Replica 수를 자동으로 조정하는지 검증하고, HPA OFF/ON 성능을 비교한다.

**장애 및 부하 방식**

ProductCatalog 실험용 Deployment에 k6를 통해 gRPC 요청을 발생시켰다.

**검증 내용**

- CPU 사용률
- HPA 목표 사용률 60%
- Replica Scale-out / Scale-in
- P95 Latency
- 처리량(RPS)
- 오류율

**실제 결과**

CPU 사용률 상승에 따라 Replica가 1개에서 2개로 확장됐으며, 부하 종료 후 1개로 축소됐다.

100 RPS / 3분 조건의 P95는 HPA OFF 1.25ms, ON 1.38ms로 측정되어 성능 개선은 확인되지 않았다.

---

### Scenario 03 — Deployment Failure

**목적**

잘못된 배포가 진행될 때 Readiness Probe와 Rolling Update가 기존 정상 Pod를 유지하는지 검증한다.

**장애 방식**

ProductCatalog 실험용 Deployment의 Readiness Probe 포트를 정상 포트 3550에서 잘못된 포트 3551로 변경했다.

**검증 내용**

- 신규 Pod의 Ready 실패
- 기존 정상 Pod 유지
- Deployment 실패 판정
- 수동 Rollback
- 롤백 완료 시간

**실제 결과**

- 신규 Pod: `0/1 Ready`
- 기존 Pod: `1/1 Ready`
- 실패 판정: `ProgressDeadlineExceeded`
- 수동 Rollback: 16.360초

---

### Scenario 04 — Monitoring Alert

**목적**

Kubernetes 리소스 장애가 Prometheus의 알림 규칙에 의해 탐지되는지 확인한다.

**장애 방식**

실험용 Pod의 Readiness Probe를 잘못 설정하여 NotReady 상태를 유도했다.

**검증 내용**

- Pod NotReady
- PrometheusRule 로딩
- Firing 전환
- Alertmanager 알림 수신 확인

**실제 결과**

`RecoveryTestPodNotReady` 알림이 Firing으로 전환되는 것을 확인했으며, Alertmanager에서 관련 알림 그룹을 확인했다.

---

## 7. 측정 지표

### 7.1 계획 지표와 실제 측정 범위

| 지표 | 의미 | 최종 측정 상태 |
| --- | --- | --- |
| MTTD | 평균 장애 탐지 시간 | 정량 측정 미완료 |
| MTTR | 평균 장애 복구 시간 | Pod Ready 도달 시간 비교로 부분 검증 |
| Pod Ready Time | 새 Pod의 Ready 상태 도달 시간 | 측정 완료 |
| Recovery Time | 장애 또는 복구 작업 후 정상 상태까지의 시간 | 시나리오별 부분 측정 |
| P95 Latency | 요청 응답시간의 95백분위수 | 측정 완료 |
| Error Rate | 전체 요청 중 실패 비율 | k6 실험 측정 완료 |
| RPS | 초당 처리 요청 수 | 측정 완료 |
| CPU Utilization | CPU 요청량 대비 사용률 등 | HPA 검증 완료 |
| Availability | 전체 서비스 가용률 | 정량 측정 미완료 |
| Pod Restart | 컨테이너 재시작 및 Pod 상태 | 상태 확인, 통합 지표 미산출 |

### 7.2 주요 실측값

| 항목 | 측정 결과 |
| --- | --- |
| 수동 Pod Ready 평균 | 19.101초 |
| 자동 Pod Ready 평균 | 3.666초 |
| 평균 소요 시간 단축 | 약 80.8% |
| gRPC 재연결 개선 후 HTTP 회복 평균 | 6.389초 |
| HPA 최대 확인 Replica | 2개 |
| HPA OFF P95 | 1.25ms |
| HPA ON P95 | 1.38ms |
| HPA OFF/ON 오류율 | 모두 0% |
| 수동 Rollback | 16.360초 |
| Prometheus Firing | 확인 |

---

## 8. 성공 기준 및 최종 평가

| 초기 성공 기준 | 검증 결과 | 평가 |
| --- | --- | --- |
| 자동 복구가 수동보다 빠를 것 | 평균 19.101초 → 3.666초 | 달성  |
| Pod 장애 시 자동 재생성 | ReplicaSet 대체 Pod 생성 | 달성 |
| 장애 후 정상 상태 복귀 | 새 Pod Ready 확인 | 달성 |
| 장애 구간 P95 및 오류율 측정 | 일부 시나리오 및 HPA 부하 테스트 측정 | 부분 달성 |
| Prometheus/Grafana 모니터링 | 모니터링 환경 구성, Firing 확인 | 달성 |
| 잘못된 배포 복구 | 기존 Pod 유지, 수동 Rollback 성공 | 달성 |
| 동일한 조건에서 반복 테스트 | Pod 복구 3회, HPA 비교 각 1회 | 부분 달성 |
| 전체 서비스 MTTR 및 가용성 개선 | 서비스 전체 기준 정량 분석 부족 | 추가 검증 필요 |

### 최종 평가

Kubernetes의 ReplicaSet을 활용한 Pod 자동 복구, CPU 기반 HPA, Readiness Probe 및 Rolling Update, Prometheus 장애 알림 기능을 실제 EKS 환경에서 검증했다.

특히 자동 Pod 복구는 수동 방식보다 평균 Ready 도달 시간이 짧게 측정됐으며, 잘못된 배포 상황에서도 기존 정상 Pod가 유지되는 것을 확인했다.

반면 HPA 성능 개선, 실제 서비스 가용률 및 MTTD 등은 추가 검증이 필요한 항목으로 남았다.

이를 통해 자동화 기능의 단순 적용 여부뿐 아니라 **기능이 실제로 동작하는지, 어떤 효과를 측정할 수 있는지, 어떤 한계가 남아 있는지**를 구분하여 평가했다.

### 결론 한 줄

**같은 Pod 장애 상황에서 수동 복구는 평균 19.101초가 소요된 반면, Kubernetes 자동 복구는 평균 3.666초로 약 80.8% 단축됐다. 결국 안정적인 인프라의 핵심은 장애 발생 후 운영자가 대응하는 것뿐 아니라, 시스템이 스스로 정상 상태를 회복하도록 설계하는 데 있다.**
