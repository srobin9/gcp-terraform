# --- Outputs ---
output "alloydb_cluster_id" {
  description = "생성된 AlloyDB 클러스터의 전체 ID"
  value       = google_alloydb_cluster.main.id
}

output "alloydb_primary_instance_name" {
  description = "생성된 AlloyDB 기본 인스턴스의 이름"
  value       = google_alloydb_instance.primary.name
}

output "psc_endpoint_ip_address" {
  description = "애플리케이션이 연결해야 할 PSC 엔드포인트의 IP 주소"
  value       = google_compute_address.psc_ip.address
}

output "psc_endpoint_name" {
  description = "생성된 PSC 엔드포인트(전달 규칙)의 이름"
  value       = google_compute_forwarding_rule.psc_endpoint.name
}

output "alloydb_cluster_service_attachment" {
  description = "AlloyDB 클러스터의 Service Attachment 링크 (참고용)"
  value       = google_alloydb_cluster.main.psc_config[0].service_attachment_link
}