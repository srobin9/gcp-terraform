# --- Provider Configuration ---
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.32.0" # PSC 관련 속성 지원 버전 확인 (최신 버전 권장)
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}