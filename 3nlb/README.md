# Amazon MSK with VPC Endpoint Service for Databricks Serverless - Multiple NLBs Pattern

This Terraform project provisions AWS infrastructure for secure, private connectivity between Databricks Serverless and Amazon MSK (Managed Streaming for Apache Kafka) using IAM authentication and VPC endpoints.

## Architecture Overview

The solution creates a private connectivity architecture with the following components:

- **Amazon MSK Cluster**: 3-broker cluster with IAM authentication enabled on port 9098
- **Network Load Balancers**: 3 dedicated NLBs (one per MSK broker) for traffic distribution
- **VPC Endpoint Services**: 3 endpoint services exposing each broker through AWS PrivateLink
- **IAM Role**: Configured for Databricks Unity Catalog service credentials with MSK access permissions
- **Private VPC**: Fully isolated network with no internet or NAT gateway

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  Databricks Workspace VPC                                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  VPC Endpoints (3)                                   │   │
│  │  - Connect to VPC Endpoint Services                  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                         │
                         │ AWS PrivateLink
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  MSK Infrastructure VPC                                     │
│                                                             │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐│
│  │ VPC Endpoint   │  │ VPC Endpoint   │  │ VPC Endpoint   ││
│  │ Service 1      │  │ Service 2      │  │ Service 3      ││
│  └────────┬───────┘  └────────┬───────┘  └────────┬───────┘│
│           │                   │                   │         │
│  ┌────────▼───────┐  ┌────────▼───────┐  ┌────────▼───────┐│
│  │ NLB 1          │  │ NLB 2          │  │ NLB 3          ││
│  │ (AZ 1)         │  │ (AZ 2)         │  │ (AZ 3)         ││
│  └────────┬───────┘  └────────┬───────┘  └────────┬───────┘│
│           │                   │                   │         │
│  ┌────────▼───────┐  ┌────────▼───────┐  ┌────────▼───────┐│
│  │ MSK Broker 1   │  │ MSK Broker 2   │  │ MSK Broker 3   ││
│  │ (AZ 1)         │  │ (AZ 2)         │  │ (AZ 3)         ││
│  └────────────────┘  └────────────────┘  └────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Key Features

- **IAM Authentication**: Secure access using AWS IAM credentials (no username/password)
- **Private Connectivity**: All communication over AWS PrivateLink (no public internet exposure)
- **High Availability**: 3 brokers across multiple availability zones
- **Broker Affinity**: Each NLB routes to a specific broker (no cross-zone load balancing)
- **Unity Catalog Integration**: IAM role configured for Databricks Unity Catalog service credentials

## Prerequisites

- **Terraform**: >= 1.0
- **AWS CLI**: Configured with appropriate credentials
- **AWS Permissions**: Ability to create VPC, MSK, NLB, VPC Endpoint Services, and IAM resources
- **Databricks Workspace**: For consuming the MSK cluster (optional, but recommended)

## Configuration

### Required Variables

Create a `terraform.tfvars` or `*.auto.tfvars` file with the following variables:

```hcl
region                  = "us-east-1"
cidr_block             = "172.18.0.0/16"
prefix                 = "my-msk-vpce"
user_name              = "your.name@company.com"
service_name           = "MSK Endpoint Service"
allowed_principals     = ["arn:aws:iam::123456789012:role/databricks-role"]
aws_profile            = "your-aws-profile"
databricks_external_id = "0000"  # Update after creating Databricks service credential
```

### Variable Descriptions

| Variable | Description | Example |
|----------|-------------|---------|
| `region` | AWS region for all resources | `us-east-1` |
| `cidr_block` | CIDR block for the VPC | `172.18.0.0/16` |
| `prefix` | Prefix for resource names | `my-msk-vpce` |
| `user_name` | Owner tag value | `user@example.com` |
| `service_name` | Service tag value | `MSK Endpoint Service` |
| `allowed_principals` | List of IAM principals allowed to create VPC endpoints | `["arn:aws:iam::123456789012:role/role-name"]` |
| `aws_profile` | AWS CLI profile name | `default` |
| `databricks_external_id` | External ID for Databricks role assumption | `0000` (initially) |

## Deployment

### Step 1: Initialize Terraform

```bash
terraform init
```

### Step 2: Review the Plan

```bash
terraform plan
```

### Step 3: Apply Configuration

```bash
terraform apply
```

This will create approximately 30+ AWS resources including VPC, subnets, security groups, MSK cluster, NLBs, target groups, VPC endpoint services, and IAM role.

### Step 4: Configure Databricks (if applicable)

After deployment, use the outputs to configure Databricks:

1. **Create Unity Catalog Service Credential** in Databricks using the IAM role ARN from the output
2. **Note the External ID** generated by Databricks
3. **Update** the `databricks_external_id` variable in your tfvars file
4. **Re-apply** the Terraform configuration: `terraform apply`

### Step 5: Create VPC Endpoints in Databricks Workspace VPC

Accept the VPC endpoint service connection requests and create corresponding VPC endpoints in your Databricks workspace VPC pointing to the 3 endpoint services.

## Outputs

The Terraform configuration provides the following outputs:

- `databricks_msk_role_arn`: IAM role ARN for Databricks Unity Catalog
- `databricks_msk_role_name`: IAM role name

Additional information can be retrieved from AWS Console:
- MSK cluster ARN and bootstrap servers
- VPC endpoint service names (for creating VPC endpoints)
- NLB DNS names

## Important Notes

### MSK Configuration

- **Kafka Version**: 3.9.x
- **Instance Type**: kafka.m5.large
- **Storage**: 1000 GB EBS per broker
- **Replication Factor**: 3
- **Authentication**: IAM only (port 9098)
- **Encryption**: TLS in transit, encryption at rest

### Security Considerations

- The MSK cluster is in a **private VPC** with no internet access
- Security groups restrict traffic to port 9098 from NLB security group only
- IAM authentication provides fine-grained access control
- External ID in IAM trust policy prevents confused deputy attacks

### Cost Considerations

This infrastructure includes:
- 3 MSK brokers (m5.large instances) running 24/7
- 3 Network Load Balancers
- 3 VPC endpoint services
- 3000 GB of EBS storage
- CloudWatch log storage

Ensure you understand the [AWS MSK pricing](https://aws.amazon.com/msk/pricing/) and [AWS PrivateLink pricing](https://aws.amazon.com/privatelink/pricing/) before deployment.

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete the MSK cluster and all its data. Ensure you have backups if needed.

## Troubleshooting

### MSK Cluster Creation Takes Long
MSK cluster provisioning typically takes 15-30 minutes. Be patient during `terraform apply`.

### VPC Endpoint Connection Not Working
- Verify that the allowed principals in `allowed_principals` match the IAM role used by Databricks
- Check that VPC endpoint connection requests are accepted in AWS Console
- Ensure security groups allow traffic on port 9098

### IAM Authentication Failures
- Verify the external ID in the IAM role matches the one in Databricks
- Ensure the IAM role has the correct permissions for MSK operations
- Check that the Databricks service credential is correctly configured

## License

This project is provided as-is for educational and reference purposes.

## Contributing

Contributions, issues, and feature requests are welcome. Feel free to check the issues page if you want to contribute.
