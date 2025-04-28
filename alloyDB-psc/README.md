# **AlloyDB PSC 연결 Terraform 설정 및 테스트 가이드**
**(AlloyDB PSC Connection Terraform Setup and Test Guide)**

## **목적 (Purpose)**

이 Terraform 코드는 Google Cloud 환경에서 다음을 수행하는 것을 목표로 합니다:

*   **AlloyDB 클러스터 및 기본 인스턴스 생성:** 고가용성 PostgreSQL 호환 데이터베이스를 프로비저닝합니다.
*   **Private Service Connect (PSC) 구성:** VPC 네트워크 내에 비공개 엔드포인트를 생성하여 AlloyDB 인스턴스에 안전하게 연결합니다.
*   **보안 비밀번호 관리:** Google Secret Manager를 사용하여 AlloyDB 초기 사용자 비밀번호를 안전하게 저장하고 참조합니다.
*   **자동화된 인프라 관리:** Terraform을 사용하여 관련 클라우드 리소스를 코드로서 관리(IaC)합니다.

## **핵심 원리 (Core Principles):**

1.  **AlloyDB 서비스 연결 자동 생성:** AlloyDB 클러스터를 생성하면 Google Cloud는 PSC 연결을 위한 **서비스 연결(Service Attachment)** 을 내부적으로 자동으로 생성하고 관리합니다.
2.  **PSC 엔드포인트 IP 예약:** 사용자의 VPC 네트워크 내부에 PSC 엔드포인트로 사용할 **내부 IP 주소**를 예약합니다.
3.  **PSC 전달 규칙 생성:** 예약된 IP 주소와 **AlloyDB 인스턴스**의 (자동 생성된) 서비스 연결을 타겟으로 하는 **전달 규칙(Forwarding Rule)** 을 생성합니다. 이 전달 규칙이 VPC 내에서 AlloyDB로 트래픽을 전달하는 PSC 엔드포인트 역할을 합니다.
4.  **비밀번호 보안 관리:** AlloyDB 초기 사용자 비밀번호를 **Google Secret Manager**에 안전하게 저장하고, Terraform 코드는 실행 시 해당 시크릿 값을 참조하여 사용합니다.
5.  **PSC를 통한 애플리케이션 연결:** 애플리케이션(Cloud Run, GKE, Compute Engine 등)은 VPC 네트워크 내에서 이 **전달 규칙(PSC 엔드포인트)의 IP 주소**를 호스트로 사용하여 AlloyDB에 비공개로 안전하게 접속합니다.

## **요구 사항 (Requirements):**

*   **Terraform:** 버전 1.0 이상 권장.
*   **Google Cloud Provider for Terraform:** 버전 6.32.0 이상 (`>= 6.32.0`). (코드 내 `required_providers` 참조)
*   **Google Cloud 프로젝트:** 리소스를 생성할 GCP 프로젝트.
*   **gcloud CLI:** 사전 준비 단계 및 테스트에 사용.
*   **(선택 사항) openssl:** 비밀번호 생성 예시에 사용.

## **사전 준비 사항 (Prerequisites):**

1.  **필수 API 활성화 확인/활성화:** Terraform을 실행하기 전에 대상 Google Cloud 프로젝트에서 다음 API들이 활성화되어 있는지 확인하거나 Terraform이 활성화하도록 허용해야 합니다.
    *   AlloyDB API (`alloydb.googleapis.com`)
    *   Compute Engine API (`compute.googleapis.com`)
    *   Service Networking API (`servicenetworking.googleapis.com`)
    *   Secret Manager API (`secretmanager.googleapis.com`)
    *   (Terraform 코드 내 `google_project_service` 리소스가 `apply` 시 자동으로 활성화를 시도합니다.)
2.  **AlloyDB 비밀번호 시크릿 생성:** Secret Manager에 AlloyDB 초기 사용자 비밀번호를 저장할 시크릿을 **미리 생성**해야 합니다.
    *   **예시 (Cloud Shell 사용): 통해 관리하며, 생성된 리소스에 대한 연결을 테스트하는 방법을 안내합니다.

## **핵심 원리 (Core Principles):**

