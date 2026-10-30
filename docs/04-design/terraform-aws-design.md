| 버전 | 변경 내용 | 상태 |
| --- | --- | --- |
| v0.1 | AWS VPC, IAM, EKS, Node Group 및 Terraform 관리 범위 설계 | 완료 |
| v0.2 | 1차 EKS 구축, Worker Node 검증 및 Terraform Destroy 결과 반영 | 완료 |
| v0.3 | EKS 재구축, Online Boutique 배포 및 Metrics Server 구성 반영 | 완료 |
| v1.0 | 최종 AWS 아키텍처, Terraform State 관리, 검증 결과 및 개선 방향 정리 | 최종 |

---

## 1. 문서 목적

Kubernetes 기반 장애 탐지 및 자동 복구 환경을 구축하기 위해 사용한 AWS 인프라 구조와 Terraform 관리 방식을 정의한다.

AWS EKS를 중심으로 VPC, Subnet, IAM, Managed Node Group 및 EKS Add-on을 구성하고, Terraform을 통해 인프라 리소스의 생성·변경·삭제 과정을 관리하였다.

또한 Terraform 코드와 실제 AWS 리소스의 상태가 일치하는지 확인하고, Kubernetes 애플리케이션 및 모니터링 리소스와 AWS 인프라의 관리 영역을 구분하였다.

**핵심 목적은 AWS 인프라를 수동으로 구성하는 데 그치지 않고, 코드 기반으로 동일한 구성의 실습 환경을 관리하고 검증하는 것이다.**

---

## 2. 설계 목표

### 2.1 핵심 목표

- AWS EKS 기반 Kubernetes 클러스터 구축
- Terraform 기반 Infrastructure as Code 구현
- VPC 및 Subnet 네트워크 구성
- IAM Role 및 Policy 기반 권한 분리
- EKS Managed Node Group 운영
- Kubernetes 시스템 Add-on 구성
- Metrics Server 기반 HPA 실행 환경 확보
- AWS 인프라 생성·삭제 검증
- Terraform State와 실제 리소스의 일치 여부 검증
- AWS 인프라와 Kubernetes 애플리케이션 관리 영역 분리
- 실습 비용을 고려한 인프라 구성

### 2.2 설계 결정

| 설계 항목 | 실제 선택 | 선택 이유 |
| --- | --- | --- |
| Cloud Provider | AWS | EKS 기반 Kubernetes 운영 검증 |
| Kubernetes | Amazon EKS | 관리형 Control Plane 활용 |
| IaC | Terraform | 선언적 인프라 구성 및 State 관리 |
| Node | Managed Node Group | Worker Node 관리 복잡도 감소 |
| Subnet | Public Subnet × 2 | 단기 실습 및 NAT Gateway 비용 절감 |
| Node Instance | t3.large × 2 | 마이크로서비스 및 모니터링 실습 환경 |
| Registry | Amazon ECR | AWS 기반 이미지 저장 및 배포 |
| Metrics | EKS Metrics Server Add-on | HPA CPU 메트릭 제공 |
| Terraform Backend | Local State | 개인 실습 환경의 관리 단순화 |

### 2.3 초기 설계 변경

초기에는 Private Subnet에 Worker Node를 배치하고 NAT Gateway를 통해 외부 통신을 제공하는 구조를 계획하였다.

그러나 개인 프로젝트의 실습 비용과 인프라 관리 복잡도를 고려해 Public Subnet 기반 Worker Node 구성으로 변경하였다.

이는 실습을 위한 설계 선택이며, 운영 환경에서는 Private Subnet 및 최소 권한 네트워크 설계를 추가로 검토할 필요가 있다.

---

## 3. 전체 AWS 아키텍처

### 3.1 최종 구현 구조

```
Windows / PowerShell
        │
        ├── AWS CLI / IAM Identity Center
        ├── Terraform
        └── kubectl
                │
                ▼
        AWS ap-northeast-2
                │
                ▼
     EKS Managed Control Plane
         Kubernetes v1.35
                │
                ▼
        VPC 10.0.0.0/16
                │
        Internet Gateway
                │
         Public Route Table
                │
       ┌────────┴────────┐
       │                 │
Public Subnet A     Public Subnet B
 10.0.1.0/24         10.0.2.0/24
ap-northeast-2a     ap-northeast-2b
       │                 │
 Worker Node 1       Worker Node 2
    t3.large            t3.large
       │                 │
       └────────┬────────┘
                │
        Kubernetes Cluster
                │
      ┌─────────┼─────────────┐
      │         │             │
      ▼         ▼             ▼
Online       Monitoring    Recovery
Boutique     Components    Test
```

