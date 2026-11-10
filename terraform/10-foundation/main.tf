# 거의 바뀌지 않고 비용도 미미해서 클러스터를 지워도 남겨두는 리소스들.

locals {
  # CloudFront 뒤에 숨는 ALB 의 이름. 사용자는 이 주소를 쓰지 않는다.
  origin_domain = "origin.${var.domain_name}"
}

# Route 53 에서 도메인을 사면 호스팅 영역이 자동으로 생기므로 새로 만들지 않고 조회만 한다.
# (새로 만들면 등록된 NS 와 어긋나서 도메인이 동작하지 않는다)
data "aws_route53_zone" "this" {
  name         = var.domain_name
  private_zone = false
}

# ---------------------------------------------------------------------------
# ACM 인증서
# ---------------------------------------------------------------------------

# 사용자 → CloudFront (us-east-1)
resource "aws_acm_certificate" "cloudfront" {
  provider = aws.us_east_1

  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront → ALB (서울). 오리진 구간도 HTTPS 로 암호화한다.
resource "aws_acm_certificate" "origin" {
  domain_name       = local.origin_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  validation_records = {
    for dvo in concat(
      tolist(aws_acm_certificate.cloudfront.domain_validation_options),
      tolist(aws_acm_certificate.origin.domain_validation_options),
    ) : dvo.domain_name => dvo
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = local.validation_records

  zone_id         = data.aws_route53_zone.this.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cloudfront" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [aws_route53_record.acm_validation[var.domain_name].fqdn]
}

resource "aws_acm_certificate_validation" "origin" {
  certificate_arn         = aws_acm_certificate.origin.arn
  validation_record_fqdns = [aws_route53_record.acm_validation[local.origin_domain].fqdn]
}

# ---------------------------------------------------------------------------
# ECR
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  for_each = toset(var.ecr_repositories)

  name = each.value

  # 같은 태그 덮어쓰기 금지 → Git 의 이미지 태그(commit SHA)가 항상 같은 이미지를 가리킨다.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true # Basic 스캔 (무료)
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "최근 30개 이미지만 보관"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 30
      }
      action = { type = "expire" }
    }]
  })
}
