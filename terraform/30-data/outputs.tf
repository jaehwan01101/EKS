output "db_security_group_id" {
  description = "40-eks 가 노드 → RDS 5432 허용 규칙을 붙일 대상"
  value       = aws_security_group.db.id
}

output "db_endpoint" {
  value = aws_db_instance.this.address
}

output "db_parameter_names" {
  value = {
    url      = aws_ssm_parameter.db_url.name
    username = aws_ssm_parameter.db_username.name
    password = aws_ssm_parameter.db_password.name
  }
}