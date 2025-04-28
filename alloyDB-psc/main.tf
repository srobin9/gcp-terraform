# --- API Enablement ---
resource "google_project_service" "apis" {
  for_each = toset([
    "alloydb.googleapis.com",
    "compute.googleapis.com",
    "servicenetworking.googleapis.com",
    "secretmanager.googleapis.com" # Secret Manager API 추가
  ])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

# --- AlloyDB Cluster ---
resource "google_alloydb_cluster" "main" {
  project     = var.project_id
  location    = var.region
  cluster_id  = var.cluster_id
  network_config {
    network = data.google_compute_network.main.id
  }
  initial_user {
    user     = var.alloydb_user
    # Secret Manager에서 가져온 비밀번호 값 사용 (sensitive 처리)
    password = sensitive(data.google_secret_manager_secret_version.alloydb_password_data.secret_data)
  }

  # 클러스터 생성 시 자동으로 PSC 서비스 연결(Service Attachment)이 생성됨
  # Terraform에서는 이 서비스 연결을 직접 생성/관리하지 않음

  depends_on = [
    google_project_service.apis,
    data.google_secret_manager_secret_version.alloydb_password_data # 비밀번호 로드 후 클러스터 생성
  ]
}

# --- AlloyDB Primary Instance ---
resource "google_alloydb_instance" "primary" {
  project       = var.project_id
  cluster       = google_alloydb_cluster.main.name
  instance_id   = var.instance_id
  instance_type = "PRIMARY"

  machine_config {
    cpu_count = var.instance_cpu_count
  }

  # availability_type = "REGIONAL" # 필요시 설정 (기본값)

  depends_on = [google_alloydb_cluster.main]
}

# --- Private Service Connect (PSC) Setup ---

# 1. PSC 엔드포인트용 내부 IP 주소 예약
resource "google_compute_address" "psc_ip" {
  project      = var.project_id
  name         = var.psc_ip_name
  subnetwork   = data.google_compute_subnetwork.psc_subnet.id
  address_type = "INTERNAL"
  region       = var.region
  purpose      = "PRIVATE_SERVICE_CONNECT" # PSC 용도로 명시
  network      = data.google_compute_network.main.id

  depends_on = [google_project_service.apis]
}

# 2. PSC 엔드포인트(전달 규칙) 생성
resource "google_compute_forwarding_rule" "psc_endpoint" {
  project               = var.project_id
  name                  = var.psc_endpoint_name
  region                = var.region
  network               = data.google_compute_network.main.id
  subnetwork            = data.google_compute_subnetwork.psc_subnet.id
  ip_address            = google_compute_address.psc_ip.self_link
  target                = google_alloydb_cluster.main.psc_config[0].service_attachment_link # 클러스터의 서비스 연결 타겟 지정
  load_balancing_scheme = "" # PSC for Google APIs/Services 에서는 빈 문자열 또는 생략

  # target = "alloydb.googleapis.com" # Target Service Name 방식도 있으나, 여기서는 Service Attachment 방식 사용

  depends_on = [
    google_alloydb_cluster.main, # 클러스터 및 서비스 연결이 준비되어야 함
    google_compute_address.psc_ip
  ]
}