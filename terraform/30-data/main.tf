# 예약 서비스 DB: RDS PostgreSQL 단일 AZ, DB 서브넷(인터넷 경로 없음).
#
# 비밀번호 처리: ephemeral + write-only 속성
#   일반적인 random_password / password 인자는 값이 Terraform 상태 파일에 평문으로 남는다.
#   ephemeral 리소스와 *_wo 인자는 값을 AWS 로 보내기만 하고 상태 파일에 저장하지 않는다.
#   교체하려면 *_wo_version 을 올린다 (그러면 새 비밀번호가 생성되어 RDS 와 SSM 에 다시 쓰인다).

locals {
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id
}

ephemeral "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+" # JDBC URL, 셸에서 문제 되는 문자(@ : / ? ' ") 제외
}

# RDS 보안 그룹. 허용 규칙은 여기서 만들지 않는다.
# "누가 접속하나(EKS 노드 보안 그룹)" 는 40-eks 가 알고 있으므로, 그 레이어가 5432 허용 규칙을 붙인다.
# (30-data 가 40-eks 를 참조하면 레이어가 순환한다)
resource "aws_security_group" "db" {
  name        = "${var.project}-db"
  description = "RDS PostgreSQL. Ingress rules are added by 40-eks"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${var.project}-db"
  }
}

resource "aws_db_instance" "this" {
  identifier = var.project

  engine         = "postgres"
  engine_version = "18" # 메이저만 지정하면 AWS 가 최신 마이너를 고른다 (auto_minor_version_upgrade 와 함께)
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username

  password_wo         = ephemeral.random_password.db.result
  password_wo_version = 1

  db_subnet_group_name   = data.terraform_remote_state.network.outputs.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false # 단일 AZ: 비용 때문에 AZ 장애 시 중단을 감수한다

  backup_retention_period    = 1
  auto_minor_version_upgrade = true
  apply_immediately          = true

  # 포트폴리오 환경: destroy 로 정리할 수 있어야 한다. 운영이라면 둘 다 반대로 둔다.
  deletion_protection = false
  skip_final_snapshot = true
}

# ── 앱이 읽을 값: External Secrets 가 SSM 에서 가져간다 ─────────────────────────────
# 이름 규칙: /reservation/<영역>/<이름>  (ESO 의 IAM 정책이 parameter/reservation/* 를 허용)
resource "aws_ssm_parameter" "db_url" {
  name  = "/${var.project}/db/url"
  type  = "String"
  value = "jdbc:postgresql://${aws_db_instance.this.address}:${aws_db_instance.this.port}/${var.db_name}?sslmode=require"
}

resource "aws_ssm_parameter" "db_username" {
  name  = "/${var.project}/db/username"
  type  = "String"
  value = var.db_username
}

resource "aws_ssm_parameter" "db_password" {
  name             = "/${var.project}/db/password"
  type             = "SecureString"
  value_wo         = ephemeral.random_password.db.result
  value_wo_version = 1
}