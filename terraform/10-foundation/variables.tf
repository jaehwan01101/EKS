variable "project" {
  type = string
}

variable "region" {
  type = string
}

variable "domain_name" {
  description = "서비스 도메인 (예: example.com). Route 53 호스팅 영역이 이미 있어야 한다."
  type        = string
}

variable "ecr_repositories" {
  description = "만들 ECR 리포지토리 이름"
  type        = list(string)
  default     = ["reservation-api"]
}
