---
name: cloud-claw-setup
description: Automatically installs and configures OpenClaw on cloud VMs for AI agent deployment
version: 1.0.0
triggers:
  - "Set up OpenClaw on a new cloud VM"
  - "Install OpenClaw on AWS"
  - "Install OpenClaw on GCP"
  - "Install OpenClaw on Azure"
  - "Automate OpenClaw deployment"
  - "Configure a cloud server for AI agents"
  - "Bootstrap OpenClaw on a fresh VM"
  - "Deploy OpenClaw infrastructure"
  - "Set up OpenClaw development environment"
  - "Automate OpenClaw installation on cloud VM"
---

# Cloud Claw Setup

## Purpose

Automate OpenClaw deployment on cloud VMs with provider-specific optimizations.
Handles dependency installation, configuration, validation, and status reporting
for AWS, GCP, and Azure environments.

## Core Components

- **Dependency Manager** (`scripts/install.sh`): Detects OS/package manager and installs all required packages
- **Configurator** (`scripts/configure.sh`): Generates optimized OpenClaw configuration based on VM specs and cloud provider
- **Validator** (`scripts/validate.sh`): Runs health checks and reports installation status
- **Cloud Provider Scripts** (`scripts/cloud-*.sh`): Provider-specific setup for AWS, GCP, and Azure

## Input Format

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `--provider` | No | auto-detect | Cloud provider: `aws`, `gcp`, or `azure` |
| `--vm-type` | No | auto-detect | VM instance type for resource optimization |
| `--config` | No | `assets/config-template.yaml` | Path to custom config template |
| `--dry-run` | No | false | Show what would be done without making changes |

## Output Types

- Installation status report (stdout)
- Generated configuration file (`/etc/openclaw/config.yaml`)
- Deployment script for reproducibility (`/tmp/openclaw-deployment.sh`)
- Error recovery suggestions on failure

## Usage

```bash
# Auto-detect provider and install
./scripts/install.sh

# Specify provider explicitly
./scripts/install.sh --provider aws

# Configure with custom template
./scripts/configure.sh --config my-config.yaml

# Validate installation
./scripts/validate.sh

# Full setup with specific provider
./scripts/install.sh --provider gcp && ./scripts/configure.sh --provider gcp && ./scripts/validate.sh
```

## Key Interactions

1. Script execution pipeline: install → configure → validate
2. Reference material lookup for provider-specific details
3. Validation feedback loops for error recovery
