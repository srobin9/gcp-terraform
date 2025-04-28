# --- Outputs ---
output "alloydb_cluster_id" {
  description = "생성된 AlloyDB 클러스터의 전체 ID"
  value       = google_alloydb_cluster.main.id
}

output "alloydb_primary_instance_name" {
  description = "생성된 AlloyDB 기본 인스턴스의 이름"
  value       = google_alloydb_instance.primary.name
}

output "alloydb_primary_instance_service_attachment_link"{
  description = "The service attachment created when Private Service Connect (PSC) is enabled for the instance."
  value       = google_alloydb_instance.primary.psc_instance_config[0].service_attachment_link 
}

output "alloydb_primary_instance_psc_dns_name"{
  description = "The DNS name of the instance for PSC connectivity."
  value       = google_alloydb_instance.primary.psc_instance_config[0].psc_dns_name 
}

output "psc_endpoint_ip_address" {
  description = "애플리케이션이 연결해야 할 PSC 엔드포인트의 IP 주소"
  value       = google_compute_address.psc_ip.address
}

output "psc_endpoint_name" {
  description = "생성된 PSC 엔드포인트(전달 규칙)의 이름"
  value       = google_compute_forwarding_rule.psc_endpoint.name
}