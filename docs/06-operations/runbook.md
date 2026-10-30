## 1. Pod 비정상 상태 대응

**증상:** Pod가 `Pending`, `CrashLoopBackOff`, `NotReady` 또는 재시작을 반복하는 상태

### 점검 명령어

```bash
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
kubectl get deployment -n <namespace>
```

### 대응 절차

1. Pod 상태 및 이벤트 확인
2. 로그를 통해 오류 원인 분석
3. Readiness / Liveness Probe 확인
4. CPU 및 Memory 사용량 확인
5. Deployment / ReplicaSet 상태 확인
6. 복구 후 Ready 상태 및 서비스 정상 여부 확인

## 2. HPA 확장 장애 대응

```bash
kubectl get hpa -n recovery-test
kubectl describe hpa productcatalog-auto -n recovery-test
kubectl top pods -n recovery-test
kubectl get deployment productcatalog-auto -n recovery-test
```

CPU 메트릭 수집 여부, HPA Target 및 Pod Resources Request 설정을 확인한다.

## 3. 배포 실패 대응

```bash
kubectl rollout status deployment/productcatalog-rollout -n recovery-test
kubectl rollout history deployment/productcatalog-rollout -n recovery-test
kubectl describe deployment productcatalog-rollout -n recovery-test
kubectl rollout undo deployment/productcatalog-rollout -n recovery-test
```

롤백 후 기존 정상 설정의 Pod가 Ready 상태인지 확인한다.

## 4. 모니터링 및 알림 점검

```bash
kubectl get pods -n monitoring
kubectl get prometheusrules -n monitoring
kubectl get prometheus -n monitoring
```

Prometheus 알림 상태와 Alertmanager 전달 여부를 확인하고, 장애 조건이 제거된 후 알림 해제 상태를 점검한다.