### 3.2 AWS 인프라 관리 구조

```
Terraform
   │
   ▼
AWS Infrastructure
   ├── VPC
   ├── Public Subnet × 2
   ├── Internet Gateway
   ├── Route Table / Route
   ├── Route Table Association
   ├── IAM Role / Policy Attachment
   ├── EKS Cluster
   ├── Managed Node Group
   ├── VPC CNI Add-on
   ├── Pod Identity Agent Add-on
   └── Metrics Server Add-on
```

### 3.3 최종 구현 범위

| 영역 | 구현 내용 |
| --- | --- |
| Network | VPC, Public Subnet, Internet Gateway, Route Table |
| IAM | Cluster Role, Node Role, VPC CNI Role |
| EKS | Managed Control Plane |
| Compute | Managed Node Group, t3.large × 2 |
| Networking Add-on | VPC CNI |
| Pod Identity | EKS Pod Identity Agent |
| Resource Metrics | Metrics Server |
| Application | Online Boutique |
| CI/CD | GitHub Actions / Argo CD |
| Monitoring | Prometheus / Grafana / Alertmanager |
| Testing | k6 / kubectl |

Terraform은 AWS 인프라 리소스를 관리하고, 애플리케이션 배포와 모니터링은 Kubernetes Manifest, Argo CD 및 Helm 등을 통해 별도로 관리하였다.

---

## 4. VPC 설계

### 4.1 역할

VPC는 EKS Worker Node와 Kubernetes Pod가 사용할 AWS 네트워크 환경을 제공한다.

### 4.2 실제 설정

| 항목 | 적용 값 |
| --- | --- |
| AWS Region | ap-northeast-2 |
| VPC CIDR | 10.0.0.0/16 |
| Availability Zone | 2개 |
| Public Subnet | 2개 |
| Private Subnet | 미구현 |
| DNS Support | Enabled |
| DNS Hostnames | Enabled |
| Internet Gateway | 사용 |

### 4.3 설계 이유

두 개의 Availability Zone에 Subnet을 구성해 Worker Node가 서로 다른 AZ에 배치될 수 있도록 하였다.

단일 AZ에 모든 Node를 배치하는 것보다 인프라 구성상 장애 영역을 분리할 수 있다는 장점이 있다.

다만 실제 AZ 장애를 발생시켜 서비스 가용성을 검증하지는 않았다.

### 4.4 검증 결과

Terraform을 통해 VPC 및 네트워크 리소스를 생성하였으며, EKS Worker Node 2개가 서로 다른 Subnet에 배치되고 Ready 상태에 도달하는 것을 확인하였다.

---

## 5. Subnet 설계

### 5.1 실제 구성

| Subnet | CIDR | AZ | 용도 |
| --- | --- | --- | --- |
| Public Subnet A | 10.0.1.0/24 | ap-northeast-2a | Worker Node |
| Public Subnet B | 10.0.2.0/24 | ap-northeast-2b | Worker Node |

두 Subnet에는 다음 설정을 적용하였다.

```
map_public_ip_on_launch = true
```

### 5.2 초기 설계와 실제 구현 비교

| 항목 | 초기 설계 | 실제 구현 |
| --- | --- | --- |
| Worker Node | Private Subnet | Public Subnet |
| Public Subnet | 외부 Load Balancer | Worker Node |
| NAT Gateway | 사용 계획 | 미사용 |
| Load Balancer | 도입 검토 | 필수 외부 진입점으로 구성하지 않음 |

### 5.3 변경 이유

짧은 실습을 반복하는 프로젝트 특성상 NAT Gateway의 고정 비용과 네트워크 구성 복잡도를 줄이고자 했다.

### 5.4 설계 한계

Public IPv4가 할당된 Worker Node는 인터넷 통신이 가능한 네트워크에 배치된다.

