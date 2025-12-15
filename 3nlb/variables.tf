variable "region" {
  type        = string
  description = "Region of all your AWS resources"
}

variable "cidr_block" {
  type        = string
  description = "Databricks Workspace VPC CIDR"
}

variable "prefix" {
  type        = string
  description = "Prefix of related AWS resources for MSK endpoint service"
}

variable "user_name" {
  type        = string
  description = "your firstname.lastname"
}

variable "service_name" {
  type        = string
  description = "Databricks service name"
}

variable "allowed_principals" {
  type        = list(string)
  description = "List of IAM principals that are allowed to create VPC endpoint against the endpoint service"
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI profile name"
}

variable "databricks_external_id" {
  type        = string
  description = "External ID for Databricks Unity Catalog service credential trust policy (use '0000' initially, then update with actual external ID from Databricks)"
  default     = "0000"
}