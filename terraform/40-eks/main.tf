# EKS 클러스터 + 관리형 노드 그룹 + 필수 add-on.
#
# 모듈: terraform-aws-modules/eks/aws (Terraform Registry, 커뮤니티 오픈소스)
#   terraform init 때 .terraform/modules/eks/ 로 내려받는다. 인자 이름은 그 안의 variables.tf 가 원본.
#   version 은 정확히 고정한다. (모듈 버전은 provider 와 달리 .terraform.lock.hcl 로 잠기지 않아서,
#   ~> 로 두면 새로 init 하는 환경에서 다른 버전이 설치될 수 있다.)
#
# 이 레이어가 만드는 것은 "클러스터와 노드"까지다. 아래는 다른 곳에서 한다.
#   - Bastion(SSM) : kubectl 접속 경로 (아직 없음, API 가 Private 이라 필요)
#   - AWS LB Controller, ExternalSecrets, Argo CD 등 : 50-platform

locals {
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = var.project
  kubernetes_version = var.kubernetes_version

  # ── 네트워크 ────────────────────────────────────────────────────────────────
  # subnet_ids 는 노드가 놓일 서브넷이고, control_plane_subnet_ids 를 따로 주지 않으면
  # 컨트롤 플레인 ENI 도 같은 서브넷에 놓인다. 둘 다 private /23 서브넷(2개 AZ).
  vpc_id     = local.vpc_id
  subnet_ids = local.private_subnet_ids

  # VPC(10.73.0.0/20) 와 겹치지 않는 Service 대역. 생성 후 바꿀 수 없다.
  service_ipv4_cidr = var.service_ipv4_cidr

  # ── API 서버 접근: Private only ─────────────────────────────────────────────
  # 모듈 기본값도 이 값이지만, 보안 결정이므로 명시해 둔다.
  # 내 PC 에서 kubectl 이 직접 닿지 않는다. SSM Bastion 을 거쳐야 한다.
  # (노드 조인, add-on, Access Entry 는 AWS API 로 처리되므로 PC 에서 apply 가능)
  endpoint_private_access = true
  endpoint_public_access  = false

  # ── 인증/권한 ───────────────────────────────────────────────────────────────
  # API: Access Entries 만 사용 (구형 aws-auth ConfigMap 은 쓰지 않는다).
  authentication_mode = "API"
  # 이 Terraform 을 실행한 IAM 주체(naranhi-admin)를 클러스터 관리자로 등록한다.
  # 모듈 기본값은 false 라서, 안 켜면 클러스터를 만들고도 접근할 수 없다.
  enable_cluster_creator_admin_permissions = true

  # Pod 에 AWS 권한을 주는 방식은 Pod Identity 로 간다 (아래 eks-pod-identity-agent).
  # IRSA 용 OIDC Provider 는 만들지 않는다. IRSA 만 지원하는 도구를 쓰게 되면 true 로 바꾼다.
  enable_irsa = false

  # ── 비용/지원 정책 ──────────────────────────────────────────────────────────
  # 표준 지원이 끝난 뒤 자동으로 Extended Support(시간당 요금 상승)로 넘어가지 않게 한다.
  upgrade_policy = {
    support_type = "STANDARD"
  }

  # ── 컨트롤 플레인 로그 / 암호화 ──────────────────────────────────────────────
  # 모듈 기본값은 audit, api, authenticator + 보관 90일. 최소한(audit, authenticator)만 남기고 7일 보관.
  enabled_log_types                      = ["audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 7

  # K8s Secret 의 envelope 암호화용 KMS 키를 모듈이 만든다(기본값 true, 키당 월 $1).
  # 삭제 대기 기간을 최소 7일로 줄인다. destroy/apply 를 반복해도 대기 중인 키가 오래 남지 않게.
  kms_key_deletion_window_in_days = 7

  # ── add-on ──────────────────────────────────────────────────────────────────
  # before_compute = true : 노드가 만들어지기 "전에" 먼저 설치/설정한다.
  #   vpc-cni 의 Prefix Delegation 은 노드가 뜨기 전에 켜져 있어야 노드가 최대 Pod 수를 크게 계산한다.
  addons = {
    eks-pod-identity-agent = {
      before_compute = true
    }

    vpc-cni = {
      before_compute = true
      configuration_values = jsonencode({
        env = {
          # IP 를 하나씩이 아니라 /28(16개) 묶음으로 노드에 할당 → 노드당 Pod 수 상한이 크게 늘어난다.
          ENABLE_PREFIX_DELEGATION = "true"
          # 미리 확보해 두는 여분 묶음 수. 1 이면 노드마다 /28 한 개를 대기시킨다.
          WARM_PREFIX_TARGET = "1"
        }
      })
    }

    kube-proxy = {}
    coredns    = {}
  }

  # ── 노드 그룹: Managed Node Group, x86(m7i-flex, 무료 플랜 허용 타입), On-Demand ─────────────────
  eks_managed_node_groups = {
    default = {
      ami_type       = var.node_ami_type
      instance_types = [var.node_instance_type]
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      # 노드 롤링 업데이트 때 한 번에 1대씩만 교체한다.
      update_config = {
        max_unavailable = 1
      }
    }
  }
}