실제 외부 접근 가능 여부는 Security Group, 라우팅 및 관련 접근 제어 설정에 따라 결정된다.

향후 운영 환경에 가까운 아키텍처에서는 Private Subnet 기반 Worker Node 구성을 검토한다.

---

## 6. Route 설계

### 6.1 Public Route 구성

```
Worker Node
     │
     ▼
Public Subnet
     │
     ▼
Public Route Table
     │
     ▼
0.0.0.0/0 → Internet Gateway
     │
     ▼
Internet
```

### 6.2 실제 설정

| 구성요소 | 설정 |
| --- | --- |
| Internet Gateway | 생성 |
| Public Route Table | 생성 |
| 기본 Route | 0.0.0.0/0 → IGW |
| Route Table Association | Public Subnet 2개 |
| NAT Gateway | 미생성 |

### 6.3 검증 결과

Terraform으로 Route Table과 Subnet 연결을 생성하였다.

EKS Managed Node Group의 클러스터 가입과 시스템 Pod 실행을 확인하여 기본 네트워크 통신이 가능한 상태임을 검증하였다.

---

## 7. EKS Cluster 설계

### 7.1 역할

Amazon EKS는 Kubernetes Control Plane을 AWS 관리형 서비스로 제공한다.

사용자는 Worker Node와 애플리케이션을 관리하고, AWS는 Control Plane의 운영을 담당한다.

### 7.2 실제 설정

| 항목 | 적용 값 |
| --- | --- |
| Cluster Name | auto-recovery-eks |
| Kubernetes Version | 1.35 |
| Region | ap-northeast-2 |
| Control Plane | AWS Managed |
| Public Endpoint | Enabled |
| Private Endpoint | Enabled |
| Public Access CIDR | 실습 PC 공인 IP /32 |
| Authentication Mode | API_AND_CONFIG_MAP |
| Support Type | STANDARD |

### 7.3 접근 제어

Kubernetes API Public Endpoint의 접근 CIDR을 실습 PC의 공인 IP로 제한하였다.

단, Public Endpoint 접근 제한은 네트워크 수준의 통제이며 AWS IAM 및 Kubernetes RBAC 권한 관리를 대체하지 않는다.

### 7.4 EKS 연결 검증

```
aws eks update-kubeconfig `
  --region ap-northeast-2 `
  --name auto-recovery-eks `
  --profile k8s-lab