1.  **AlloyDB PSC 활성화 및 Service Attachment:** AlloyDB 클러스터 생성 시 PSC 사용을 **명시적으로 활성화** (`psc_instance_config` 블록 사용) 하면, Google Cloud는 해당 **AlloyDB 인스턴스**에 대한 고유한 **서비스 연결(Service Attachment)** 을 내부적으로 생성하고 관리합니다. (사용자가 직접 Service Attachment 리소스를 만들 필요는 없습니다.)
2.  **PSC 엔드포인트 IP 예약:** AlloyDB 인스턴스와 동일한 VPC 네트워크 내부에 PSC 엔드포인트로 사용할 **내부 IP 주소**를 예약합니다.
3.  **PSC 전달 규칙 생성:** 예약된 IP 주소와 **AlloyDB 인스턴스의 서비스 연결(Service Attachment)** 을 타겟으로 하는 **전달 규칙(Forwarding Rule)** 을 생성합니다. 이 전달 규칙이 VPC 내에서 AlloyDB로 트래픽을 전달하는 PSC 엔드포인트 역할을 합니다.
4.  **비밀번호 보안 관리:** AlloyDB 초기 사용자 비밀번호를 **Google Secret Manager**에 안전하게 저장하고, Terraform 코드는 실행 시 해당 시크릿 값을 참조하여 사용합니다. 이를 통해 코드나 변수 파일에 비밀번호를 직접 노출하는 것을 방지합니다.
5.  **PSC를 통한 애플리케이션 연결:** 애플리케이션(Cloud Run, GKE, Compute Engine 등)은 VPC 네트워크 내에서 이 **전달 규칙(PSC 엔드포인트)의 IP 주소**를 호스트(host)로 사용하여 AlloyDB에 비공개로 안전하게 접속합니다.

## **사전 준비 사항 (Prerequisites):**

1.  **Terraform 및 Google Cloud SDK 설치:** Terraform과 `gcloud` CLI가 설치되어 있어야 합니다.
2.  **필요 API 활성화:** Terraform 실행 전에 대상 Google Cloud 프로젝트에서 다음 API들이 활성화되어 있어야 합니다. (코드 내 `google_project_service` 리소스가 `apply` 시 활성화를 시도하지만, 미리 활성화하는 것이 좋습니다.)
    *   AlloyDB API (`alloydb.googleapis.com`)
    *   Compute Engine API (`compute.googleapis.com`)
    *   Secret Manager API (`secretmanager.googleapis.com`)
    *   Service Networking API (`servicenetworking.googleapis.com` - 직접 사용하진 않지만 관련 네트워킹에 필요할 수 있음)
    ```bash
    gcloud services enable alloydb.googleapis.com compute.googleapis.com secretmanager.googleapis.com servicenetworking.googleapis.com --project=YOUR_PROJECT_ID
    ```
3.  **AlloyDB 비밀번호 시크릿 생성:** Secret Manager에 AlloyDB 초기 사용자 비밀번호를 저장할 시크릿을 **미리 생성**해야 합니다.
    *   **예시 (Cloud Shell 사용):**
        ```bash
        export PROJECT_ID="p-khm8-dev-svc" # 실제 프로젝트 ID로 변경
        export ALLOYDB_SECRET_ID="alloydb-initial-password" # 사용할 시크릿 이름

        # 강력한 비밀번호 생성 (예시)
        export MY_ALLOYDB_PASSWORD=$(openssl rand -base64 16)
        echo "생성된 비밀번호 (안전하게 보관하세요): $MY_ALLOYDB_PASSWORD"

        # 시크릿 생성 (이미 존재하면 건너뜀)
        gcloud secrets create $ALLOYDB_SECRET_ID \
            --replication-policy="automatic" \
            --project=${PROJECT_ID} || echo "시크릿 '$ALLOYDB_SECRET_ID'가 이미 존재할 수 있습니다."

        # 시크릿 버전 추가
        echo -n "$MY_ALLOYDB_PASSWORD" | gcloud secrets versions add $ALLOYDB_SECRET_ID \
            --data-file=- \
            --project=${PROJECT_ID}

        unset MY_ALLOYDB_PASSWORD # 생성된 비밀번호 변수 삭제
        ```
        *   여기서 사용한 시크릿 이름(`alloydb-initial-password`)을 Terraform 코드의 `alloydb_password_secret_id` 변수 기본값 또는 `terraform.tfvars` 파일의 값과 일치시켜야 합니다.
