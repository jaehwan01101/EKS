# External Secrets Operator: SSM Parameter Store 의 값을 쿠버네티스 Secret 으로 동기화한다.
# 최소 권한: /<project>/* 경로의 파라미터 읽기만 허용한다. 다른 경로, 쓰기, 삭제는 불가.
data "aws_iam_policy_document" "external_secrets" {
  statement {
    sid       = "ReadProjectParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project}/*"]
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "${var.project}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy" "external_secrets" {
  name   = "read-project-parameters"
  role   = aws_iam_role.external_secrets.id
  policy = data.aws_iam_policy_document.external_secrets.json
}

# 서비스 어카운트 external-secrets/external-secrets 가 ESO 컨트롤러다 (Helm 차트 기본값).
resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = local.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets.arn
}