```

현재 Context 확인:

```
kubectl config current-context
```

Worker Node 확인:

```
kubectl get nodes -o wide
```

### 7.5 검증 결과

- EKS Cluster 생성 성공
- Kubernetes API 연결 성공
- Worker Node 2개 Ready
- Online Boutique 11개 Deployment 실행
- Kubernetes 장애 복구 및 HPA 실험 수행

---

## 8. Managed Node Group 설계

### 8.1 실제 설정

| 항목 | 적용 값 |
| --- | --- |
| Node Group | auto-recovery-eks-nodes |
| 관리 방식 | EKS Managed Node Group |
| Instance Type | t3.large |
| Capacity Type | ON_DEMAND |
| AMI | Amazon Linux 2023 x86_64 |
| Desired Size | 2 |
| Min Size | 2 |
| Max Size | 2 |
| Node Disk | 30GiB |
| Subnet | Public Subnet A/B |

### 8.2 검증 결과

`kubectl get nodes -o wide` 실행 결과 다음을 확인하였다.

- Worker Node 2개 모두 Ready
- 서로 다른 AZ에 Node 배치
- Amazon Linux 2023 사용
- Container Runtime으로 containerd 사용
- Kubernetes 시스템 Pod 정상 실행

### 8.3 Node Scaling과 HPA 구분

프로젝트에서는 Managed Node Group의 최소·희망·최대 크기를 모두 2개로 고정하였다.

따라서 실제 수행한 HPA 테스트는 **Node 개수를 늘리는 실험이 아니라 기존 Worker Node에서 Pod Replica 수를 조정하는 실험**이었다.

| 구분 | 적용 기능 | 결과 |
| --- | --- | --- |
| Pod Scaling | HPA | 1 → 2 → 1 |
| Node Scaling | Managed Node Group | 2개 고정 |
| Cluster Autoscaler | 미구성 | 미검증 |
| Karpenter | 미구성 | 미검증 |

Node 증설이나 교체에 의한 가용성 향상은 이번 실험에서 검증하지 않았다.

---

## 9. IAM 설계

### 9.1 역할 분리

| IAM Role | 용도 |
| --- | --- |
| EKS Cluster Role | EKS Control Plane 운영 |
| EKS Node Role | EC2 Worker Node 운영 |
| VPC CNI Role | Pod 네트워크 관리 |

### 9.2 적용 정책

**EKS Cluster Role**

- AmazonEKSClusterPolicy

**EKS Node Role**

- AmazonEKSWorkerNodePolicy
- AmazonEC2ContainerRegistryPullOnly
- AmazonEKS_CNI_Policy (초기 부트스트랩용)

**VPC CNI Role**

- AmazonEKS_CNI_Policy

### 9.3 Pod Identity 적용

VPC CNI가 전용 IAM Role을 사용할 수 있도록 `aws-node` ServiceAccount에 Pod Identity Association을 구성하였다.

EKS Pod Identity Agent는 시스템 Pod로 배포되었으며 정상 실행을 확인하였다.

### 9.4 개선 방향

초기 Node 생성에 필요한 CNI 권한을 Node Role에도 부여하였다.

향후 Pod Identity를 통한 전용 권한 사용을 검증하고, Node Role에서 불필요한 CNI 권한을 제거하는 방향을 검토한다.

---

## 10. Security Group 설계

### 10.1 적용 방향

- EKS Cluster와 Worker Node 간 통신
- Worker Node 간 Kubernetes 통신
- Kubernetes API Public Endpoint 접근 제한
- 불필요한 외부 접근 최소화

### 10.2 실제 구현

이번 구성에서는 별도의 사용자 정의 Security Group Rule을 Terraform으로 작성하지 않았다.

EKS가 생성·관리하는 Cluster Security Group 및 Managed Node Group의 네트워크 구성을 활용하였다.

### 10.3 개선 사항

- 실제 Security Group Inbound / Outbound 규칙 검토
- Worker Node 직접 접근 최소화
- Monitoring 접근 제어 강화
- 외부 Load Balancer 도입 시 별도 보안 정책 정의
- Private Subnet 전환 검토

---

## 11. 외부 접근 방식

### 11.1 초기 설계

- Kubernetes Service type LoadBalancer
- Ingress 및 AWS Load Balancer Controller

### 11.2 실제 프로젝트 활용

초기 구축 단계에서는 외부 Load Balancer를 생성하지 않고 `kubectl` 기반 클러스터 접근을 우선 검증하였다.

애플리케이션 기능 확인에는 port-forward 방식을 활용하였다.

```
kubectl port-forward `
  -n online-boutique `
  deployment/frontend 8080:8080
```

### 11.3 k6 부하 테스트

HPA 성능 비교는 외부 Load Balancer를 통하지 않고 EKS 내부의 k6 Job으로 실행하였다.

```
k6 Job
   │
   ▼
ClusterIP Service
   │
   ▼
ProductCatalog Pod
```

### 11.4 설계 판단

외부 Load Balancer를 필수 구성요소로 사용하지 않아 실험 환경을 단순화하였다.

다만 실제 인터넷 사용자 트래픽에 대한 고가용성, 외부 Load Balancer 기반 장애 복구, TLS 종료 및 Ingress 운영은 별도로 검증하지 않았다.

---

## 12. Terraform 관리 범위

### 12.1 Terraform 관리 리소스

- AWS VPC 및 Public Subnet
- Internet Gateway
- Route Table 및 Route Association
- IAM Role 및 Policy Attachment
- EKS Cluster
- EKS Managed Node Group
- VPC CNI Add-on
- Pod Identity Agent Add-on
- Metrics Server Add-on

### 12.2 Kubernetes 관리 영역

다음 항목은 Terraform이 아닌 Kubernetes Manifest, Helm 또는 Argo CD를 통해 관리하였다.

- Online Boutique Deployment / Service
- ConfigMap
- Readiness / Liveness Probe
- HPA
- Prometheus / Grafana / Alertmanager
- Argo CD Application
- 테스트용 Job 및 Pod

### 12.3 관리 영역 분리

```
Terraform
    │
    ▼
