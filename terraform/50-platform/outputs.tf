output "lb_controller_role_arn" {
  value = aws_iam_role.lb_controller.arn
}

output "external_secrets_role_arn" {
  value = aws_iam_role.external_secrets.arn
}

output "ebs_csi_role_arn" {
  value = aws_iam_role.ebs_csi.arn
}
