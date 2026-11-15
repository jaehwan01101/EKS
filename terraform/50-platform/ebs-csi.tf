# EBS CSI 드라이버: PersistentVolumeClaim 이 EBS 볼륨을 만들 수 있게 한다.
# Prometheus, Loki 처럼 디스크가 필요한 관측성 구성요소가 쓴다.
# 없으면 PVC 가 영원히 Pending 으로 남는 것이 EKS 에서 가장 흔한 막힘 중 하나다.
#
# 위 두 개(LB 컨트롤러, ESO)와 달리 이건 EKS 가 관리하는 애드온이라 Terraform 이 직접 설치한다.
resource "aws_iam_role" "ebs_csi" {
  name               = "${var.project}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name = local.cluster_name
  addon_name   = "aws-ebs-csi-driver"

  pod_identity_association {
    role_arn        = aws_iam_role.ebs_csi.arn
    service_account = "ebs-csi-controller-sa"
  }

  depends_on = [aws_iam_role_policy_attachment.ebs_csi]
}
