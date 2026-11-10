output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_version" {
  value = module.eks.cluster_version
}

output "cluster_endpoint" {
  description = "Private 엔드포인트. VPC 안에서만 접근 가능하다."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  value = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  value = module.eks.node_security_group_id
}

output "node_iam_role_arn" {
  value = module.eks.node_iam_role_arn
}

output "bastion_instance_id" {
  value = aws_instance.bastion.id
}

output "bastion_ssm_command" {
  description = "Bastion 접속 명령 (PC 에 Session Manager 플러그인 필요)"
  value       = "aws ssm start-session --target ${aws_instance.bastion.id} --region ${var.region} --profile eks"
}
