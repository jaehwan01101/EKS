output "state_bucket" {
  description = "backend.hcl 의 bucket, common.tfvars 의 state_bucket 에 넣을 값"
  value       = aws_s3_bucket.tfstate.bucket
}