4.  **Terraform 실행 계정 권한:** Terraform 코드를 실행하는 사용자 계정 또는 서비스 계정은 대상 프로젝트에서 다음 IAM 역할(또는 상응하는 권한)을 가지고 있어야 합니다.
    *   `roles/owner` 또는 `roles/editor` (가장 간단하지만 권한이 넓음)
    *   **최소 권한 (권장):**
        *   `roles/alloydb.admin`: AlloyDB 클러스터 및 인스턴스 관리
        *   `roles/compute.networkAdmin`: VPC 네트워크, 서브넷, IP 주소, 전달 규칙 관리
        *   `roles/secretmanager.secretAccessor`: Secret Manager 비밀번호 값 읽기
        *   `roles/serviceusage.serviceUsageAdmin`: API 활성화
        *   `roles/iam.serviceAccountTokenCreator`: (사용자 계정으로 ADC 사용 시 또는 서비스 계정 가장 시 필요)
    *   **권한 부여 예시 (사용자 계정):**
        ```bash
        export TERRAFORM_USER_EMAIL="your-email@example.com"
        export PROJECT_ID="p-khm8-dev-svc"

        gcloud projects add-iam-policy-binding $PROJECT_ID --member="user:$TERRAFORM_USER_EMAIL" --role="roles/alloydb.admin"
        gcloud projects add-iam-policy-binding $PROJECT_ID --member="user:$TERRAFORM_USER_EMAIL" --role="roles/compute.networkAdmin"
        gcloud projects add-iam-policy-binding $PROJECT_ID --member="user:$TERRAFORM_USER_EMAIL" --role="roles/secretmanager.secretAccessor"
        gcloud projects add-iam-policy-binding $PROJECT_ID --member="user:$TERRAFORM_USER_EMAIL" --role="roles/serviceusage.serviceUsageAdmin"
        gcloud projects add-iam-policy-binding $PROJECT_ID --member="user:$TERRAFORM_USER_EMAIL" --role="roles/iam.serviceAccountTokenCreator"
        ```

## **사용 방법 (Usage):**

1.  **코드 준비:** 이 저장소의 Terraform 코드(`.tf` 파일)를 로컬 환경에 복제하거나 다운로드합니다.
2.  **변수 설정:**
    *   **`terraform.tfvars` 파일 생성:** 코드 디렉토리에 `terraform.tfvars` 파일을 만들고 필수 변수 값을 지정합니다. **비밀번호는 이 파일에 넣지 마세요.**
    *   **필수 변수:**
        *   `project_id`: Google Cloud 프로젝트 ID (예: `"p-khm8-dev-svc"`)
        *   `region`: 리소스 생성 리전 (예: `"asia-northeast3"`)
        *   `subnetwork_name`: PSC IP를 할당할 서브넷 이름 (예: `"default"`)
    *   **선택적 변수 (기본값 변경 시):** `network_name`, `cluster_id`, `instance_id`, `alloydb_user`, `alloydb_password_secret_id` 등 (`variables.tf` 파일 참조)
    *   **`terraform.tfvars` 예시:**
        ```hcl
        project_id       = "p-khm8-dev-svc"
        region           = "asia-northeast3"
        subnetwork_name  = "default" # 실제 환경의 서브넷 이름 확인
        ```
3.  **Terraform 초기화:** 터미널에서 코드 디렉토리로 이동 후 실행합니다.
    ```bash
    terraform init
    ```
4.  **실행 계획 확인 (권장):** 생성/수정될 리소스를 미리 확인합니다.
    ```bash
    terraform plan -var-file=terraform.tfvars
    ```
5.  **리소스 생성/수정:** 계획 확인 후 리소스를 적용합니다.
    ```bash
    terraform apply -var-file=terraform.tfvars
    ```
    *   `apply` 명령 실행 시 확인 프롬프트가 나타납니다. `yes`를 입력하여 진행합니다. (`-auto-approve` 플래그로 생략 가능)