AWS Infrastructure
    │
    ▼
Amazon EKS
    │
    ├── Argo CD
    │      └── Kubernetes Application
    │
    ├── Helm
    │      └── Monitoring Stack
    │
    └── kubectl / Manifest
           └── Recovery Test Resources
```

### 12.4 운영 원칙

Terraform은 AWS 인프라의 생성·변경·삭제를 담당한다.

Argo CD는 Git에 선언된 Kubernetes 애플리케이션 상태를 관리한다.

Helm은 모니터링 구성요소 설치에 활용하고, 실험용 리소스는 별도 Manifest를 통해 관리한다.

---

## 13. Terraform 디렉터리 구조

### 13.1 최종 파일 구성

```
terraform/
├── versions.tf
├── providers.tf
├── variables.tf
├── terraform.tfvars.example
├── outputs.tf
├── main.tf
├── iam.tf
├── eks.tf
├── node-group.tf
├── vpc-cni.tf
├── metrics-server.tf
└── .terraform.lock.hcl
```

### 13.2 파일별 역할

| 파일 | 주요 역할 |
| --- | --- |
| versions.tf | Terraform 및 Provider 버전 제약 |
| providers.tf | AWS Provider 및 기본 태그 구성 |
| variables.tf | 입력 변수 정의 |
| terraform.tfvars.example | 변수 입력 예시 |
| outputs.tf | 인프라 생성 결과 출력 |
| main.tf | VPC 및 네트워크 리소스 |
| iam.tf | IAM Role 및 Policy |
| eks.tf | EKS Cluster |
| node-group.tf | Managed Node Group |
| vpc-cni.tf | VPC CNI 및 Pod Identity 관련 구성 |
| metrics-server.tf | Metrics Server Add-on |
| .terraform.lock.hcl | Provider 의존성 버전 잠금 |

### 13.3 설계 판단

이번 프로젝트에서는 별도의 `modules/` 구조를 만들지 않고 Root Module 방식으로 구성하였다.

Terraform의 리소스 및 의존관계를 학습하고 프로젝트의 전체 구조를 이해하기 위해 파일별 역할 분리를 우선하였다.

향후 재사용성이 필요하면 Network, IAM 및 EKS 모듈로 분리할 수 있다.

---

## 14. Terraform 실행 흐름

### 14.1 AWS 인증

Windows PowerShell에서 IAM Identity Center 프로필을 이용해 로그인한다.

```
aws sso login --profile k8s-lab
```

현재 세션에서 사용할 프로필 지정:

```
$env:AWS_PROFILE = "k8s-lab"
```

### 14.2 Terraform 초기화 및 검증

```
cd .\terraform
terraform init
terraform fmt
terraform validate
```

### 14.3 인프라 생성

```
terraform plan -var-file="terraform.tfvars"
```

Plan 파일 생성:

```
terraform plan `
  -var-file="terraform.tfvars" `
  -out="eks.tfplan"
```

적용:

```
terraform apply "eks.tfplan"
```

### 14.4 Kubernetes 연결

```
aws eks update-kubeconfig `
  --region ap-northeast-2 `
  --name auto-recovery-eks `
  --profile k8s-lab
```

확인:

```
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

### 14.5 Terraform 구성 일치 검증

```
terraform fmt -check
terraform validate
terraform plan -var-file="terraform.tfvars"
```

최종 검증에서 다음 결과를 확인하였다.

```
No changes. Your infrastructure matches the configuration.
```

### 14.6 인프라 삭제

삭제 계획 확인:

```
terraform plan -destroy -var-file="terraform.tfvars"
```

실제 삭제:

```
terraform destroy -var-file="terraform.tfvars"
```

삭제 이후 State 확인:

```
terraform state list
```

AWS 리소스 확인:

```
aws eks describe-cluster `
  --name auto-recovery-eks `
  --region ap-northeast-2 `
  --profile k8s-lab
```

클러스터가 삭제됐다면 `ResourceNotFoundException`이 발생할 수 있다.

Terraform 삭제 완료 여부는 실제 `Destroy complete` 로그와 AWS 리소스 조회 결과를 기준으로 판단한다.

---

## 15. IaC 검증 결과

### 15.1 1차 Terraform 구축 결과

