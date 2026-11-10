variable "project" {
  type = string
}

variable "region" {
  type = string
}

variable "github_owner" {
  description = "GitHub 계정 또는 조직 이름"
  type        = string
}

variable "github_repo" {
  description = "이미지를 빌드하는 앱 저장소 이름"
  type        = string
}

variable "github_branch" {
  description = "이 브랜치에서 실행된 워크플로만 역할을 맡을 수 있다"
  type        = string
  default     = "main"
}

variable "ecr_repository_name" {
  description = "푸시를 허용할 ECR 저장소 (10-foundation 에서 만든 것)"
  type        = string
  default     = "reservation-api"

}

variable "github_owner_id" {
  description = "GitHub 계정의 숫자 ID. OIDC sub 에 들어간다 (이름이 재사용돼도 탈취되지 않게 하는 장치)"
  type        = string
}

variable "github_repo_id" {
  description = "GitHub 저장소의 숫자 ID. OIDC sub 에 들어간다"
  type        = string
}