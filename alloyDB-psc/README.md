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

# 접속 테스트

PSC는 VPC 네트워크 내부에 엔드포인트(전달 규칙의 IP 주소)를 생성하므로, **테스트는 반드시 해당 VPC 네트워크 내부에서 수행해야 합니다.** 가장 간단한 방법은 AlloyDB 및 PSC 엔드포인트와 동일한 VPC 네트워크 내에 임시 Compute Engine(GCE) VM 인스턴스를 생성하고 해당 VM에서 연결을 시도하는 것입니다.

## 테스트 단계:

1.  **필요 정보 확인:**
    *   **PSC 엔드포인트 IP 주소:** Terraform `output`에서 `psc_endpoint_ip_address` 값을 확인합니다.
    *   **데이터베이스 이름:** Terraform 변수 `database` 값 (기본값: `movies`)
    *   **데이터베이스 사용자:** Terraform 변수 `alloydb_user` 값 (기본값: `postgres`)
    *   **데이터베이스 비밀번호:** Secret Manager에서 가져오도록 설정한 비밀번호 (`alloydb-initial-password` 시크릿의 값)
    *   **VPC 네트워크 이름:** Terraform 변수 `network_name` 값 (기본값: `default`)
    *   **서브네트워크 이름:** Terraform 변수 `subnetwork_name` 값 (PSC IP를 예약한 서브넷)
    *   **리전 (Region):** Terraform 변수 `region` 값 (예: `asia-northeast3`)
    *   **가용 영역 (Zone):** 테스트 VM을 생성할 리전 내의 가용 영역 (예: `asia-northeast3-a`)

2.  **테스트용 GCE VM 생성:**
    *   Cloud Shell 또는 로컬 터미널에서 다음 명령어를 실행하여 PSC 엔드포인트와 **동일한 VPC 및 서브넷**에 임시 VM을 생성합니다.
        ```bash
        # 환경 변수 설정 (이미 설정되어 있다면 생략 가능)
        # export PROJECT_ID="p-khm8-dev-svc"
        # export REGION="asia-northeast3"
        # export ZONE="asia-northeast3-a" # 또는 해당 리전의 다른 가용 영역
        # export NETWORK_NAME="default"
        # export SUBNET_NAME="default" # PSC IP를 예약한 서브넷 이름
        export TEST_VM_NAME="alloydb-psc-test-vm"

        echo "테스트 VM 생성 중: $TEST_VM_NAME..."
        gcloud compute instances create $TEST_VM_NAME \
            --project=$PROJECT_ID \
            --zone=$ZONE \
            --machine-type=e2-small \
            --image-family=debian-12 \
            --image-project=debian-cloud \
            --network=$NETWORK_NAME \
            --subnet=$SUBNET_NAME \
            --scopes="https://www.googleapis.com/auth/cloud-platform" \
            --shielded-secure-boot
        ```
        *(조직 정책에 따라 `--shielded-secure-boot` 등이 필요할 수 있습니다.)*

3.  **GCE VM 접속:**
    ```bash
    gcloud compute ssh $TEST_VM_NAME --project $PROJECT_ID --zone $ZONE
    ```

4.  **VM 내부에 PostgreSQL 클라이언트 설치:**
    *   VM에 접속된 상태에서 다음 명령어를 실행합니다.
        ```bash
        sudo apt-get update
        sudo apt-get install -y postgresql-client telnet
        ```
        *(여기서는 `telnet`도 함께 설치하여 네트워크 연결 자체를 먼저 확인해 볼 수 있습니다.)*

5.  **네트워크 연결 테스트 (선택 사항):**
    *   `psql`로 실제 연결을 시도하기 전에, PSC 엔드포인트 IP와 PostgreSQL 포트(5432)로 TCP 연결이 가능한지 확인합니다. 방화벽 문제를 진단하는 데 도움이 됩니다.
        ```bash
        # PSC_ENDPOINT_IP 를 Terraform output 값으로 대체
        export PSC_ENDPOINT_IP="여기에_PSC_엔드포인트_IP_입력"
        telnet $PSC_ENDPOINT_IP 5432
        ```
    *   **성공 시:** `Connected to <IP 주소>.`와 유사한 메시지가 표시되고 Escape 문자를 입력하라는 안내가 나옵니다. (Ctrl + ] 누르고 `quit` 입력하여 종료)
    *   **실패 시:** `Connection timed out` 또는 `Connection refused` 메시지가 표시됩니다. 이는 VPC 방화벽 규칙이 VM에서 PSC 엔드포인트 IP의 5432 포트로 가는 트래픽을 막고 있을 가능성을 시사합니다. VPC 방화벽 규칙을 확인하고 필요한 경우 허용 규칙을 추가해야 합니다.