| 검증 항목 | 실제 결과 |
| --- | --- |
| Terraform Validate | 성공 |
| Terraform Plan | 20개 생성 예정 |
| Terraform Apply | 20개 생성 성공 |
| EKS Cluster 생성 | 7분 54초 |
| Managed Node Group 생성 | 1분 57초 |
| Pod Identity Agent 생성 | 25초 |
| VPC CNI Add-on 생성 | 26초 |

위 시간은 Terraform 로그에서 확인한 개별 리소스 생성 소요 시간이다.

전체 Apply 시간은 별도로 측정하지 않았다.

### 15.2 1차 인프라 삭제 결과

| 검증 항목 | 결과 |
| --- | --- |
| Terraform Destroy | 20개 삭제 |
| Terraform State | 관리 리소스 없음 |
| EKS Cluster 목록 | 삭제 확인 |
| Worker Node | EC2 종료 확인 |
| 추가 EBS 및 기타 리소스 | 별도 점검 필요 |

1차 구축에서는 Terraform으로 인프라를 생성하고 기본 동작을 확인한 후 삭제하는 과정을 검증하였다.

### 15.3 EKS 재구축 및 애플리케이션 운영

이후 EKS 환경을 다시 구축하여 Online Boutique 애플리케이션과 Kubernetes 운영 구성요소를 배포하였다.

| 검증 항목 | 결과 |
| --- | --- |
| EKS Cluster | 구축 성공 |
| Worker Node | 2개 Ready |
| Online Boutique | 11개 Deployment 정상 실행 |
| Argo CD | Synced / Healthy |
| Prometheus / Grafana | 모니터링 환경 구성 |
| Metrics Server | 정상 동작 |
| HPA | 자동 확장·축소 검증 |

### 15.4 Metrics Server Terraform 관리 편입

Metrics Server는 먼저 AWS EKS Add-on으로 설치하였다.

이후 Terraform State에 존재하지 않는 문제를 해결하기 위해 Terraform 관리 대상으로 편입하였다.

**Terraform 리소스 정의**

```
resource "aws_eks_addon" "metrics_server" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "metrics-server"
  addon_version = "v0.9.0-eksbuild.14"

  depends_on = [
    aws_eks_node_group.main
  ]
}
```

**기존 리소스 Import**

```
terraform import `
  -var-file="terraform.tfvars" `
  aws_eks_addon.metrics_server `
  auto-recovery-eks:metrics-server
