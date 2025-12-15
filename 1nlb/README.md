# Amazon MSK with VPC Endpoint Service (PrivateLink)

This Terraform project deploys an Amazon MSK (Managed Streaming for Apache Kafka) cluster with VPC Endpoint Service access, enabling private connectivity to MSK from external VPCs using AWS PrivateLink.

## Features

- **Private MSK Cluster**: 3-node Kafka cluster (v3.9.x) in a private VPC without internet access
- **AWS PrivateLink Integration**: VPC Endpoint Service for secure cross-VPC connectivity
- **IAM Authentication**: SASL/IAM authentication for Kafka clients
- **High Availability**: Cross-zone load balancing with NLB across multiple AZs
- **TLS Encryption**: End-to-end encryption for client-broker and inter-broker communication
- **Pre-configured IAM Roles**: Ready-to-use roles for Databricks Unity Catalog and AWS instance profile
- **CloudWatch Monitoring**: Built-in logging for MSK cluster operations

## Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────────┐
│                        Consumer VPC                              │
│                                                                   │
│   ┌─────────────────────┐                                       │
│   │  VPC Endpoint       │                                       │
│   │  (Interface)        │                                       │
│   └──────────┬──────────┘                                       │
└──────────────┼──────────────────────────────────────────────────┘
               │
               │  AWS PrivateLink
               │
┌──────────────┼──────────────────────────────────────────────────┐
│              │            MSK VPC                                │
│              │                                                   │
│   ┌──────────▼──────────┐                                       │
│   │  VPC Endpoint       │                                       │
│   │  Service            │                                       │
│   └──────────┬──────────┘                                       │
│              │                                                   │
│   ┌──────────▼──────────┐                                       │
│   │  Network Load       │  Ports: 8443-8445 (per broker)       │
│   │  Balancer (NLB)     │         9098 (shared/IAM)            │
│   └──────────┬──────────┘                                       │
│              │                                                   │
│   ┌──────────▼──────────┐                                       │
│   │  MSK Cluster        │                                       │
│   │  ┌───┐ ┌───┐ ┌───┐ │  3 brokers across 3 AZs              │
│   │  │B1 │ │B2 │ │B3 │ │  kafka.m5.large                      │
│   │  └───┘ └───┘ └───┘ │  1000 GB EBS each                    │
│   └─────────────────────┘                                       │
└─────────────────────────────────────────────────────────────────┘
```

### Traffic Flow

1. Client applications in consumer VPCs connect to the VPC Endpoint
2. Traffic is routed through AWS PrivateLink to the VPC Endpoint Service
3. The Network Load Balancer distributes traffic to MSK broker ENIs
4. MSK cluster authenticates clients using IAM credentials
5. Kafka operations are performed over TLS-encrypted connections

### Key Design Decisions

- **Private VPC**: No Internet Gateway or NAT Gateway for enhanced security
- **IAM Authentication**: SASL/IAM on port 9098 for secure access control
- **NLB Configuration**: `enforce_security_group_inbound_rules_on_private_link_traffic = "off"` to allow PrivateLink traffic
- **Target Groups**: 3 individual target groups (one per broker) + 1 shared target group for all brokers
- **Cross-Zone Load Balancing**: Enabled for high availability

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- AWS Account with appropriate permissions
- AWS CLI configured with credentials
- Basic understanding of AWS MSK, VPC, and PrivateLink

## Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd cis-msk-iam-vpce
```

### 2. Configure Variables

Create or update `myvars.auto.tfvars`:

