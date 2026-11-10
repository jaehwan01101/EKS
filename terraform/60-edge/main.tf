# 단일 도메인 + 경로 분기
#
#   https://example.com/*       → CloudFront → S3 (정적 파일, 캐시)
#   https://example.com/api/*   → CloudFront → origin.example.com (ALB → EKS, 캐시 안 함)
#
# API 오리진을 ALB DNS 가 아닌 고정 호스트명(origin.<domain>)으로 잡는다.
# ALB 는 클러스터를 지웠다 만들 때마다 바뀌지만, ExternalDNS 가 이 이름을 새 ALB 로 다시 가리키므로
# 이 레이어는 EKS 보다 먼저, 그리고 EKS 와 무관하게 apply 할 수 있다. (클러스터가 없으면 /api 만 502)

data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "10-foundation/terraform.tfstate"
    region = var.region
  }
}

locals {
  foundation    = data.terraform_remote_state.foundation.outputs
  s3_origin_id  = "frontend-s3"
  api_origin_id = "api-alb"
}

# ---------------------------------------------------------------------------
# 프론트엔드 S3 버킷 (비공개, CloudFront 만 읽을 수 있음)
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project}-frontend-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 프론트는 canary 가 없으므로, 잘못 배포했을 때 이전 파일로 되돌릴 수단으로 버전 관리를 켠다.
resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project}-frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontRead"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.this.arn }
      }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

# ---------------------------------------------------------------------------
# ALB 직접 접근 차단용 시크릿 헤더
# ---------------------------------------------------------------------------
# CloudFront 가 API 요청에 이 헤더를 붙이고, ALB 리스너 규칙이 헤더 값이 맞을 때만 통과시킨다.
# ALB 보안 그룹을 CloudFront prefix list 로 제한하는 것과 함께 써야 한다
# (prefix list 만으로는 "다른 사람의 CloudFront" 를 거쳐 들어오는 요청을 막지 못한다).
# 값은 Ingress 설정에서 읽도록 SSM Parameter Store 에 둔다. Standard 등급은 무료.

resource "random_password" "origin_verify" {
  length  = 48
  special = false
}

resource "aws_ssm_parameter" "origin_verify" {
  name  = "/${var.project}/edge/origin-verify-header"
  type  = "SecureString"
  value = random_password.origin_verify.result
}

# ---------------------------------------------------------------------------
# CloudFront
# ---------------------------------------------------------------------------

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Host 헤더만 빼고 쿼리스트링·쿠키·헤더를 전부 오리진으로 넘긴다.
# Host 는 오리진 이름(origin.<domain>)으로 바뀌어야 ALB 인증서와 맞는다.
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  comment             = "${var.project} frontend + api"
  aliases             = [local.foundation.domain_name]
  default_root_object = "index.html"
  price_class         = var.price_class
  http_version        = "http2and3"
  is_ipv6_enabled     = true

  origin {
    origin_id                = local.s3_origin_id
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  origin {
    origin_id   = local.api_origin_id
    domain_name = local.foundation.origin_domain

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 30
      origin_keepalive_timeout = 5
    }

    custom_header {
      name  = "X-Origin-Verify"
      value = random_password.origin_verify.result
    }
  }

  # /api/* → ALB. 캐시하지 않고 모든 메서드 허용.
  ordered_cache_behavior {
    path_pattern           = var.api_path_pattern
    target_origin_id       = local.api_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
  }

  # 나머지 → S3 정적 파일. 캐시함.
  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
  }

  # 주의: custom_error_response(403/404 → /index.html) 를 넣지 않는다.
  # 배포 전체에 적용되기 때문에 API 의 404 까지 index.html 로 바뀌어 버린다.
  # 클라이언트 라우팅이 있는 SPA 가 되면 CloudFront Function 으로 기본 동작에만 적용할 것.

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = local.foundation.cloudfront_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# ---------------------------------------------------------------------------
# DNS: example.com → CloudFront
# ---------------------------------------------------------------------------

resource "aws_route53_record" "apex" {
  for_each = toset(["A", "AAAA"])

  zone_id = local.foundation.zone_id
  name    = local.foundation.domain_name
  type    = each.value

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
