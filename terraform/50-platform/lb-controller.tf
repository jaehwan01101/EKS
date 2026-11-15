# AWS Load Balancer Controller 가 쓸 AWS 권한.
#
# 이 파일은 컨트롤러를 설치하지 않는다. 컨트롤러(클러스터 안에서 도는 Pod)는 Argo CD 가 설치한다.
# 여기서 만드는 것은 "그 Pod 가 AWS API 로 ALB 를 만들 수 있는 권한" 뿐이다.
#
# 정책은 AWS 공식 JSON(kubernetes-sigs/aws-load-balancer-controller v3.6.2, docs/install/iam_policy.json) 그대로다.
# 컨트롤러 버전을 올리면 이 JSON 도 같은 버전의 것으로 교체한다.
resource "aws_iam_role" "lb_controller" {
  name               = "${var.project}-lb-controller"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

# 압축 기준 약 5.2KB 라 인라인 정책 한도(10,240자)에 들어간다.
resource "aws_iam_role_policy" "lb_controller" {
  name   = "aws-load-balancer-controller"
  role   = aws_iam_role.lb_controller.id
  policy = file("${path.module}/policies/aws-load-balancer-controller.json")
}

# "kube-system 의 aws-load-balancer-controller 서비스 어카운트 = 위 역할" 연결.
# Helm 차트의 서비스 어카운트 이름이 다르면 ALB 가 만들어지지 않으니 차트 설정과 반드시 같아야 한다.
resource "aws_eks_pod_identity_association" "lb_controller" {
  cluster_name    = local.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lb_controller.arn
}
