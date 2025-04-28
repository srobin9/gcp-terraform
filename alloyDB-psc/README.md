# 핵심 원리:

1.  AlloyDB 클러스터를 생성하면 Google Cloud가 해당 클러스터에 대한 **서비스 연결(Service Attachment)** 을 자동으로 생성하고 노출합니다.
2.  사용자의 VPC 네트워크 내에 **내부 IP 주소**를 예약합니다.
3.  이 예약된 IP 주소와 AlloyDB 클러스터의 서비스 연결을 타겟으로 하는 **전달 규칙(Forwarding Rule)** 을 생성합니다. 이 전달 규칙이 바로 PSC 엔드포인트 역할을 합니다.
4.  AlloyDB 초기 사용자 비밀번호를 **Google Secret Manager**에 저장하고 Terraform 코드에서 해당 시크릿을 참조합니다.
5.  애플리케이션(예: Cloud Run, GKE, Compute Engine)은 VPC 내에서 이 **전달 규칙의 IP 주소**로 연결하여 AlloyDB에 접속합니다.

# 사전 준비 사항:

1.  **Secret Manager API 활성화:** Terraform을 실행하기 전에 프로젝트에서 Secret Manager API가 활성화되어 있어야 합니다. (아래 코드에 자동으로 포함되도록 수정했습니다.)
2.  **비밀번호 시크릿 생성:** Secret Manager에 AlloyDB 비밀번호를 저장하는 시크릿을 **미리 생성**해야 합니다.
    *   **예시 (Cloud Shell 사용):**
        ```bash
        # 1. 강력한 비밀번호 생성 (예시)
        export MY_ALLOYDB_PASSWORD=$(openssl rand -base64 16)
        echo "생성된 비밀번호: $MY_ALLOYDB_PASSWORD" # 이 비밀번호를 안전한 곳에 기록해두세요.

        # 2. Secret Manager에 시크릿 생성 및 버전 추가
        gcloud secrets create alloydb-initial-password \
            --replication-policy="automatic" \
            --project=${PROJECT_ID}

        echo -n "$MY_ALLOYDB_PASSWORD" | gcloud secrets versions add alloydb-initial-password \
            --data-file=- \
            --project=${PROJECT_ID}

        # 3. 생성된 비밀번호 변수 삭제 (선택 사항)
        unset MY_ALLOYDB_PASSWORD
        ```
        *   위 예시에서는 시크릿 이름을 `alloydb-initial-password`로 지정했습니다. 다른 이름을 사용했다면 아래 Terraform 코드의 변수 값을 해당 이름으로 변경해야 합니다.
     
3.  **Terraform 실행 계정 권한:** Terraform을 실행하는 사용자 또는 서비스 계정은 해당 시크릿에 접근할 수 있는 **`secretmanager.secretAccessor`** IAM 역할이 필요합니다.
    ```bash
    # Terraform 실행 서비스 계정에 권한 부여 예시
    # gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    #   --member="serviceAccount:your-terraform-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    #   --role="roles/secretmanager.secretAccessor"

    # 또는 특정 시크릿에만 권한 부여
    # gcloud secrets add-iam-policy-binding alloydb-initial-password \
    #   --member="serviceAccount:your-terraform-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    #   --role="roles/secretmanager.secretAccessor" \
    #   --project=${PROJECT_ID}
    ```

# 사용 방법:
1.  **변수 설정:**
    *   `terraform.tfvars` 파일을 생성하거나 환경 변수를 사용하여 필요한 변수 (`project_id`, `subnetwork_name`, `alloydb_password` 등)의 값을 설정합니다. `subnetwork_name`은 PSC 엔드포인트 IP를 할당할 서브넷의 실제 이름으로 변경해야 합니다.
    *   **`terraform.tfvars` 예시:**
        ```hcl
        project_id       = "p-khm8-dev-svc"
        region           = "us-central1"
        subnetwork_name  = "default" # 실제 사용하는 서브넷 이름으로 변경
        alloydb_password = "your-secure-password-here"
        # network_name     = "your-custom-network" # 기본값 외 다른 네트워크 사용 시
        # cluster_id       = "my-psc-cluster"      # 기본값 외 다른 이름 사용 시
        # instance_id      = "my-psc-instance"     # 기본값 외 다른 이름 사용 시
        # ... 다른 변수들도 필요 시 설정
        ```
2.  **Terraform 초기화:** 터미널에서 해당 코드가 있는 디렉토리로 이동한 후 다음 명령어를 실행합니다.
    ```bash
    terraform init
    ```
3.  **실행 계획 확인 (선택 사항):** 어떤 리소스가 생성될지 미리 확인합니다.
    ```bash
    terraform plan -var-file=terraform.tfvars
    ```
4.  **리소스 생성:** 계획이 문제없으면 리소스를 생성합니다.
    ```bash
    terraform apply -var-file=terraform.tfvars
    ```
5. **접속 테스트**
6. **리소스 삭제**

# 중요 참고 사항:

*   **서브네트워크:** PSC 엔드포인트에 내부 IP를 할당하려면 **반드시 서브네트워크를 지정**해야 합니다. `var.subnetwork_name` 변수에 올바른 서브넷 이름을 입력하세요.
*   **애플리케이션 연결:** 이 Terraform 코드로 생성된 후, 애플리케이션(Cloud Run 등)은 AlloyDB 인스턴스의 직접적인 Private IP가 아닌, **`output "psc_endpoint_ip_address"`** 로 출력되는 **PSC 엔드포인트 IP 주소**로 연결해야 합니다. 데이터베이스 연결 문자열이나 AlloyDB Python 커넥터 설정 시 이 PSC 엔드포인트 IP를 호스트(host)로 사용해야 합니다. 포트는 여전히 PostgreSQL 기본 포트(5432)입니다.
*   **방화벽:** PSC 엔드포인트는 VPC 내부에 생성되므로, 애플리케이션이 실행되는 환경(예: 다른 서브넷의 Compute Engine, GKE 노드 등)에서 이 PSC 엔드포인트 IP의 5432 포트로 트래픽을 보낼 수 있도록 **VPC 방화벽 규칙**이 필요할 수 있습니다. (같은 서브넷 내라면 기본적으로 허용될 수 있습니다.)
*   **GKE Cluster에서 PSC 엔드포인트 사용:** GKE Cluster가 이 PSC 엔드포인트에 연결하려면, GKE Cluster 역시 **동일한 VPC 네트워크에 연결**되어야 합니다 (Direct VPC Egress 사용). 
