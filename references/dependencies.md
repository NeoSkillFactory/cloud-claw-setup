# Dependencies Reference

## System Dependencies

### Required Packages
| Package | Min Version | Purpose |
|---------|-------------|---------|
| bash | 4.0+ | Script execution |
| curl | 7.0+ | HTTP requests, downloads |
| wget | 1.0+ | File downloads (fallback) |
| git | 2.0+ | Version control |
| openssl | 1.1+ | TLS/SSL support |
| ca-certificates | - | SSL certificate verification |
| gnupg | 2.0+ | Package signature verification |
| unzip | 6.0+ | Archive extraction |
| jq | 1.5+ | JSON processing (optional but recommended) |
| lsb-release | - | OS version detection |

### Package Manager Support
| Manager | OS Family | Command |
|---------|-----------|---------|
| apt-get | Debian, Ubuntu | `apt-get install -y` |
| dnf | Fedora, RHEL 8+ | `dnf install -y` |
| yum | CentOS, RHEL 7 | `yum install -y` |
| apk | Alpine | `apk add` |

## Runtime Dependencies

### Node.js
- **Minimum version**: 18.x LTS
- **Recommended**: 20.x LTS or newer
- **Install via**: NodeSource repository or nvm
- **Used for**: OpenClaw runtime, npm package management

### Python
- **Minimum version**: 3.9
- **Recommended**: 3.11+
- **Required packages**: python3, python3-pip, python3-venv
- **Used for**: Utility scripts, YAML validation, tooling

## Cloud Provider CLIs

### AWS CLI
- **Version**: v2
- **Install**: Download from `https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip`
- **Required for**: AWS provider-specific features (S3, IAM, metadata)

### Google Cloud CLI (gcloud)
- **Version**: Latest
- **Install**: Download from `https://dl.google.com/dl/cloudsdk/`
- **Required for**: GCP provider-specific features (GCS, IAM, metadata)

### Azure CLI
- **Version**: Latest
- **Install**: `curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash`
- **Required for**: Azure provider-specific features (Blob, AD, metadata)

## OpenClaw Components

### Core
- **openclaw**: Main framework package
- **Install**: `npm install -g openclaw` or `pip3 install openclaw`

### Directory Structure
| Path | Purpose |
|------|---------|
| /etc/openclaw/ | Configuration files |
| /var/lib/openclaw/data/ | Persistent data |
| /var/lib/openclaw/cache/ | Cache storage |
| /var/log/openclaw/ | Log files |
| /opt/openclaw/ | Optional installation directory |

## System Requirements

### Minimum
- **CPU**: 2 cores
- **RAM**: 4 GB
- **Disk**: 10 GB free
- **OS**: Linux (Debian/Ubuntu, RHEL/CentOS, Fedora)

### Recommended
- **CPU**: 4+ cores
- **RAM**: 16 GB+
- **Disk**: 50 GB+ SSD
- **OS**: Ubuntu 22.04 LTS or Amazon Linux 2023
