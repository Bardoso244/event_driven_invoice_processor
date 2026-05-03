variable "project_prefix" {
  type = string
  description = "Prefix for all resource names"
  default = "bart-dev"
}

variable "bucket_name" {
  type = string
}

variable "email_address" {
  type = string
}

variable "table_name" {
  type = string
}

variable "sqs_queue" {
  type = string
}

variable "dlq" {
  type = string
}

variable "dlq_alarm" {
  type = string
}

variable "sns_topic" {
  type = string
}