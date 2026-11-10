# VPC: 2 AZ, 퍼블릭 / 프라이빗 / DB 서브넷, NAT Gateway 1개.
#
# 서브넷 크기 (기본 10.73.0.0/20 = 4,096 IP 기준. 서브넷당 AWS 예약 5개 제외)
#   private  /23 x2  : 노드와 Pod. VPC CNI 는 Pod 마다 VPC IP 를 쓴다 (AZ당 507개)
#   public   /26 x2  : ALB, NAT 만 놓인다. ALB 는 스케일 아웃 때 서브넷 IP 를 더 쓰므로 /27 보다 여유 있게 (59개)
#   database /27 x2  : RDS 전용. 인터넷 경로 없음 (27개)
# 서브넷은 만든 뒤 크기를 바꿀 수 없다. 모자라면 VPC 에 보조 CIDR 을 붙여 서브넷을 추가한다.
# 40-eks 에서 service_ipv4_cidr 을 정할 때 이 VPC 와 겹치지 않게 할 것 (EKS 기본값은 10.100.0.0/16 또는 172.20.0.0/16)

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.project
  cidr = var.vpc_cidr
  azs  = var.azs

  private_subnets  = [for i in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 3, i)]      # 10.73.0.0/23, 10.73.2.0/23
  public_subnets   = [for i in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 6, 16 + i)] # 10.73.4.0/26, 10.73.4.64/26
  database_subnets = [for i in range(length(var.azs)) : cidrsubnet(var.vpc_cidr, 7, 36 + i)] # 10.73.4.128/27, 10.73.4.160/27

  # NAT Gateway 1개 (첫 번째 AZ). 그 AZ 장애 시 프라이빗 서브넷의 외부 통신이 끊기는 SPOF 를 감수한다.
  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  create_database_subnet_group           = true
  create_database_subnet_route_table     = true
  create_database_internet_gateway_route = false
  create_database_nat_gateway_route      = false

  # AWS Load Balancer Controller 가 ALB 를 놓을 서브넷을 찾는 태그
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# S3 Gateway 엔드포인트 (무료).
# ECR 이미지 레이어는 S3 에서 내려받으므로, 이게 없으면 이미지 pull 트래픽이 전부 NAT 데이터 처리 요금으로 나간다.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = {
    Name = "${var.project}-s3"
  }
}
