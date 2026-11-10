# 20-network 가 내보낸 값(vpc_id, 서브넷 ID)을 읽는다. 레이어끼리 이 방식으로 연결된다.
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "20-network/terraform.tfstate"
    region = var.region
  }
}
