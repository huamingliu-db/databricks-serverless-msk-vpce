# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Trust policy for Databricks Unity Catalog service credentials IAM role

data "aws_iam_policy_document" "trust_policy_for_msk_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      # https:#docs.databricks.com/en/data-governance/unity-catalog/manage-external-locations-and-credentials.html
      identifiers = ["arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL"]
      type        = "AWS"
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.databricks_external_id]
    }
  }
  statement {
    sid     = "ExplicitSelfRoleAssumption"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::${local.account_id}:role/${local.prefix}-databricks-msk-role"]
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.databricks_external_id]
    }
  }
}

# Unity Catalog service credentials IAM role
resource "aws_iam_role" "databricks_msk_access" {
  name               = "${local.prefix}-databricks-msk-role"
  assume_role_policy = data.aws_iam_policy_document.trust_policy_for_msk_role.json
  tags = merge(
    {
      Name = "Databricks MSK Access Role"
    },
    local.tags
  )
}

# Extract cluster name and UUID from cluster ARN for building resource ARNs
# Cluster ARN format: arn:aws:kafka:region:account:cluster/cluster-name/cluster-uuid
locals {
  cluster_arn_parts = split("/", aws_msk_cluster.poc.arn)
  cluster_name      = local.cluster_arn_parts[1]
  cluster_uuid      = local.cluster_arn_parts[2]

  # Build MSK resource ARN patterns
  topic_arn_pattern          = "arn:aws:kafka:${var.region}:${local.account_id}:topic/${local.cluster_name}/${local.cluster_uuid}/*"
  group_arn_pattern          = "arn:aws:kafka:${var.region}:${local.account_id}:group/${local.cluster_name}/${local.cluster_uuid}/*"
  transactional_id_arn_pattern = "arn:aws:kafka:${var.region}:${local.account_id}:transactional-id/${local.cluster_name}/${local.cluster_uuid}/*"
}

# IAM policy for MSK cluster access with IAM authentication
data "aws_iam_policy_document" "msk_access_policy" {
  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:Connect",
      "kafka-cluster:AlterCluster",
      "kafka-cluster:DescribeCluster",
      "kafka-cluster:WriteDataIdempotently"
    ]
    resources = [aws_msk_cluster.poc.arn]
  }
  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:*Topic*",
      "kafka-cluster:WriteData",
      "kafka-cluster:ReadData"
    ]
    resources = [
      local.topic_arn_pattern,
      local.transactional_id_arn_pattern
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:AlterGroup",
      "kafka-cluster:DescribeGroup"
    ]
    resources = [local.group_arn_pattern]
  }
  statement {
    effect = "Allow"
    actions = [
      "kafka-cluster:AlterTransactionalId",
      "kafka-cluster:DescribeTransactionalId"
    ]
    resources = [local.transactional_id_arn_pattern]
  }
}

# Attach the MSK access policy to the role
resource "aws_iam_role_policy" "msk_access" {
  role   = aws_iam_role.databricks_msk_access.id
  policy = data.aws_iam_policy_document.msk_access_policy.json
}

# Output the role ARN for use in Databricks Unity Catalog service credential creation
output "databricks_msk_role_arn" {
  description = "ARN of the IAM role for Databricks Unity Catalog MSK access"
  value       = aws_iam_role.databricks_msk_access.arn
}

output "databricks_msk_role_name" {
  description = "Name of the IAM role for Databricks Unity Catalog MSK access"
  value       = aws_iam_role.databricks_msk_access.name
}

# Trust policy for EC2 instances to access MSK
data "aws_iam_policy_document" "ec2_trust_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# EC2 IAM role for MSK access
resource "aws_iam_role" "ec2_msk_access" {
  name               = "${local.prefix}-ec2-msk-role"
  description        = "IAM role for EC2 instances to access MSK cluster with IAM authentication"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust_policy.json

  tags = merge(
    {
      Name = "EC2 MSK Access Role"
    },
    local.tags
  )
}

# Attach the MSK access policy to the EC2 role
resource "aws_iam_role_policy" "ec2_msk_access" {
  role   = aws_iam_role.ec2_msk_access.id
  policy = data.aws_iam_policy_document.msk_access_policy.json
}

# Create instance profile for EC2 instances
resource "aws_iam_instance_profile" "ec2_msk_access" {
  name = "${local.prefix}-ec2-msk-profile"
  role = aws_iam_role.ec2_msk_access.name

  tags = merge(
    {
      Name = "EC2 MSK Access Instance Profile"
    },
    local.tags
  )
}

# Output the EC2 role ARN and instance profile
output "ec2_msk_role_arn" {
  description = "ARN of the IAM role for EC2 MSK access"
  value       = aws_iam_role.ec2_msk_access.arn
}

output "ec2_msk_role_name" {
  description = "Name of the IAM role for EC2 MSK access"
  value       = aws_iam_role.ec2_msk_access.name
}

output "ec2_msk_instance_profile_name" {
  description = "Name of the instance profile for EC2 instances to access MSK"
  value       = aws_iam_instance_profile.ec2_msk_access.name
}
