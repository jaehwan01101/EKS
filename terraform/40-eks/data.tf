# 20-network 가 내보낸 값(vpc_id, 서브넷 ID)을 읽는다. 레이어끼리 이 방식으로 연결된다.
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "20-network/terraform.tfstate"
    region = var.region
  }
}

# 30-data 가 내보낸 RDS 보안 그룹 ID 를 읽는다. 이 레이어가 노드 → RDS 허용 규칙을 붙인다(rds-access.tf).
# 그래서 apply 순서는 30-data → 40-eks 이다.
data "terraform_remote_state" "data" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "30-data/terraform.tfstate"
    region = var.region
  }
}
