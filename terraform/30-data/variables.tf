variable "project" {
  type = string
}

variable "region" {
  type = string
}

variable "state_bucket" {
  type = string
}

variable "db_instance_class" {
  description = "무료 플랜에서 허용되는 종류(db.t4g.micro, db.t3.micro)"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "GB"
  type        = number
  default     = 20
}

variable "db_name" {
  type    = string
  default = "reservation"
}

variable "db_username" {
  type    = string
  default = "reservation"
}