## ▫︎  선정 오픈소스

- **Google Online Boutique (microservices-demo)**
    
    쇼핑몰 사용자 흐름을 구현한 클라우드 네이티브 데모 애플리케이션으로, 현재 공식 저장소 기준 11개의 마이크로서비스가 여러 언어로 구현되어 있으며 서비스 간 통신에 주로 gRPC를 사용
    
- **선정 이유**
    
    > Kubernetes 기반 장애 탐지 및 자동 복구 효과를 검증하기 위해서는 서비스 간 의존 관계가 존재하고 특정 서비스 장애가 실제 사용자 요청에 영향을 줄 수 있는 애플리케이션이 필요
    
    Online Boutique는 독립적인 마이크로서비스 구조와 Kubernetes 배포 예제를 제공하여 Pod 장애, 자원 고갈, 잘못된 배포 등의 장애 시나리오를 재현하기 적합하다고 판단
    > 
- **프로젝트 활용**
    
    
    | 장애 | 대상 | 검증 |
    | --- | --- | --- |
    | Pod Failure | productcatalogservice | Kubernetes Self-Healing |
    | Resource Exhaustion | frontend | HPA 및 서비스 안정성 |
    | Deployment Failure | paymentservice | 장애 탐지 및 Rollback |

---

## ▫︎  서비스 구조

| 서비스 | 역할 | 언어 |
| --- | --- | --- |
| frontend | 사용자 요청 처리 및 화면 제공 | Go |
| productcatalogservice | 상품 목록 및 상세 정보 제공 | Go |
| cartservice | 장바구니 관리 | C# |
| checkoutservice | 주문 처리 흐름 제어 | Go |
| paymentservice | 결제 처리 | Node.js |
| shippingservice | 배송 정보 처리 | Go |
| emailservice | 주문 이메일 처리 | Python |
| currencyservice | 환율 변환 | Node.js |
| recommendationservice | 상품 추천 | Python |
| adservice | 광고 제공 | Java |
| redis-cart | 장바구니 데이터 저장 | Redis |

---

## ▫︎  핵심 서비스 분석

| 대상 | 역할 | 실제 활용 |
| --- | --- | --- |
| frontend | 사용자 요청 진입점 | HTTP 응답 회복 및 gRPC 재연결 개선 검증 |
| productcatalogservice | 상품 조회 | Pod 장애 및 자동 복구 시나리오 |
| productcatalog-auto | 실험 전용 상품 조회 Deployment | ReplicaSet 자동 복구 및 HPA 검증 |
| productcatalog-rollout | 실험 전용 Deployment | Readiness 실패 및 Rollback 검증 |
| alert-test-pod | 알림 검증용 Pod | NotReady 장애 및 Prometheus Firing 확인 |
| checkoutservice | 주문 처리 및 서비스 간 호출 조정 | 서비스 의존 관계 분석 |

---

## ▫︎  서비스 의존 관계

```
User
  │
  ▼
frontend
  ├── productcatalogservice
  ├── cartservice
  ├── recommendationservice
  ├── currencyservice
  ├── adservice
  └── checkoutservice
       ├── cartservice
       ├── productcatalogservice
       ├── paymentservice
       ├── shippingservice
       └── emailservice
```

---

## ▫︎  장애 영향 분석

| 장애 대상 | 예상 영향 | 이번 프로젝트 검증 |
| --- | --- | --- |
| productcatalogservice | 상품 조회 실패 또는 응답 지연 | Pod 자동 재생성 및 응답 복구 |
| productcatalog-auto | CPU 부하 상승 | HPA Scale-out / Scale-in |
| productcatalog-rollout | 잘못된 배포로 신규 Pod 준비 실패 | 기존 Pod 유지 및 Rollback |
| alert-test-pod | Pod NotReady | Prometheus Firing 및 Alertmanager 수신 |
