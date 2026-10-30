- **Kubernetes Metrics Server 미구성으로 CPU 메트릭 조회 실패**
    
    **문제:**
    
    HPA 테스트를 준비하면서 Pod와 Node의 CPU 사용량을 확인하려 했으나 Metrics API를 사용할 수 없었음.
    
    ```powershell
    kubectl top nodes
    kubectl top pods -n recovery-test
    ```
    
    **원인:**
    
    EKS 클러스터에 Metrics Server가 구성되지 않아 Kubernetes가 CPU 및 Memory 사용량을 Metrics API로 제공하지 못했음.
    
    **해결:**
    
    Metrics Server를 EKS Add-on으로 설치하고 정상 동작을 확인함.
    
    이후 `kubectl top nodes`, `kubectl top pods`가 정상 실행됐으며, HPA가 CPU 사용률에 따라 Pod를 자동 확장하는 것까지 확인함.
    
- **PowerShell 환경에서 Amazon ECR Docker 로그인 오류**
    
    **문제:**
    
    EKS 내부에서 k6 부하 테스트를 실행하기 위해 Docker 이미지를 ECR에 Push하는 과정에서 로그인 오류가 발생함.
    
    **원인:**
    
    Windows PowerShell에서 AWS ECR 인증 정보를 Docker 로그인 명령어로 전달하는 과정에 문제가 발생함.
    
    **해결:**
    
    PowerShell 파이프라인 대신 `cmd /c`를 사용해 ECR 로그인 명령어를 실행함.
    
    ```powershell
    cmd /c 'aws ecr get-login-password --region ap-northeast-2 --profile k8s-lab | docker login --username AWS --password-stdin 007053125976.dkr.ecr.ap-northeast-2.amazonaws.com'
    ```
    
    Docker 로그인 성공 후 k6 이미지를 ECR에 Push하고, Kubernetes Job에서 정상적으로 실행함.
    
- **k6 gRPC 테스트에서 Proto 파일 로딩 실패**
    
    **문제:**
    
    k6를 이용해 ProductCatalog gRPC API를 호출하는 과정에서 `demo.proto` 파일을 정상적으로 불러오지 못함.
    
    **원인:**
    
    스크립트에 지정한 Proto 파일의 상대 경로가 실제 k6 실행 환경과 일치하지 않았음.
    
    기존 설정:
    
    ```jsx
    client.load(['./tests/hpa'], 'demo.proto');
    ```
    
    **해결:**
    
    Proto 파일과 JavaScript 테스트 스크립트를 ConfigMap으로 생성하고 `/scripts` 경로에 마운트함.
    
    Proto 파일 참조 경로를 수정함.
    
    ```jsx
    client.load(['.'], 'demo.proto');
    ```
    
    이후 EKS 내부 k6 Job에서 gRPC 요청을 정상적으로 실행했으며, 3분간 18,001건의 요청을 오류 없이 처리함.
    
- **Metrics Server Add-on과 Terraform State 불일치**
    
    **문제:**
    
    AWS EKS에 Metrics Server Add-on이 설치되어 있었지만, Terraform 코드와 State에는 해당 리소스가 등록되어 있지 않았음.
    
    **원인:**
    
    Metrics Server를 Terraform 외부에서 설치했기 때문에 AWS에는 리소스가 존재하지만 Terraform의 관리 대상에는 포함되지 않았음.
    
    **해결:**
    
    `metrics-server.tf`에 Metrics Server Add-on 리소스를 정의함.
    
    ```hcl
    resource "aws_eks_addon" "metrics_server" {
      cluster_name  = aws_eks_cluster.main.name
      addon_name    = "metrics-server"
      addon_version = "v0.9.0-eksbuild.14"
    
      depends_on = [
        aws_eks_node_group.main
      ]
    }
    ```
    
    기존 AWS 리소스를 Terraform State에 Import함.
    
    ```powershell
    terraform import -var-file="terraform.tfvars" aws_eks_addon.metrics_server auto-recovery-eks:metrics-server
    ```
    
    이후 태그 변경을 적용하고 Terraform Plan을 재실행한 결과 다음 메시지를 확인함.
    
    ```
    No changes. Your infrastructure matches the configuration.
    ```
    
- **Terraform Destroy 실행 시 AWS 인증 오류**
    
    **문제:**
    
    실험 종료 후 AWS 인프라를 삭제하기 위해 Terraform 삭제 계획을 확인했으나 AWS 인증 오류가 발생함.
    
    ```
    Error: No valid credential sources found
    ```
    
    **원인:**
    
    현재 PowerShell 세션에서 Terraform이 유효한 AWS 인증 정보를 찾지 못함.
    
    AWS IAM Identity Center(SSO) 인증 만료 또는 프로필 미설정이 원인일 가능성이 있었음.
    
    **해결:**
    
    AWS SSO에 다시 로그인하고, 현재 PowerShell 세션에 사용할 프로필을 지정함.
    
    ```powershell
    aws sso login --profile k8s-lab
    ```
    
    ```powershell
    $env:AWS_PROFILE = "k8s-lab"
    ```
    
    이후 `terraform plan -destroy`에서 AWS 리소스 정보를 정상적으로 조회하고 삭제 계획을 확인함.