## **접속 테스트 (Connection Test)**

Terraform `apply`가 성공적으로 완료된 후, 생성된 PSC 엔드포인트를 통해 AlloyDB 인스턴스에 연결할 수 있는지 확인합니다. 테스트는 **반드시 PSC 엔드포인트와 동일한 VPC 네트워크 내부에서** 수행해야 합니다.

### **테스트 단계:**

1.  **필요 정보 확인:**
    *   **PSC 엔드포인트 IP 주소:** `terraform apply` 완료 후 출력된 `psc_endpoint_ip_address` 값.
    *   **데이터베이스 사용자:** Terraform 변수 `alloydb_user` 값 (기본값: `postgres`).
    *   **데이터베이스 비밀번호:** Secret Manager에 저장한 비밀번호. (테스트 시 직접 입력하거나 `gcloud secrets versions access latest --secret="alloydb-initial-password"` 로 확인)
    *   **리전/영역/VPC/서브넷:** 테스트 VM 생성에 필요한 정보 (Terraform 변수 값과 동일하게 사용).

2.  **테스트용 GCE VM 생성:** PSC 엔드포인트와 동일한 VPC/서브넷에 임시 VM 생성.
    ```bash
    export PROJECT_ID="p-khm8-dev-svc"
    export REGION="asia-northeast3"
    export ZONE="asia-northeast3-a" # 또는 해당 리전의 다른 가용 영역
    export NETWORK_NAME="default"
    export SUBNET_NAME="default" # PSC IP가 예약된 서브넷
    export TEST_VM_NAME="alloydb-psc-test-vm"

    gcloud compute instances create $TEST_VM_NAME \
        --project=$PROJECT_ID --zone=$ZONE --machine-type=e2-small \
        --image-family=debian-12 --image-project=debian-cloud \
        --network=$NETWORK_NAME --subnet=$SUBNET_NAME \
        --scopes="https://www.googleapis.com/auth/cloud-platform" \
        --shielded-secure-boot
    ```

3.  **GCE VM 접속:**
    ```bash
    gcloud compute ssh $TEST_VM_NAME --project $PROJECT_ID --zone $ZONE
    ```

4.  **VM 내부에 PostgreSQL 클라이언트 설치:**
    ```bash
    sudo apt-get update && sudo apt-get install -y postgresql-client telnet
    ```

5.  **네트워크 연결 테스트 (telnet - 선택 사항):** PSC 엔드포인트 IP와 포트(5432)로 TCP 연결 확인.
    ```bash
    export PSC_ENDPOINT_IP="YOUR_PSC_ENDPOINT_IP" # Terraform 출력값으로 대체
    telnet $PSC_ENDPOINT_IP 5432
    ```    *   성공: `Connected to ...` / 실패: VPC 방화벽 규칙 확인.

6.  **AlloyDB 기본 DB 연결 테스트 (psql):** `postgres` 데이터베이스로 연결 및 인증 테스트.
    ```bash
    export PSC_ENDPOINT_IP="YOUR_PSC_ENDPOINT_IP"
    export ALLOYDB_USER="postgres"

    echo "AlloyDB 기본 DB 연결 시도 (비밀번호 입력 필요)..."
    psql -h $PSC_ENDPOINT_IP -U $ALLOYDB_USER -d postgres
    ```    *   비밀번호 입력 후 `postgres=>` 프롬프트 확인.
    *   종료: `\q`

7.  **(연결 성공 시) `movies` 데이터베이스 생성 및 확장 활성화 (예시):** PSC 엔드포인트 IP 사용.
    ```bash
    export PSC_ENDPOINT_IP="YOUR_PSC_ENDPOINT_IP"
    export PGPASSWORD='YOUR_SECRET_PASSWORD' # 비밀번호 환경 변수 설정 (또는 psql 내부 입력)

    psql -h $PSC_ENDPOINT_IP -U postgres -c 'CREATE DATABASE movies;'
    psql -h $PSC_ENDPOINT_IP -U postgres -d movies -c 'CREATE EXTENSION IF NOT EXISTS alloydb_scann CASCADE;'

    unset PGPASSWORD
    ```

