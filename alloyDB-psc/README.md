네, 지적 감사합니다. 이전 버전에 중복되거나 정제되지 않은 부분이 있었던 것 같습니다. 내용을 간결하게 다듬고 흐름을 개선하여 README 파일을 다시 작성했습니다.

---

# **AlloyDB PSC 연결 Terraform 설정 및 테스트 가이드**
**(AlloyDB PSC Connection Terraform Setup and Test Guide)**

## **목적 (Purpose)**

이 Terraform 코드는 Google Cloud 환경에서 다음을 수행하는 것을 목표로 합니다:

*   AlloyDB 클러스터 및 기본 인스턴스를 Private Service Connect (PSC) 방식으로 프로비저닝합니다.
*   Google Secret Manager를 사용하여 AlloyDB 초기 비밀번호를 안전하게 관리합니다.
*   생성된 AlloyDB 인스턴스에 PSC 엔드포인트를 통해 비공개로 연결할 수 있도록 구성합니다.
*   Terraform을 사용하여 관련 인프라를 코드로 관리합니다 (Infrastructure as Code).

## **핵심 원리 (Core Principles):**

*   **PSC 엔드포인트:** 사용자의 VPC 네트워크 내에 내부 IP 주소를 가진 전달 규칙(Forwarding Rule)을 생성하여 AlloyDB 서비스에 대한 비공개 연결 지점(엔드포인트)을 만듭니다.
*   **자동 서비스 연결:** AlloyDB 인스턴스 생성 시 PSC 연결을 위한 서비스 연결(Service Attachment)이 Google Cloud에 의해 자동으로 관리됩니다. 전달 규칙은 이 서비스 연결을 타겟으로 합니다.
*   **보안 비밀번호:** Secret Manager를 사용하여 데이터베이스 비밀번호를 코드 외부에서 안전하게 관리하고 Terraform 실행 시 참조합니다.
*   **비공개 연결:** 애플리케이션은 VPC 내에서 PSC 엔드포인트 IP 주소를 통해 AlloyDB에 연결하므로, 데이터베이스 트래픽이 공용 인터넷을 통하지 않습니다.

## **요구 사항 (Requirements):**

*   Terraform (v1.0 이상 권장)
*   Google Cloud SDK (`gcloud` CLI)
*   Google Cloud 프로젝트 및 VPC 네트워크 (`default` 네트워크 사용 가정)
*   Terraform 실행을 위한 적절한 IAM 권한 (아래 '사전 준비 사항' 참조)

## **사전 준비 사항 (Prerequisites):**

1.  **필수 API 활성화:** 대상 프로젝트에서 다음 API들이 활성화되어 있어야 합니다.
    ```bash
    export PROJECT_ID="YOUR_PROJECT_ID" # 실제 프로젝트 ID로 변경

    gcloud services enable alloydb.googleapis.com \
                           compute.googleapis.com \
                           secretmanager.googleapis.com \
                           servicenetworking.googleapis.com \
                           --project=${PROJECT_ID}
    ```
2.  **AlloyDB 비밀번호 시크릿 생성:** Secret Manager에 AlloyDB 초기 비밀번호를 저장할 시크릿을 미리 생성합니다.
    ```bash
    export PROJECT_ID="YOUR_PROJECT_ID"
    export ALLOYDB_SECRET_ID="alloydb-initial-password" # Terraform 변수와 일치시킬 이름

    # (선택) 비밀번호 생성 및 환경 변수 설정
    export MY_ALLOYDB_PASSWORD=$(openssl rand -base64 16)
    echo "Password (save securely): $MY_ALLOYDB_PASSWORD"

    # 시크릿 생성 (이미 있으면 오류 발생, 무시 가능)
    gcloud secrets create ${ALLOYDB_SECRET_ID} \
        --replication-policy="automatic" \
        --project=${PROJECT_ID} || echo "Secret ${ALLOYDB_SECRET_ID} might already exist."

    # 시크릿 버전 추가 (비밀번호 값 저장)
    echo -n "${MY_ALLOYDB_PASSWORD}" | gcloud secrets versions add ${ALLOYDB_SECRET_ID} \
        --data-file=- \
        --project=${PROJECT_ID}

    # 비밀번호 변수 삭제 (보안)
    unset MY_ALLOYDB_PASSWORD
    ```