```hcl
region               = "us-west-2"
cidr_block          = "10.0.0.0/16"
prefix              = "my-msk"
user_name           = "your-name"
service_name        = "kafka-service"
aws_profile         = "default"
allowed_principals  = [
  "arn:aws:iam::123456789012:root"  # Replace with your AWS account/principal ARNs
]
databricks_external_id = "0000"  # Will be updated after Databricks setup
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Review the Plan

```bash
terraform plan
```

### 5. Deploy Infrastructure

```bash
terraform apply
```

## Configuration

### Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `region` | AWS region for deployment | - | Yes |
| `cidr_block` | VPC CIDR block | - | Yes |
| `prefix` | Resource name prefix | - | Yes |
| `user_name` | Owner tag value | - | Yes |
| `service_name` | Service tag value | - | Yes |
| `aws_profile` | AWS CLI profile for authentication | - | Yes |
| `allowed_principals` | List of IAM principal ARNs allowed to create VPC endpoints | - | Yes |
| `databricks_external_id` | External ID for Unity Catalog service credential | `"0000"` | No |

### MSK Configuration

The MSK cluster is configured with the following settings:

**Broker Configuration:**
- Instance type: `kafka.m5.large`
- EBS storage: 1000 GB per broker
- Kafka version: 3.9.x
- Number of brokers: 3 (one per AZ)

**Server Properties:**
- Auto topic creation: Enabled
- Topic deletion: Enabled
- Default replication factor: 3
- Min in-sync replicas: 2
- Default partitions: 32
- Log retention: 24 hours
- Rack awareness: Enabled

**Security:**
- Encryption in transit (TLS): Enabled
- Client authentication: IAM only
- Encryption at rest: AWS managed

## IAM Roles Setup

This project creates two IAM roles for MSK access:

### 1. Databricks Unity Catalog Role

**Purpose**: Allows Databricks Unity Catalog to connect to MSK using IAM authentication.

**Setup Process:**

1. Deploy infrastructure (external_id defaults to "0000"):
   ```bash
   terraform apply
   ```

2. Note the output `databricks_msk_role_arn`

3. In Databricks, create a Unity Catalog service credential using the ARN

4. Copy the external ID from the created service credential in Databricks

5. Update `databricks_external_id` in `myvars.auto.tfvars`:
   ```hcl
   databricks_external_id = "actual-external-id-from-databricks"
   ```

6. Apply changes to update the trust policy:
   ```bash
   terraform apply
   ```

**Permissions Granted:**
- Cluster-level: Connect, AlterCluster, DescribeCluster, WriteDataIdempotently
- Topic-level: All topic operations, ReadData, WriteData
- Consumer group: AlterGroup, DescribeGroup
- Transactional ID: AlterTransactionalId, DescribeTransactionalId

### 2. EC2 Instance Role

**Purpose**: Allows EC2 instances to connect to MSK using IAM authentication.

**Usage:**
- Attach the instance profile to your EC2 instances
- Use the instance profile name from output: `ec2_msk_instance_profile_name`
- Configure Kafka client with IAM authentication

**Permissions Granted:**
- Same MSK permissions as the Databricks role

## Outputs

After deployment, Terraform provides the following outputs:

### MSK Cluster Outputs
- `msk_cluster_arn`: ARN of the MSK cluster
- `msk_bootstrap_brokers_iam`: Bootstrap broker endpoints for IAM authentication
- `msk_zookeeper_connect_string`: ZooKeeper connection string

### VPC Endpoint Service Outputs
- `vpc_endpoint_service_name`: Service name for creating VPC endpoints
- `vpc_endpoint_service_id`: VPC Endpoint Service ID

### IAM Role Outputs (Databricks)
- `databricks_msk_role_arn`: ARN to use when creating Unity Catalog service credential
- `databricks_msk_role_name`: IAM role name for reference

### IAM Role Outputs (EC2)
- `ec2_msk_role_arn`: ARN of the EC2 IAM role
- `ec2_msk_role_name`: Name of the EC2 IAM role
- `ec2_msk_instance_profile_name`: Instance profile name to attach to EC2 instances

### Network Outputs
- `vpc_id`: VPC ID
- `private_subnet_ids`: List of private subnet IDs
- `nlb_dns_name`: DNS name of the Network Load Balancer

## File Structure

```
.
├── README.md                 # This file
├── vpce.tf                  # Main infrastructure (VPC, MSK, NLB, VPC Endpoint Service)
├── iam.tf                   # IAM roles and policies
├── variables.tf             # Input variable declarations
├── providers.tf             # AWS provider configuration
├── versions.tf              # Terraform version constraints
└── myvars.auto.tfvars       # Variable values (auto-loaded, not tracked in git)
```

## Connecting to MSK

### From Consumer VPC

1. Create a VPC Endpoint in your consumer VPC:
   ```bash
   aws ec2 create-vpc-endpoint \
     --vpc-id vpc-xxxxx \
     --service-name <vpc_endpoint_service_name> \
     --subnet-ids subnet-xxxxx subnet-yyyyy \
     --security-group-ids sg-xxxxx
   ```

2. Configure Kafka client with IAM authentication:
   ```properties
   security.protocol=SASL_SSL
   sasl.mechanism=AWS_MSK_IAM
   sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
   sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler
   ```

3. Use the bootstrap brokers endpoint from Terraform outputs

### Required Dependencies

For Java/Scala clients:
```xml
<dependency>
    <groupId>software.amazon.msk</groupId>
    <artifactId>aws-msk-iam-auth</artifactId>
    <version>1.1.5</version>
</dependency>
```

For Python clients:
```bash
pip install aws-msk-iam-sasl-signer-python
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete the MSK cluster and all associated data. Ensure you have backups if needed.

## Security Considerations

- MSK cluster is deployed in a private VPC with no internet access
- All communication is encrypted using TLS
- IAM authentication provides fine-grained access control
- VPC Endpoint Service limits access to specified AWS principals
- Security groups restrict traffic to necessary ports only
- CloudWatch logs provide audit trail for monitoring

## Troubleshooting

### Common Issues

**Issue**: VPC Endpoint connection fails
- Verify the principal ARN is in `allowed_principals` list
- Check security groups allow traffic on required ports
- Ensure VPC Endpoint is in the same region as the service

**Issue**: IAM authentication fails
- Verify the IAM role/user has necessary MSK permissions
- Check the trust policy allows your principal to assume the role
- For Databricks: Ensure external ID is correctly configured

**Issue**: Cannot connect to brokers
- Verify NLB target groups are healthy
- Check MSK security group allows traffic from NLB security group
- Ensure route tables are properly configured

## License

This project is provided as-is for reference and learning purposes.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Acknowledgments

- Uses the [terraform-aws-vpc](https://github.com/terraform-aws-modules/terraform-aws-vpc) module for VPC creation
- Inspired by AWS best practices for MSK deployment
