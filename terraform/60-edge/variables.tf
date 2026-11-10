variable "project" {
  type = string
}

variable "region" {
  type = string
}

variable "state_bucket" {
  description = "다른 레이어의 output 을 읽을 state 버킷"
  type        = string
}

variable "api_path_pattern" {
  description = "ALB(EKS)로 보낼 경로. 나머지는 전부 S3 정적 파일."
  type        = string
  default     = "/api/*"
}

variable "price_class" {
  description = "PriceClass_200 은 한국/일본 엣지를 포함하면서 남미·오세아니아 등 비싼 엣지를 뺀다."
  type        = string
  default     = "PriceClass_200"
}