3.  **Terraform 실행 계정 권한 부여:** Terraform을 실행하는 사용자 또는 서비스 계정에 다음 IAM 역할을 부여합니다.
    *   **최소 권한:** `roles/alloydb.admin`, `roles/compute.networkAdmin`, `roles/secretmanager.secretAccessor`, `roles/serviceusage.serviceUsageAdmin`, `roles/iam.serviceAccountTokenCreator` (ADC 사용 시)
    *   **권한 부여 예시 (사용자 계정):**
        ```bash
        export TERRAFORM_USER_EMAIL="your-email@example.com"
        export PROJECT_ID="YOUR_PROJECT_ID"

        gcloud projects add-iam-policy-binding $PROJECT_ID --member="user:$TERRAFORM_USER_EMAIL" --role="roles/alloydb.admin"
        gcloud projects add-iam-policy-binding $PROJECT_ID --member="user:$TERRAFORM_USER_EMAIL" --role="roles/compute.networkAdmin"
        gcloud projects add-iam-policy-binding $PROJECT_ID --member="user:$TERRAFORM_USER_EMAIL" --role="roles/secretmanager.secretAccessor"
        gcloud projects add-iam-policy-binding $PROJECT_ID --member="user:$TERRAFORM_USER_EMAIL" --role="roles/serviceusage.serviceUsageAdmin"
        gcloud projects add-iam-policy-binding $PROJECT_ID --member="user:$TERRAFORM_USER_EMAIL" --role="roles/iam.serviceAccountTokenCreator"
        ```

## **사용 방법 (Usage):**

1.  **코드 준비:** 이 저장소의 Terraform 코드(`.tf`)를 로컬에 준비합니다.
2.  **변수 설정 (`terraform.tfvars`):** 코드 디렉토리에 `terraform.tfvars` 파일을 생성하고 필수 변수 값을 지정합니다. (비밀번호는 넣지 않습니다.)
    ```hcl
    # terraform.tfvars 예시
    project_id       = "p-khm8-dev-svc"
    region           = "asia-northeast3"
    subnetwork_name  = "default" # PSC IP를 할당할 서브넷 이름 확인
    # alloydb_password_secret_id = "custom-secret-name" # 기본값 외 다른 시크릿 이름 사용 시
    # cluster_id = "my-cluster" # 필요시 변경
    # instance_id = "my-instance" # 필요시 변경
    ```
3.  **Terraform 초기화:**
    ```bash
    terraform init
    ```
4.  **실행 계획 확인 (선택 사항):**
    ```bash
    terraform plan -var-file=terraform.tfvars
    ```
5.  **리소스 생성/수정:**
    ```bash
    terraform apply -var-file=terraform.tfvars
    ```
    *   실행 계획을 검토하고 `yes`를 입력하여 적용합니다.

## **접속 테스트 (Connection Test)**

Terraform `apply` 완료 후, PSC 엔드포인트를 통해 AlloyDB 인스턴스에 연결되는지 **동일 VPC 네트워크 내에서** 테스트합니다.

### **테스트 단계:**

1.  **정보 확인:** `terraform apply` 출력값에서 `psc_endpoint_ip_address` 확인, Secret Manager에서 비밀번호 확인.
2.  **테스트 VM 생성:** AlloyDB와 동일 VPC/서브넷에 GCE VM 생성 (위 '사전 준비 사항'의 VM 생성 명령어 참조).
3.  **VM 접속:** `gcloud compute ssh ...`
4.  **PostgreSQL 클라이언트 설치:** `sudo apt-get update && sudo apt-get install -y postgresql-client telnet`
5.  **네트워크 테스트 (telnet):** `telnet YOUR_PSC_ENDPOINT_IP 5432` (성공 시 `Connected...`)
6.  **기본 DB 연결 테스트 (psql):**
    ```bash
    export PSC_ENDPOINT_IP="YOUR_PSC_ENDPOINT_IP"
    export ALLOYDB_USER="postgres" # Terraform 변수 값 확인

    psql -h $PSC_ENDPOINT_IP -U $ALLOYDB_USER -d postgres
    # 비밀번호 프롬프트에서 Secret Manager 비밀번호 입력
    ```
    *   성공 시 `postgres=>` 프롬프트 확인. (`\q`로 종료)
