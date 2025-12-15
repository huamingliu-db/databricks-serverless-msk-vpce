# Define locals to configure deployment
locals {
  vpc_cidr = var.cidr_block
  prefix   = var.prefix
  account_id = data.aws_caller_identity.current.account_id
  tags = {
    Service = "${var.service_name}"
    Owner   = "${var.user_name}"
  }

}

# Create networking VPC resources

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"

  name = "${local.prefix}-vpc"
  cidr = local.vpc_cidr
  azs  = data.aws_availability_zones.available.names
  tags = local.tags

  enable_dns_hostnames = true

  enable_nat_gateway = false

  create_igw = false

  private_subnets = [cidrsubnet(local.vpc_cidr, 8, 1),
    cidrsubnet(local.vpc_cidr, 8, 2),
    cidrsubnet(local.vpc_cidr, 8, 3)
  ]
}

# Create security group for the MSK cluster
resource "aws_security_group" "msk_sg" {
  name        = "${local.prefix}-msk-sg"
  description = "Security group for the MSK cluster"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow 9098 NLB ingress"
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"

    security_groups = [aws_security_group.nlb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    {
      Name = "MSK Cluster Security Group"
    },
    local.tags
  )
}

resource "aws_cloudwatch_log_group" "poc" {
  name = "msk_broker_logs"
}

resource "aws_msk_configuration" "poc" {
  kafka_versions = ["3.9.x"]
  name           = "${local.prefix}-msk-config"

  server_properties = <<PROPERTIES
auto.create.topics.enable = true
delete.topic.enable = true
default.replication.factor = 3
log.retention.hours = 24
min.insync.replicas = 2
num.partitions = 32
replica.selector.class = org.apache.kafka.common.replica.RackAwareReplicaSelector
PROPERTIES
}

# Create MSK cluster

resource "aws_msk_cluster" "poc" {
  cluster_name           = "${local.prefix}-msk-cluster"
  kafka_version          = "3.9.x"
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type = "kafka.m5.large"
    client_subnets = module.vpc.private_subnets
    storage_info {
      ebs_storage_info {
        volume_size = 1000
      }
    }
    security_groups = [aws_security_group.msk_sg.id]
  }

  configuration_info {
    arn      = aws_msk_configuration.poc.arn
    revision = aws_msk_configuration.poc.latest_revision
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.poc.name
      }
    }
  }

  client_authentication {
    sasl {
      iam = true
    }
  }

  tags = merge(
    {
      Name = "MSK Cluster"
    },
    local.tags
  )
}


# Create security group for NLB
resource "aws_security_group" "nlb_sg" {
  name   = "${local.prefix}-nlb-sg"
  vpc_id = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    {
      Name = "NLB Security Group"
    },
    local.tags
  )
}


# Create NLB
resource "aws_lb" "nlb" {
  name               = "${local.prefix}-nlb"
  internal           = true
  load_balancer_type = "network"
  security_groups    = [aws_security_group.nlb_sg.id]
  subnets            = module.vpc.private_subnets

  enable_deletion_protection = false

  enable_cross_zone_load_balancing = true

  enforce_security_group_inbound_rules_on_private_link_traffic = "off"

  tags = merge(
    {
      Name = "${local.prefix}-NLB"
    },
    local.tags
  )
}


# Create target groups for each MSK broker
resource "aws_lb_target_group" "msk_broker_tgs" {
  count    = aws_msk_cluster.poc.number_of_broker_nodes
  name     = "${local.prefix}-broker${count.index}-tg"
  port     = 9098
  protocol = "TCP"
  target_type = "ip"
  vpc_id   = module.vpc.vpc_id

  tags = merge(
    {
      Name = "${local.prefix}-broker${count.index}-target-group"
    },
    local.tags
  )
}

# Create a target group for all MSK brokers
resource "aws_lb_target_group" "msk_all_brokers_tg" {
  name     = "${local.prefix}-all-brokers-tg"
  port     = 9098
  protocol = "TCP"
  target_type = "ip"
  vpc_id   = module.vpc.vpc_id

  tags = merge(
    {
      Name = "${local.prefix}-all-brokers-target-group"
    },
    local.tags
  )
}

# Create NLB listeners for each target group
resource "aws_lb_listener" "msk_listeners" {
  count = aws_msk_cluster.poc.number_of_broker_nodes

  load_balancer_arn = aws_lb.nlb.arn
  port              = 8443 + count.index
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.msk_broker_tgs[count.index].arn
  }

  tags = merge(
    {
      Name = "${local.prefix}-broker${count.index}-listener"
    },
    local.tags
  )
}

# Create an NLB listener for all brokers
resource "aws_lb_listener" "msk_all_brokers_listener" {

  load_balancer_arn = aws_lb.nlb.arn
  port              = 9098
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.msk_all_brokers_tg.arn
  }

  tags = merge(
    {
      Name = "${local.prefix}-all-brokers-listener"
    },
    local.tags
  )
}

data "aws_msk_broker_nodes" "broker_nodes" {
  cluster_arn = aws_msk_cluster.poc.arn
}

# Register MSK broker ENIs as targets
resource "aws_lb_target_group_attachment" "msk_broker_attachments" {
  count = aws_msk_cluster.poc.number_of_broker_nodes

  target_group_arn = aws_lb_target_group.msk_broker_tgs[count.index].arn
  target_id        = data.aws_msk_broker_nodes.broker_nodes.node_info_list[count.index].client_vpc_ip_address
  port             = 9098
}

# Register all MSK broker ENIs to the all brokers target group
resource "aws_lb_target_group_attachment" "msk_all_brokers_attachment" {
  count = aws_msk_cluster.poc.number_of_broker_nodes

  target_group_arn = aws_lb_target_group.msk_all_brokers_tg.arn
  target_id        = data.aws_msk_broker_nodes.broker_nodes.node_info_list[count.index].client_vpc_ip_address
  port             = 9098
}

# Create endpoint service
resource "aws_vpc_endpoint_service" "msk" {
  acceptance_required        = true
  network_load_balancer_arns = [aws_lb.nlb.arn]
  allowed_principals         = var.allowed_principals

  tags = merge(
    {
      Name = "${local.prefix}-endpoint-service"
    },
    local.tags
  )
}