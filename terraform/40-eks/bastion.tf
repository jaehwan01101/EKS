# SSM Bastion: Private 인 EKS API 서버에 닿기 위한 작은 EC2.
#
#   내 PC ──(SSM Session Manager, IAM 인증)──▶ Bastion(프라이빗 서브넷) ──443──▶ EKS API(Private 엔드포인트)
#
# 특징
#   - 인바운드 규칙이 하나도 없다. SSH 포트도, 공인 IP도, 키 페어도 없다.
#   - 접속 권한은 "ssm:StartSession" 을 가진 IAM 주체에게만 있다 (IAM 이 곧 접근 통제).
#   - 이 인스턴스의 아웃바운드 통신(SSM 서비스, 패키지 다운로드)은 20-network 의 NAT 를 쓴다.
#     NAT 를 destroy 하면 SSM 접속도 끊긴다. (SSM 용 Interface 엔드포인트 3개는 시간당 요금이 있어 쓰지 않았다)
#
# 주의: Bastion 의 IAM 역할에 클러스터 관리자 권한을 준다. SSM 으로 이 인스턴스에 들어올 수 있는 사람은
#   곧 클러스터 관리자다. 권한을 줄이려면 아래 aws_eks_access_policy_association 의 policy_arn 을 바꾼다.

variable "bastion_instance_type" {
  description = "Bastion 인스턴스 타입. arm AMI 를 쓰므로 Graviton(t4g 등)이어야 한다. 무료 플랜 허용 타입은 t4g.micro 부터다 (t4g.nano 는 불가)."
  type        = string
  default     = "t4g.micro"
}

# 최신 Amazon Linux 2023 arm64 AMI. AWS 가 SSM 파라미터로 항상 최신 ID 를 가리켜 준다.
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# ── IAM: EC2 가 SSM 에 등록되고, 클러스터 정보를 조회할 수 있는 최소 권한 ────────────────────
resource "aws_iam_role" "bastion" {
  name = "${var.project}-bastion"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# SSM Session Manager 로 접속되게 하는 AWS 관리형 정책
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# aws eks update-kubeconfig 가 클러스터 엔드포인트/CA 를 조회하는 데 필요. 이 클러스터 하나로 한정.
resource "aws_iam_role_policy" "bastion_eks_describe" {
  name = "eks-describe-cluster"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "eks:DescribeCluster"
      Resource = module.eks.cluster_arn
    }]
  })
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.project}-bastion"
  role = aws_iam_role.bastion.name
}

# ── 네트워크: 인바운드 없음, 아웃바운드는 443 만 ─────────────────────────────────────────────
resource "aws_security_group" "bastion" {
  name        = "${var.project}-bastion"
  description = "SSM bastion: no inbound, egress 443 only"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${var.project}-bastion"
  }
}

# SSM 서비스, EKS API, kubectl 다운로드 모두 443 이다.
resource "aws_vpc_security_group_egress_rule" "bastion_https" {
  security_group_id = aws_security_group.bastion.id
  description       = "HTTPS out (SSM, EKS API, downloads)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# EKS 컨트롤 플레인 보안그룹이 Bastion 의 443 접근을 허용해야 kubectl 이 닿는다.
resource "aws_vpc_security_group_ingress_rule" "cluster_from_bastion" {
  security_group_id            = module.eks.cluster_security_group_id
  description                  = "EKS API from SSM bastion"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.bastion.id
}

# ── 클러스터 권한: Bastion 역할을 클러스터 관리자로 등록 (Access Entry) ───────────────────────
resource "aws_eks_access_entry" "bastion" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.bastion.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "bastion_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.bastion.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.bastion]
}

# ── 인스턴스 ──────────────────────────────────────────────────────────────────────────────
resource "aws_instance" "bastion" {
  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = var.bastion_instance_type
  subnet_id              = local.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.bastion.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name

  # 공인 IP 없음. 키 페어도 지정하지 않는다 (SSM 으로만 접속).
  associate_public_ip_address = false

  # IMDSv2 강제 (SSRF 로 인스턴스 자격 증명이 새는 것을 막는다)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  # kubectl 을 클러스터 버전에 맞춰 설치한다. 체크섬 검증이 실패하면 설치하지 않는다.
  # 실패 시 로그: /var/log/cloud-init-output.log
  # 주의: bash 변수는 중괄호 없이($KVER) 써야 한다. Terraform 이 ${...} 를 먼저 해석하기 때문이다.
  user_data = <<-EOT
    #!/bin/bash
    set -euo pipefail
    KVER=$(curl -fsSL https://dl.k8s.io/release/stable-${var.kubernetes_version}.txt)
    cd /tmp
    curl -fsSLO "https://dl.k8s.io/release/$KVER/bin/linux/arm64/kubectl"
    curl -fsSLO "https://dl.k8s.io/release/$KVER/bin/linux/arm64/kubectl.sha256"
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
    install -m 0755 kubectl /usr/local/bin/kubectl
    echo 'export AWS_DEFAULT_REGION=${var.region}' > /etc/profile.d/aws-region.sh
  EOT

  user_data_replace_on_change = true

  # 최신 AMI 가 나올 때마다 plan 에서 인스턴스가 교체되는 것을 막는다. 갱신하려면 taint 하거나 이 줄을 잠시 빼면 된다.
  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name = "${var.project}-bastion"
  }

  # 클러스터와 Access Entry 가 만들어진 뒤에 뜬다.
  depends_on = [aws_eks_access_policy_association.bastion_admin]
}
