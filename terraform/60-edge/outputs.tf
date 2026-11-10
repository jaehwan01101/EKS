output "frontend_bucket" {
  description = "프론트 CI 가 s3 sync 할 버킷"
  value       = aws_s3_bucket.frontend.bucket
}

output "cloudfront_distribution_id" {
  description = "프론트 배포 후 캐시 무효화(create-invalidation)에 쓸 ID"
  value       = aws_cloudfront_distribution.this.id
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "origin_verify_ssm_parameter" {
  description = "ALB 리스너 규칙에서 검증할 헤더 값이 저장된 SSM 파라미터"
  value       = aws_ssm_parameter.origin_verify.name
}