```

Import 후 Terraform Plan에서 Provider의 기본 태그에 따른 변경 사항을 확인하였다.

필요한 태그 변경을 적용하고 다시 Plan을 실행하여 최종적으로 `No changes`를 확인하였다.

### 15.5 최종 검증 결과

| 검증 항목 | 결과 |
| --- | --- |
| Terraform fmt | 통과 |
| Terraform validate | 통과 |
| Metrics Server Import | 성공 |
| Terraform 태그 변경 적용 | 성공 |
| 최종 Terraform Plan | No changes |
| Terraform 코드 GitHub 반영 | 완료 |
| 이후 최종 Destroy | 완료 로그 별도 확인 필요 |

### 검증 결론

Terraform을 통해 AWS EKS 기반 인프라 생성과 삭제를 검증했으며, 재구축한 환경에서 실제 Kubernetes 애플리케이션 및 장애 복구 실험을 수행하였다.

또한 Metrics Server를 Terraform State에 편입하여 코드와 관리 대상 AWS 리소스의 상태가 일치하는 것을 확인하였다.

다만 `No changes` 결과만으로 전체 Kubernetes 애플리케이션과 모니터링 구성의 완전한 재현성을 입증한 것은 아니다.

---

## 16. Terraform State 관리

### 16.1 State 역할

Terraform State는 Terraform 코드에서 선언한 리소스와 실제 AWS 리소스 사이의 연결 관계를 관리한다.

### 16.2 실제 적용

| 항목 | 적용 방식 |
| --- | --- |
| Backend | Local |
| State 파일 | terraform.tfstate |
| State Backup | terraform.tfstate.backup |
| Terraform 변수 파일 | terraform.tfvars |
| Provider Lock File | .terraform.lock.hcl |
| Remote State | 미적용 |

### 16.3 Git 관리 제외

다음 항목은 GitHub에 업로드하지 않도록 설정하였다.

```
.terraform/
*.tfstate
*.tfstate.*
terraform.tfvars
*.tfplan
*-tfplan
*-tkplan
```

Plan 및 State 파일에는 민감한 설정이나 인프라 정보가 포함될 수 있으므로 소스 코드와 분리하여 관리한다.

반면 `.terraform.lock.hcl`은 Provider 버전 재현을 위해 Git 관리 대상으로 유지하였다.

### 16.4 State Import

기존 AWS 리소스를 Terraform 관리 대상으로 추가할 때 `terraform import`를 활용하였다.

Import를 통해 이미 생성된 Metrics Server Add-on과 Terraform 리소스 정의를 연결하였다.

### 16.5 개선 방향

개인 실습 환경에서는 Local State를 사용했지만, 여러 사용자가 함께 Terraform을 실행하는 환경에서는 Remote State 및 State 잠금 기능을 검토할 필요가 있다.

---

## 17. 비용 관리 방안

### 17.1 설계 방향

AWS 리소스는 실습이 필요한 기간에 생성하고, 실험 종료 후 삭제하는 방식을 적용하였다.

### 17.2 실제 적용

| 항목 | 관리 방안 |
| --- | --- |
| NAT Gateway | 미생성 |
| Worker Node | t3.large × 2 |
| Node Group | Min 2 / Desired 2 / Max 2 |
| Load Balancer | 필수 구성으로 사용하지 않음 |
| EKS Cluster | 실습 시 생성 |
| Terraform | 생성·삭제 관리 |
| 비용 알림 | AWS Budgets 알림 설정 |

### 17.3 비용 발생 대상

- EKS Cluster
- EC2 Worker Node
- EBS Volume
- Public IPv4
- ECR 이미지 저장
- CloudWatch 등 별도 사용 리소스

### 17.4 비용 최적화 판단

NAT Gateway를 생성하지 않아 추가적인 NAT Gateway 비용을 줄였다.

다만 Public IPv4 비용과 Public Subnet 기반 Node 배치에 따른 보안 고려 사항이 존재한다.

또한 EKS Cluster 및 EC2 리소스는 실행 중 비용이 발생하므로 실험 종료 후 리소스 정리가 필요하다.

### 17.5 검증 한계

이번 프로젝트에서 최종 AWS 청구 금액과 시간별 비용을 정량적으로 분석한 자료는 별도로 확보하지 않았다.

따라서 NAT Gateway 미사용에 따른 구체적인 절감 금액을 실측 성과로 제시하지 않는다.

---

## 18. 보안 설계 방향

### 18.1 AWS 인증

- IAM Identity Center 기반 SSO
- Terraform 코드에 Access Key 직접 저장하지 않음
- AWS CLI Profile 기반 인증

### 18.2 네트워크 보안

- EKS API Public Endpoint CIDR 제한
- AWS Security Group 활용
- Public / Private API Endpoint 구성
- 2개 Availability Zone 구성

### 18.3 IAM 권한 분리

- EKS Cluster Role
- Node Role
- VPC CNI 전용 Role
- Pod Identity Agent 활용

### 18.4 민감정보 관리

- Terraform State Git 관리 제외
- Terraform 변수 파일 Git 관리 제외
- Plan 파일 Git 관리 제외
- Provider Lock File 유지

### 18.5 향후 개선

- Worker Node Private Subnet 배치
- Node Role의 CNI 권한 최소화
- Security Group 규칙 세부 검증
- Terraform Remote State 및 접근 제어
- CI/CD IAM 권한 및 OIDC 검증
- Secret 관리 강화

### 보안 설계 결론

이번 AWS 환경은 비용과 학습 효율을 고려해 구성한 개인 실습용 아키텍처다.

따라서 실제 운영 환경에 적용하려면 네트워크 접근 제어, IAM 최소 권한, State 보안 및 모니터링 접근 통제를 추가로 검토해야 한다.

---

## 19. 다른 구성요소와 연결

### 19.1 인프라 구축 흐름

```
Terraform
    │
    ▼
AWS VPC / IAM
    │
    ▼
Amazon EKS
    │
    ▼
Managed Node Group
    │
    ▼
