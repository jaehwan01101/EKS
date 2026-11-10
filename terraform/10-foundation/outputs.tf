output "zone_id" {
  value = data.aws_route53_zone.this.zone_id
}

output "domain_name" {
  value = var.domain_name
}

output "origin_domain" {
  description = "ALB 가 받을 호스트명. Ingress(ExternalDNS)가 이 이름으로 ALB 레코드를 만든다."
  value       = local.origin_domain
}

output "cloudfront_certificate_arn" {
  value = aws_acm_certificate_validation.cloudfront.certificate_arn
}

output "origin_certificate_arn" {
  description = "ALB Ingress 에 붙일 인증서 (서울)"
  value       = aws_acm_certificate_validation.origin.certificate_arn
}

output "ecr_repository_urls" {
  value = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}
