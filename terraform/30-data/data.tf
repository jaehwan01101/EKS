data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "20-network/terraform.tfstate"
    region = var.region
  }
}