6.  **AlloyDB 연결 테스트 (psql 사용):**
    *   PSC 엔드포인트 IP 주소를 호스트(`-h`)로 지정하여 `psql` 명령어를 실행합니다.
        ```bash
        # 환경 변수 설정 (PSC IP, 사용자, DB 이름)
        # export PSC_ENDPOINT_IP="Terraform_출력_IP" # 이미 설정했다면 생략
        export ALLOYDB_USER="postgres" # 또는 Terraform에서 설정한 사용자

        echo "AlloyDB 기본 DB 연결 시도 (비밀번호 입력 필요)..."
        # 데이터베이스 이름을 'postgres'로 변경
        psql -h $PSC_ENDPOINT_IP -U $ALLOYDB_USER -d postgres
        ```
    *   위 명령어를 실행하면 **비밀번호를 묻는 프롬프트**가 나타납니다. Secret Manager에 저장하고 Terraform `apply` 시 사용했던 비밀번호를 입력합니다.
    *   성공 시: psql (버전) 정보와 함께 postgres=> 와 같은 psql 프롬프트가 나타납니다. 이는 PSC 엔드포인트를 통한 네트워크 연결 및 사용자 인증이 성공했음을 의미합니다.
    *   **psql 종료:** `\q`를 입력하고 Enter 키를 누릅니다.
    *   **실패 시:** `psql: error: connection to server at ... failed: ...` 와 같은 오류 메시지가 표시됩니다. 원인은 다음과 같을 수 있습니다.
        *   잘못된 비밀번호 입력
        *   잘못된 사용자 이름 또는 데이터베이스 이름
        *   네트워크 연결 문제 (5단계 테스트 실패 시)
        *   AlloyDB 인스턴스 자체의 문제 (가능성 낮음)
    *   **`movies` 데이터베이스 생성 및 확장 활성화:** 테스트
        ```bash
        psql -U postgres -h $PSC_ENDPOINT_IP -c 'create DATABASE movies'
        psql -U postgres -h $PSC_ENDPOINT_IP -d movies -c 'CREATE EXTENSION IF NOT EXISTS alloydb_scann CASCADE;'
        ```

7.  **테스트 VM 정리:**
    *   테스트가 완료되면 GCE VM에서 `exit` 명령어로 접속을 종료합니다.
    *   더 이상 필요하지 않으면 생성했던 테스트 VM을 삭제합니다.
        ```bash
        echo "테스트 VM 삭제 중: $TEST_VM_NAME..."
        gcloud compute instances delete $TEST_VM_NAME --project $PROJECT_ID --zone $ZONE --quiet
        ```
# 리소스 삭제
   ```bash
   # 특정 리소스만 타겟하여 삭제 (클러스터, 인스턴스, 전달 규칙, IP)
   terraform destroy -target=google_alloydb_instance.primary -var-file=terraform.tfvars
   terraform destroy -target=google_compute_forwarding_rule.psc_endpoint -var-file=terraform.tfvars
   terraform destroy -target=google_compute_address.psc_ip -var-file=terraform.tfvars
   terraform destroy -target=google_alloydb_cluster.main -var-file=terraform.tfvars

   # 또는 전체 리소스 삭제 (이 Terraform 구성으로 관리되는 모든 것)
   terraform destroy -var-file=terraform.tfvars
   ```

# 중요 참고 사항:

*   **서브네트워크:** PSC 엔드포인트에 내부 IP를 할당하려면 **반드시 서브네트워크를 지정**해야 합니다. `var.subnetwork_name` 변수에 올바른 서브넷 이름을 입력하세요.
*   **애플리케이션 연결:** 이 Terraform 코드로 생성된 후, 애플리케이션(Cloud Run 등)은 AlloyDB 인스턴스의 직접적인 Private IP가 아닌, **`output "psc_endpoint_ip_address"`** 로 출력되는 **PSC 엔드포인트 IP 주소**로 연결해야 합니다. 데이터베이스 연결 문자열이나 AlloyDB Python 커넥터 설정 시 이 PSC 엔드포인트 IP를 호스트(host)로 사용해야 합니다. 포트는 여전히 PostgreSQL 기본 포트(5432)입니다.
*   **방화벽:** PSC 엔드포인트는 VPC 내부에 생성되므로, 애플리케이션이 실행되는 환경(예: 다른 서브넷의 Compute Engine, GKE 노드 등)에서 이 PSC 엔드포인트 IP의 5432 포트로 트래픽을 보낼 수 있도록 **VPC 방화벽 규칙**이 필요할 수 있습니다. (같은 서브넷 내라면 기본적으로 허용될 수 있습니다.)
*   **GKE Cluster에서 PSC 엔드포인트 사용:** GKE Cluster가 이 PSC 엔드포인트에 연결하려면, GKE Cluster 역시 **동일한 VPC 네트워크에 연결**되어야 합니다 (Direct VPC Egress 사용). 
