# 노드(= 그 위의 Pod) → RDS PostgreSQL 5432 허용.
#
# 왜 노드 보안 그룹을 출발지로 지정하나
#   VPC CNI 에서 Pod 는 노드의 ENI 에서 받은 VPC IP 를 쓰고, 보안 그룹은 노드 것이 그대로 적용된다.
#   그래서 "노드 보안 그룹에서 오는 5432" 만 열면, IP 대역을 열어 두는 것보다 범위가 좁다.
#   (점프 호스트 등 같은 서브넷의 다른 인스턴스는 이 규칙에 해당하지 않는다.)
#
# 왜 이 레이어에 있나
#   RDS 보안 그룹은 30-data 가 만들지만, 출발지인 노드 보안 그룹은 이 레이어가 안다.
#   30-data 가 40-eks 를 참조하면 레이어가 순환하므로, 규칙은 두 값을 모두 아는 쪽에서 붙인다.
resource "aws_vpc_security_group_ingress_rule" "rds_from_nodes" {
  security_group_id            = data.terraform_remote_state.data.outputs.db_security_group_id
  referenced_security_group_id = module.eks.node_security_group_id

  ip_protocol = "tcp"
  from_port   = 5432
  to_port     = 5432
  description = "EKS nodes (pods) to RDS PostgreSQL"
}
