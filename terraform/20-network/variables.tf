variable "project" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_cidr" {
  description = "서브넷 분할이 /20 기준으로 짜여 있다. 흔한 10.0/10.1 대역과 EKS 서비스 기본 대역(10.100.0.0/16, 172.20.0.0/16)은 피할 것."
  type        = string
  default     = "10.73.0.0/20"

  validation {
    condition     = endswith(var.vpc_cidr, "/20")
    error_message = "vpc_cidr 은 /20 이어야 한다 (서브넷 오프셋이 /20 기준으로 고정되어 있음)."
  }
}

variable "enable_nat_gateway" {
  description = "false 로 적용하면 NAT Gateway 와 그 EIP 만 지워진다(VPC, 서브넷은 유지). 클러스터를 내려둔 동안 시간당 과금을 끊는 용도. 다시 켜면 프라이빗 서브넷의 외부 경로가 복구된다."
  type        = bool
  default     = true
}

variable "azs" {
  description = "사용할 AZ 2개. 쓸 인스턴스 타입이 두 AZ 모두에서 제공되는지 aws ec2 describe-instance-type-offerings 로 확인할 것."
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}
