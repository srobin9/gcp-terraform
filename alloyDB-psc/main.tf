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

  # --- PSC 설정 명시 ---
  psc_config {
    psc_enabled = true
  }

  initial_user {
    user     = var.alloydb_user
    # Secret Manager에서 가져온 비밀번호 값 사용 (sensitive 처리)
    password = sensitive(data.google_secret_manager_secret_version.alloydb_password_data.secret_data)
  }

  depends_on = [
    google_project_service.apis,
    data.google_secret_manager_secret_version.alloydb_password_data # 비밀번호 로드 후 클러스터 생성
  ]
}

# --- AlloyDB Primary Instance ---
resource "google_alloydb_instance" "primary" {
  cluster       = google_alloydb_cluster.main.name
  instance_id   = var.instance_id
  instance_type = "PRIMARY"

  machine_config {
    cpu_count = var.instance_cpu_count
  }

  # --- PSC Instance Config (프로젝트 번호 사용) ---
  psc_instance_config {
    # project_id 대신 프로젝트 번호 사용
    allowed_consumer_projects = [data.google_project.current.number]
  }
  
  # availability_type = "REGIONAL" # 필요시 설정 (기본값)

  depends_on = [google_alloydb_cluster.main]
}

# --- Private Service Connect (PSC) Setup ---
# PSC 엔드포인트용 내부 IP 주소 예약
resource "google_compute_address" "psc_ip" {
  project      = var.project_id
  name         = var.psc_ip_name
  subnetwork   = data.google_compute_subnetwork.psc_subnet.id
  address_type = "INTERNAL"
  region       = var.region

  depends_on = [google_project_service.apis["compute.googleapis.com"]]
}

# PSC 엔드포인트(전달 규칙) 생성
resource "google_compute_forwarding_rule" "psc_endpoint" {
  project               = var.project_id
  name                  = var.psc_endpoint_name
  region                = var.region
  network               = data.google_compute_network.main.id
  ip_address            = google_compute_address.psc_ip.self_link
  # *** target을 인스턴스의 Service Attachment Link로 사용 ****
  target                = google_alloydb_instance.primary.psc_instance_config[0].service_attachment_link
  load_balancing_scheme = "" # Service Attachment 타겟 시 불필요

  depends_on = [
    google_alloydb_instance.primary, # 인스턴스가 생성되고 PSC 정보가 나와야 함
    google_compute_address.psc_ip
  ]
}