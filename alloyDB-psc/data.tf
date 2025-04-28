# --- Data Sources ---
# --- Project Number 가져오기 Data Source ---
data "google_project" "current" {
  project_id = var.project_id
}

data "google_compute_network" "main" {
  project = var.project_id
  name    = var.network_name
}

data "google_compute_subnetwork" "psc_subnet" {
  project = var.project_id
  name    = var.subnetwork_name
  region  = var.region
}

# Secret Manager에서 비밀번호 값 가져오기
data "google_secret_manager_secret_version" "alloydb_password_data" {
  project = var.project_id
  secret  = var.alloydb_password_secret_id
  version = var.alloydb_password_secret_version

  depends_on = [google_project_service.apis] # API 활성화 후 실행 보장
}
