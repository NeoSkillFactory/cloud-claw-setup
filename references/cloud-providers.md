# Cloud Provider Reference

## AWS (Amazon Web Services)

### Supported Instance Types
| Type | vCPUs | Memory | Use Case |
|------|-------|--------|----------|
| t3.medium | 2 | 4 GB | Development/Testing |
| m5.xlarge | 4 | 16 GB | Standard workloads |
| m5.2xlarge | 8 | 32 GB | Production AI agents |
| c5.4xlarge | 16 | 32 GB | Compute-intensive |
| r5.2xlarge | 8 | 64 GB | Memory-intensive |

### Key Services
- **EC2**: VM hosting
- **S3**: Object storage for agent data
- **IAM**: Access management
- **VPC**: Network isolation
- **CloudWatch**: Monitoring and logging

### CLI Setup
```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure credentials
aws configure
```

### Metadata Service (IMDSv2)
```bash
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type
```

## GCP (Google Cloud Platform)

### Supported Machine Types
| Type | vCPUs | Memory | Use Case |
|------|-------|--------|----------|
| e2-medium | 2 | 4 GB | Development/Testing |
| n2-standard-4 | 4 | 16 GB | Standard workloads |
| n2-standard-8 | 8 | 32 GB | Production AI agents |
| c2-standard-16 | 16 | 64 GB | Compute-intensive |
| n2-highmem-8 | 8 | 64 GB | Memory-intensive |

### Key Services
- **Compute Engine**: VM hosting
- **Cloud Storage (GCS)**: Object storage
- **IAM**: Access management
- **VPC**: Network isolation
- **Cloud Logging**: Monitoring and logging

### CLI Setup
```bash
# Install gcloud CLI
curl https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz -o gcloud.tar.gz
tar -xzf gcloud.tar.gz
./google-cloud-sdk/install.sh

# Authenticate
gcloud auth login
gcloud config set project PROJECT_ID
```

### Metadata Service
```bash
curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/machine-type
```

## Azure (Microsoft Azure)

### Supported VM Sizes
| Size | vCPUs | Memory | Use Case |
|------|-------|--------|----------|
| Standard_B2s | 2 | 4 GB | Development/Testing |
| Standard_D4s_v5 | 4 | 16 GB | Standard workloads |
| Standard_D8s_v5 | 8 | 32 GB | Production AI agents |
| Standard_F16s_v2 | 16 | 32 GB | Compute-intensive |
| Standard_E8s_v5 | 8 | 64 GB | Memory-intensive |

### Key Services
- **Virtual Machines**: VM hosting
- **Blob Storage**: Object storage
- **Azure AD/Entra ID**: Access management
- **VNet**: Network isolation
- **Azure Monitor**: Monitoring and logging

### CLI Setup
```bash
# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Authenticate
az login
az account set --subscription SUBSCRIPTION_ID
```

### Instance Metadata Service (IMDS)
```bash
curl -H "Metadata: true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01"
```

## Provider Detection Logic

The setup scripts detect the cloud provider automatically by querying metadata endpoints:

1. **AWS**: `http://169.254.169.254/latest/meta-data/` (responds without special headers)
2. **GCP**: `http://metadata.google.internal/computeMetadata/v1/` (requires `Metadata-Flavor: Google`)
3. **Azure**: `http://169.254.169.254/metadata/instance` (requires `Metadata: true`)

If none respond, the environment is treated as "generic" (on-premises or unknown cloud).