Kubernetes System Add-ons
    │
    ▼
Worker Node Ready
```

### 19.2 애플리케이션 배포 흐름

```
GitHub Source Code
        │
        ▼
GitHub Actions
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
Online Boutique on EKS
```

### 19.3 모니터링 및 장애 검증

```
Kubernetes Workload
        │
        ├── ReplicaSet / Probe
        │
        ├── Metrics Server → HPA
        │
        └── Prometheus
                 │
          ┌──────┴───────┐
          │              │
          ▼              ▼
        Grafana       Alertmanager

k6 / kubectl
      │
      ▼
부하 및 장애 주입
      │
      ▼
복구 동작 및 측정 결과 분석
```

### 19.4 관리 영역 분리

Terraform은 AWS 리소스를 관리하고, Kubernetes 및 Argo CD는 애플리케이션의 선언적 상태를 관리한다.

Kubernetes의 Pod 자동 복구와 HPA는 Terraform과 별개로 클러스터 내부에서 동작한다.

Prometheus는 상태를 관측하며, Pod를 직접 재생성하는 역할을 수행하지 않는다.

---

## 20. 최종 구성 및 미검증 항목

### 20.1 최종 확정 구성

| 항목 | 실제 설정 |
| --- | --- |
| AWS Region | ap-northeast-2 |
| EKS Cluster | auto-recovery-eks |
| Kubernetes Version | 1.35 |
| VPC | 10.0.0.0/16 |
| Public Subnet | 10.0.1.0/24, 10.0.2.0/24 |
| Availability Zone | 2개 |
| Worker Node | t3.large × 2 |
| Node Group | Min 2 / Desired 2 / Max 2 |
| NAT Gateway | 미사용 |
| Kubernetes API | Public + Private |
| Container Registry | Amazon ECR |
| Resource Metrics | Metrics Server |
| Terraform Backend | Local State |
| CI/CD | GitHub Actions / Argo CD |
| Monitoring | Prometheus / Grafana |

### 20.2 후속 검증 항목

| 항목 | 최종 상태 |
| --- | --- |
| Terraform 기반 EKS 생성 | 검증 완료 |
| 1차 Terraform Destroy | 검증 완료 |
| Worker Node Ready | 검증 완료 |
| Online Boutique EKS 배포 | 검증 완료 |
| Metrics Server 설치 | 검증 완료 |
| Metrics Server Import | 검증 완료 |
| 최종 Terraform Plan | No changes |
| 이후 최종 Terraform Destroy | 완료 로그 별도 확인 필요 |
| Remote State | 미구현 |
| Node Auto Scaling | 미구현 |
| Terraform 전체 재구축 시간 | 미측정 |
| 전체 애플리케이션 자동 재구축 | 미검증 |
| 실제 AWS 비용 분석 | 미완료 |
| AZ 장애 대응 | 미검증 |
| Private Subnet 기반 Node | 미구현 |

---

## 21. 설계 결론

Terraform을 사용하여 AWS EKS 클러스터, VPC, Subnet, IAM, Managed Node Group 및 EKS Add-on을 코드 기반으로 구성하였다.

1차 구축에서는 Terraform 리소스 20개를 생성하고, Worker Node 2개의 Ready 상태와 Kubernetes 시스템 Pod의 정상 동작을 확인한 뒤 삭제까지 검증하였다.

이후 EKS 환경을 다시 구성하고 Online Boutique, GitHub Actions, Argo CD, Prometheus 및 Grafana를 연계하여 실제 Kubernetes 장애 복구 실험을 수행하였다.

또한 기존에 생성된 Metrics Server Add-on을 Terraform State에 Import하고 최종 Plan에서 변경 사항이 없음을 확인하여 인프라의 선언적 관리 상태를 검증하였다.

### 최종 결론 한 줄

**AWS 인프라를 수동으로 생성하는 방식에서 Terraform 기반 선언적 관리 방식으로 전환하고, EKS 구축·삭제 및 State 일치 여부를 검증했다. 결국 안정적인 인프라 운영의 기반은 리소스를 구축하는 데서 끝나는 것이 아니라, 코드와 실제 환경의 상태를 일관되게 유지하고 변경·복구 과정을 관리하는 데 있다.**