8.  **테스트 VM 정리:**
    *   VM 접속 종료: `exit`
    *   VM 삭제: `gcloud compute instances delete $TEST_VM_NAME --project $PROJECT_ID --zone $ZONE --quiet`

## **리소스 삭제 (Resource Deletion):**

Terraform으로 생성한 리소스를 삭제하려면 코드 디렉토리에서 다음 명령어를 실행합니다.

```bash
terraform destroy -var-file=terraform.tfvars
```

*   **경고:** 이 명령어는 AlloyDB 클러스터, 인스턴스, PSC 관련 리소스 등을 **영구적으로 삭제**하며, 데이터는 복구되지 않습니다.
*   **주의:** Secret Manager에 생성된 비밀번호 시크릿은 Terraform으로 관리되지 않으므로, 필요 없다면 Google Cloud Console 또는 `gcloud secrets delete` 명령어를 사용하여 **별도로 삭제**해야 합니다.

## **중요 참고 사항 (Important Notes):**

*   **Service Attachment Link 참조:** PSC 전달 규칙(`google_compute_forwarding_rule`)의 `target` 인수에 사용되는 Service Attachment URL은 **`google_alloydb_instance` 리소스의 `psc_instance_config.service_attachment_link` 속성**에서 가져옵니다. 이는 클러스터가 아닌 **인스턴스 레벨**의 속성이며, Terraform `apply` 후에 값이 결정되는 Computed 속성입니다. (이전 논의 과정에서 혼란이 있었던 부분입니다.)
*   **서브네트워크:** PSC 엔드포인트 IP 주소를 예약하는 `google_compute_address` 리소스에는 반드시 `subnetwork` 인수를 지정해야 합니다.
*   **애플리케이션 연결:** Cloud Run, GKE 등의 애플리케이션에서 AlloyDB에 연결할 때는 호스트 정보로 **PSC 엔드포인트 IP 주소** (`psc_endpoint_ip_address` 출력값)를 사용해야 합니다. 포트는 5432입니다.
*   **방화벽 규칙:** 애플리케이션 환경에서 **PSC 엔드포인트 IP 주소의 TCP 포트 5432**로 **송신(Egress)** 트래픽을 허용하는 VPC 방화벽 규칙이 필요할 수 있습니다.
*   **Cloud Run / GKE 연결:** Cloud Run 또는 GKE에서 이 PSC 엔드포인트를 사용하려면 해당 서비스/클러스터가 **동일한 VPC 네트워크에 연결**되어 있어야 합니다 (Direct VPC Egress 또는 VPC Connector 사용).

## **참조 링크 (Reference Links):**

*   **AlloyDB 개요:** [https://cloud.google.com/alloydb/docs/overview?hl=ko](https://cloud.google.com/alloydb/docs/overview?hl=ko)
*   **Private Service Connect 개요:** [https://cloud.google.com/vpc/docs/private-service-connect?hl=ko](https://cloud.google.com/vpc/docs/private-service-connect?hl=ko)
*   **AlloyDB에서 PSC 사용:** [https://cloud.google.com/alloydb/docs/private-service-connect?hl=ko](https://cloud.google.com/alloydb/docs/private-service-connect?hl=ko)
*   **Terraform Google Provider - AlloyDB Cluster:** [https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/alloydb_cluster](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/alloydb_cluster)
*   **Terraform Google Provider - AlloyDB Instance:** [https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/alloydb_instance](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/alloydb_instance)
*   **Terraform Google Provider - Compute Address:** [https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_address](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_address)
*   **Terraform Google Provider - Compute Forwarding Rule:** [https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_forwarding_rule](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_forwarding_rule)
*   **Google Secret Manager:** [https://cloud.google.com/secret-manager/docs?hl=ko](https://cloud.google.com/secret-manager/docs?hl=ko)
*   **Cloud Run VPC 네트워크 연결:** [https://cloud.google.com/run/docs/configuring/connecting-vpc?hl=ko](https://cloud.google.com/run/docs/configuring/connecting-vpc?hl=ko)
