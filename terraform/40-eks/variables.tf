variable "project" {
  type = string
}

variable "region" {
  type = string
}

variable "state_bucket" {
  description = "20-network 의 state 를 읽기 위한 버킷 이름 (common.tfvars 의 값)"
  type        = string
}

variable "kubernetes_version" {
  description = "EKS 쿠버네티스 버전. 표준 지원 기간이 남은 버전만 쓸 것 (aws eks describe-cluster-versions 로 확인). 지원이 끝나면 Extended Support 로 컨트롤 플레인 요금이 크게 오른다."
  type        = string
  default     = "1.36"
}

variable "service_ipv4_cidr" {
  description = "쿠버네티스 Service(ClusterIP) 대역. 클러스터 안에서만 쓰이는 가상 대역이며 VPC(10.73.0.0/20)와 겹치면 안 된다. 클러스터 생성 후 변경 불가."
  type        = string
  default     = "10.74.0.0/20"
}

variable "node_instance_type" {
  description = "노드 인스턴스 타입. 이 계정은 무료 플랜이라 Free Tier 허용 타입만 띄울 수 있다 (aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true). 아키텍처를 바꾸면 node_ami_type 도 같이 바꿔야 한다."
  type        = string
  default     = "m7i-flex.large"
}

variable "node_ami_type" {
  description = "노드 AMI 타입. node_instance_type 의 CPU 아키텍처와 맞아야 한다 (x86: AL2023_x86_64_STANDARD, arm: AL2023_ARM_64_STANDARD)."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  description = "최초 생성 시에만 반영된다 (이후 변경은 무시됨)."
  type        = number
  default     = 2
}