7.  **(선택) `movies` DB 생성 및 확장 활성화:**
    ```bash
    export PSC_ENDPOINT_IP="YOUR_PSC_ENDPOINT_IP"
    export PGPASSWORD='YOUR_SECRET_PASSWORD' # 또는 대화형 입력

    psql -h $PSC_ENDPOINT_IP -U postgres -c 'CREATE DATABASE movies;'
    psql -h $PSC_ENDPOINT_IP -U postgres -d movies -c 'CREATE EXTENSION IF NOT EXISTS alloydb_scann CASCADE;'

    unset PGPASSWORD
    ```
8.  **테스트 VM 정리:** `exit` 후 `gcloud compute instances delete ...`

## **리소스 삭제 (Resource Deletion):**

Terraform으로 생성한 리소스를 삭제하려면 코드 디렉토리에서 실행합니다.

```bash
terraform destroy -var-file=terraform.tfvars
```

*   **경고:** AlloyDB 클러스터, 인스턴스 등 모든 관련 리소스와 데이터가 영구 삭제됩니다.
*   **주의:** Secret Manager 시크릿은 Terraform으로 관리되지 않으므로 별도로 삭제해야 합니다 (`gcloud secrets delete ...`).

## **중요 참고 사항 (Important Notes):**

*   **Service Attachment Link:** PSC 전달 규칙(`google_compute_forwarding_rule`)의 `target`은 **AlloyDB 인스턴스(`google_alloydb_instance`)** 리소스의 **`psc_instance_config.service_attachment_link`** 속성을 참조하여 설정됩니다. 이 값은 Terraform `apply` 후에 계산됩니다.
*   **애플리케이션 연결:** 애플리케이션(Cloud Run 등)은 **PSC 엔드포인트 IP 주소** (`psc_endpoint_ip_address` 출력값)를 호스트로 사용하여 포트 5432로 AlloyDB에 연결해야 합니다.
*   **방화벽:** 애플리케이션 환경에서 PSC 엔드포인트 IP의 TCP 포트 5432로 **송신(Egress) 트래픽**을 허용하는 VPC 방화벽 규칙이 필요할 수 있습니다.
*   **Cloud Run/GKE:** Cloud Run 또는 GKE에서 이 PSC 엔드포인트를 사용하려면, 해당 서비스/클러스터가 **동일한 VPC 네트워크에 연결**되어 있어야 합니다 (Direct VPC Egress 또는 VPC Connector 사용).

## **참조 링크 (Reference Links):**

*   AlloyDB 개요: [https://cloud.google.com/alloydb/docs/overview?hl=ko](https://cloud.google.com/alloydb/docs/overview?hl=ko)
*   Private Service Connect 개요: [https://cloud.google.com/vpc/docs/private-service-connect?hl=ko](https://cloud.google.com/vpc/docs/private-service-connect?hl=ko)
*   AlloyDB에서 PSC 사용: [https://cloud.google.com/alloydb/docs/private-service-connect?hl=ko](https://cloud.google.com/alloydb/docs/private-service-connect?hl=ko)
*   Terraform Google Provider Docs:
    *   [alloydb\_cluster](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/alloydb_cluster)
    *   [alloydb\_instance](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/alloydb_instance)
    *   [compute\_address](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_address)
    *   [compute\_forwarding\_rule](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_forwarding_rule)
*   Google Secret Manager: [https://cloud.google.com/secret-manager/docs?hl=ko](https://cloud.google.com/secret-manager/docs?hl=ko)
*   Cloud Run VPC 연결: [https://cloud.google.com/run/docs/configuring/connecting-vpc?hl=ko](https://cloud.google.com/run/docs/configuring/connecting-vpc?hl=ko)

---

이 버전이 더 명확하고 필요한 정보를 잘 전달하기를 바랍니다.
