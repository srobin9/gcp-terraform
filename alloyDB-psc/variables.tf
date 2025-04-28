# --- Input Variables ---
variable "project_id" {
  description = "Google Cloud 프로젝트 ID"
  type        = string
}

variable "region" {
  description = "AlloyDB 클러스터 및 관련 리소스를 생성할 리전"
  type        = string
  default     = "us-central1"
}

variable "network_name" {
  description = "AlloyDB 클러스터 및 PSC 엔드포인트가 연결될 VPC 네트워크 이름"
  type        = string
  default     = "default" # 기존 'default' 네트워크 사용 가정
}

variable "subnetwork_name" {
  description = "PSC 엔드포인트에 사용할 내부 IP 주소를 할당할 서브네트워크 이름"
  type        = string
  # default = "default" # 사용자의 서브넷 이름으로 변경 필요 (예: default)
}

variable "cluster_id" {
  description = "생성할 AlloyDB 클러스터의 ID"
  type        = string
  default     = "movies-cluster-psc"
}

variable "instance_id" {
  description = "생성할 AlloyDB 기본 인스턴스의 ID"
  type        = string
  default     = "movies-instance-psc"
}

variable "alloydb_user" {
  description = "AlloyDB 초기 사용자 이름"
  type        = string
  default     = "postgres"
}

# 비밀번호 변수 대신 Secret Manager 관련 변수 추가
variable "alloydb_password_secret_id" {
  description = "AlloyDB 비밀번호가 저장된 Secret Manager 시크릿의 ID (이름)"
  type        = string
  default     = "alloydb-initial-password" # 사전 준비에서 생성한 시크릿 이름과 일치해야 함
}

variable "instance_cpu_count" {
  description = "AlloyDB 인스턴스의 vCPU 개수"
  type        = number
  default     = 2 # PSC 테스트용으로 최소 사양 고려
}

variable "psc_ip_name" {
  description = "PSC 엔드포인트에 사용할 예약된 내부 IP 주소의 이름"
  type        = string
  default     = "alloydb-psc-ip"
}

variable "psc_endpoint_name" {
  description = "생성할 PSC 엔드포인트(전달 규칙)의 이름"
  type        = string
  default     = "alloydb-psc-endpoint"
}