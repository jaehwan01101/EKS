# 40-eks 가 내보낸 클러스터 이름을 읽는다.
data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "40-eks/terraform.tfstate"
    region = var.region
  }
}

data "aws_caller_identity" "current" {}

locals {
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
}

# Pod Identity 신뢰 정책. EKS 의 Pod Identity 서비스(pods.eks.amazonaws.com)만 이 역할을 맡을 수 있다.
# GitHub OIDC 의 sts:AssumeRoleWithWebIdentity 와 달리 sts:AssumeRole + TagSession 을 쓴다.
data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}
