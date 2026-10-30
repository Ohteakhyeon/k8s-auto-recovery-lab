# 장애를 발견하는 인프라에서, 스스로 복구하는 인프라로

### Kubernetes 기반 장애 탐지·자동 복구 체계 구축 및 MTTR 개선 검증

> **같은 Pod 장애 상황에서 수동 복구는 평균 19.101초가 소요된 반면, Kubernetes 자동 복구는 평균 3.666초로 약 80.8% 짧게 측정되었습니다.**

## 1. 프로젝트 개요

### 문제 정의

일반적인 수동 장애 대응에서는 운영자가 장애를 확인하고 원인을 분석한 뒤 복구 명령을 수행해야 합니다.

이 과정에서 복구 시간이 길어질 수 있으며, 운영자의 개입 여부에 따라 대응 결과도 달라집니다.

본 프로젝트에서는 Kubernetes의 Self-Healing 기능을 활용해 장애 복구를 자동화하고, 실제 장애를 재현하여 **수동 복구와 자동 복구의 차이를 정량적으로 검증**했습니다.

| 항목 | 내용 |
|---|---|
| 프로젝트 유형 | 개인 프로젝트 |
| 기간 | 2026.10.13 ~ 2026.10.28 (주요 구축·실험) |
| 실습 환경 | AWS EKS / Kubernetes 1.35 |
| 애플리케이션 | Google Online Boutique v0.10.7 |
| 핵심 기술 | Kubernetes, Terraform, GitHub Actions, Argo CD, Prometheus, Grafana, k6 |
| 핵심 검증 | Pod 자동 복구, HPA, Deployment Rollback, 장애 알림 |

---

## 2. 시스템 아키텍처

<img width="1024" height="1536" alt="전체아키텍처" src="https://github.com/user-attachments/assets/a5b75251-8afa-4da2-8da0-9915748a6a3f" />

---

**구성요소별 역할**

- **Terraform:** VPC, IAM, EKS, Managed Node Group 구성 및 관리
- **GitHub Actions + Amazon ECR:** 애플리케이션 이미지 빌드 및 저장
- **Argo CD:** GitOps 기반 Kubernetes 배포 관리
- **ReplicaSet:** Pod 장애 발생 시 자동 재생성
- **HPA:** CPU 사용률을 기준으로 Replica 자동 조정
- **Readiness Probe:** 요청 처리 준비가 되지 않은 Pod 제외
- **Prometheus + Grafana + Alertmanager:** 상태 관측 및 장애 알림
- **k6:** gRPC 부하 테스트 및 응답 성능 측정

---

## 3. 핵심 구현

### ① Kubernetes Self-Healing

Pod가 삭제되면 ReplicaSet이 원하는 Replica 수를 유지하기 위해 새 Pod를 자동 생성하도록 구성했습니다.

```text
Pod Failure
    ↓
ReplicaSet 감지
    ↓
대체 Pod 자동 생성
    ↓
Readiness Probe 통과
    ↓
Pod Ready
```

수동 복구 방식과 ReplicaSet 자동 복구 방식의 Pod Ready 도달 시간을 각각 3회 측정했습니다.

### ② HPA 기반 자동 확장

Metrics Server와 HPA를 연계하여 CPU 사용률에 따라 Pod 수를 자동 조정하도록 구성했습니다.

- CPU Target: 60%
- Replica: Min 1 / Max 3
- 실제 Scale-out: 1 → 2
- 실제 Scale-in: 2 → 1

### ③ 배포 실패 대응

Readiness Probe 포트를 의도적으로 잘못 설정하여 신규 Pod가 Ready 상태에 도달하지 못하는 상황을 재현했습니다.

```text
잘못된 Deployment
       ↓
신규 Pod NotReady
       ↓
기존 정상 Pod 유지
       ↓
ProgressDeadlineExceeded
       ↓
수동 Rollback
       ↓
정상 Revision 복구
```

### ④ 모니터링 및 장애 알림

Prometheus와 Alertmanager를 연계하여 비정상 Pod 상태를 감지하도록 구성했습니다.

