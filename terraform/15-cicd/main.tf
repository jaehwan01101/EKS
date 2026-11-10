# GitHub Actions 가 장기 액세스 키 없이 AWS 에 인증하도록 하는 OIDC 설정.
#
#   GitHub Actions ──(1. 실행마다 발급되는 OIDC 토큰)──▶ AWS STS
#                  ◀─(2. 신뢰 조건 검증 후 임시 자격 증명, 기본 1시간)── IAM 역할
#
# 1) 신원 제공자 등록  2) 역할의 신뢰 정책(누가 맡을 수 있나)  3) 역할의 권한 정책(맡으면 뭘 할 수 있나)

# ── 1) AWS 가 GitHub 이 발급한 토큰을 신뢰하도록 등록 ──────────────────────────────
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# ── 2) 신뢰 정책: 이 역할을 누가 맡을 수 있나 ───────────────────────────────────────
data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # aud: 토큰이 "AWS STS 용"으로 발급됐는지
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # sub: 토큰을 발급받은 "저장소와 브랜치". 이 한 줄이 보안의 핵심이다.
    # 이 조건이 없거나 느슨하면(예: repo:*) 다른 사람의 저장소도 이 역할을 맡을 수 있다.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = "${var.project}-github-actions"
  assume_role_policy   = data.aws_iam_policy_document.github_trust.json
  max_session_duration = 3600
}

# ── 3) 권한 정책: 역할을 맡으면 무엇을 할 수 있나 (ECR 이미지 푸시만) ────────────────
data "aws_ecr_repository" "app" {
  name = var.ecr_repository_name
}

data "aws_iam_policy_document" "ecr_push" {
  # 로그인 토큰 발급은 특정 저장소로 한정할 수 없는 API 라서 resources 가 "*" 이다.
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # 이미지 업로드와 조회는 이 저장소 하나로만 한정한다.
  statement {
    sid = "EcrPushToOneRepository"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
    ]
    resources = [data.aws_ecr_repository.app.arn]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.ecr_push.json
}
