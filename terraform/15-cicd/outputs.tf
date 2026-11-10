output "github_actions_role_arn" {
  description = "워크플로의 role-to-assume 에 넣을 값"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}