실험용 Pod의 Readiness 실패를 유도한 결과, `RecoveryTestPodNotReady` 알림이 Firing 상태로 전환되고 Alertmanager에 표시되는 것을 확인했습니다.

---

## 4. 장애 테스트 결과

### 4.1 Pod Failure — 수동 복구 vs 자동 복구

| 회차 | 수동 복구 | 자동 복구 |
|---|---:|---:|
| 1회 | 34.358초 | 4.183초 |
| 2회 | 12.013초 | 4.144초 |
| 3회 | 10.933초 | 2.670초 |
| **평균** | **19.101초** | **3.666초** |

**평균 Pod Ready 도달 시간 약 80.8% 단축**

다만 수동·자동 실험의 일부 실행 조건에 차이가 있으므로, 이 수치를 서비스 전체 MTTR의 직접적인 개선율로 해석하지 않았습니다.

### 4.2 HPA — OFF vs ON

ProductCatalog gRPC API에 100 RPS 부하를 180초간 발생시켜 성능을 비교했습니다.

| 항목 | HPA OFF | HPA ON |
|---|---:|---:|
| 총 요청 | 18,001 | 18,001 |
| P95 Latency | 1.25ms | 1.38ms |
| Error Rate | 0% | 0% |
| 자동 확장 | 없음 | 1 → 2 |

**HPA 자동 확장은 성공했으나, 해당 부하 조건에서 P95 성능 개선은 확인되지 않았습니다.**

### 4.3 Deployment Failure

| 검증 항목 | 결과 |
|---|---|
| 신규 Pod | NotReady |
| 기존 Pod | Ready 유지 |
| 배포 실패 감지 | ProgressDeadlineExceeded |
| 복구 방식 | 수동 Rollback |
| Rollback 소요 시간 | 16.360초 |

### 4.4 장애 알림

| 검증 항목 | 결과 |
|---|---|
| 장애 상황 | Pod NotReady |
| Prometheus Alert | Firing 확인 |
| Alertmanager | 알림 그룹 확인 |
| MTTD | 정량 측정 미완료 |

---

## 5. 결과 분석 및 한계

이번 프로젝트를 통해 다음 사항을 검증했습니다.

- ReplicaSet의 자동 Pod 재생성과 수동 대비 Ready 도달 시간 차이
- HPA의 CPU 기반 Scale-out / Scale-in
- Readiness Probe를 활용한 비정상 신규 Pod 차단
- Kubernetes Deployment의 수동 Rollback
- Prometheus와 Alertmanager의 장애 탐지

반면 HPA에 의한 응답시간 개선, 자동 Rollback, 서비스 전체 MTTD·MTTR 및 Availability는 완전히 검증하지 못했습니다.

특히 **Kubernetes의 자동화 기능이 정상 동작하는 것과 실제 서비스 성능이 개선되는 것은 별개**라는 점을 확인했습니다.

---

## 6. 최종 결론

**수동 대응에 의존하던 Pod 복구 과정을 Kubernetes의 ReplicaSet으로 자동화하여 평균 Ready 도달 시간을 19.101초에서 3.666초로 줄였습니다.**

또한 HPA, Readiness Probe, Rolling Update 및 Prometheus를 연계하여 장애 유형에 따라 Kubernetes가 상태를 유지하고 복구하는 과정을 검증했습니다.

이를 통해 단순히 서비스를 배포하는 것이 아니라 **장애 발생 시 시스템이 어떻게 반응하고, 어떤 방식으로 복구하며, 그 효과를 어떻게 측정해야 하는지**에 대한 운영 경험을 확보했습니다.

---

## 7. 상세 문서

프로젝트 설계 과정과 실험 방법, 실제 사용한 명령어 및 결과는 별도 문서로 정리했습니다.

- 프로젝트 기획서
- 전체 아키텍처 설계서
- Docker 설계서
- Kubernetes 설계서
- Terraform / AWS 설계서
- CI/CD 설계서
- Monitoring 설계서
- 장애 테스트 계획서
- 장애 테스트 결과 보고서
- Runbook / 트러블슈팅

**Notion:** https://locrian-birthday-9a8.notion.site/3f790fbea2d28085918aeae7d9770c47
