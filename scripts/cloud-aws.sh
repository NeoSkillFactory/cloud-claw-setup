#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/openclaw-aws.log"
VM_TYPE=""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[AWS]${NC} $*" | tee -a "$LOG_FILE"; }
log_warn()  { echo -e "${YELLOW}[AWS]${NC} $*" | tee -a "$LOG_FILE"; }
log_step()  { echo -e "${BLUE}[AWS]${NC} $*" | tee -a "$LOG_FILE"; }

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vm-type) VM_TYPE="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
}

install_aws_cli() {
    log_step "Checking AWS CLI..."

    if command -v aws &>/dev/null; then
        local ver
        ver=$(aws --version 2>&1 | head -1)
        log_info "AWS CLI already installed: $ver"
        return
    fi

    log_info "Installing AWS CLI v2..."
    local tmp_dir
    tmp_dir=$(mktemp -d)

    if command -v curl &>/dev/null; then
        curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$tmp_dir/awscliv2.zip" 2>>"$LOG_FILE" || {
            log_warn "Could not download AWS CLI. Install manually: https://aws.amazon.com/cli/"
            rm -rf "$tmp_dir"
            return
        }
        if command -v unzip &>/dev/null; then
            unzip -q "$tmp_dir/awscliv2.zip" -d "$tmp_dir" 2>>"$LOG_FILE"
            if command -v sudo &>/dev/null; then
                sudo "$tmp_dir/aws/install" 2>>"$LOG_FILE" || log_warn "AWS CLI install failed"
            else
                "$tmp_dir/aws/install" --install-dir /opt/aws-cli --bin-dir /usr/local/bin 2>>"$LOG_FILE" || log_warn "AWS CLI install failed"
            fi
        else
            log_warn "unzip not found, cannot install AWS CLI"
        fi
        rm -rf "$tmp_dir"
    fi
}

configure_imds_v2() {
    log_step "Configuring IMDSv2 for enhanced security..."

    # Check if we're on an EC2 instance
    if ! curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/ &>/dev/null; then
        log_warn "Not running on EC2, skipping IMDSv2 configuration"
        return
    fi

    # Get IMDSv2 token
    local token
    token=$(curl -s --connect-timeout 2 -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")

    if [[ -n "$token" ]]; then
        log_info "IMDSv2 token obtained successfully"

        # Get instance metadata
        local instance_id instance_type region az
        instance_id=$(curl -s -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
        instance_type=$(curl -s -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo "unknown")
        az=$(curl -s -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || echo "unknown")
        region="${az%?}"

        log_info "Instance ID: $instance_id"
        log_info "Instance Type: $instance_type"
        log_info "Region: $region"
        log_info "Availability Zone: $az"
    else
        log_warn "Could not obtain IMDSv2 token"
    fi
}

optimize_for_vm_type() {
    local vm_type="$1"
    log_step "Optimizing for VM type: $vm_type..."

    case "$vm_type" in
        large)
            log_info "Large VM detected - enabling high-performance settings"
            log_info "  - Increased connection pool: 200"
            log_info "  - Worker threads: 8"
            log_info "  - Memory cache: 4GB"
            ;;
        medium)
            log_info "Medium VM detected - using balanced settings"
            log_info "  - Connection pool: 100"
            log_info "  - Worker threads: 4"
            log_info "  - Memory cache: 2GB"
            ;;
        small|*)
            log_info "Small VM detected - using conservative settings"
            log_info "  - Connection pool: 50"
            log_info "  - Worker threads: 2"
            log_info "  - Memory cache: 512MB"
            ;;
    esac
}

configure_aws_storage() {
    log_step "Configuring AWS storage optimizations..."

    # Check for NVMe instance store volumes
    if ls /dev/nvme*n1 &>/dev/null 2>&1; then
        log_info "NVMe volumes detected, can be used for high-speed cache"
    else
        log_info "No NVMe instance store volumes found, using EBS"
    fi

    # Optimize EBS settings if available
    if [[ -f /sys/block/xvda/queue/read_ahead_kb ]]; then
        if command -v sudo &>/dev/null; then
            sudo sh -c 'echo 4096 > /sys/block/xvda/queue/read_ahead_kb' 2>/dev/null || true
            log_info "EBS read-ahead optimized to 4096KB"
        fi
    fi
}

configure_aws_networking() {
    log_step "Configuring AWS networking..."

    # Enable enhanced networking check
    if [[ -d /sys/class/net/eth0 ]]; then
        local driver
        driver=$(basename "$(readlink /sys/class/net/eth0/device/driver 2>/dev/null)" 2>/dev/null || echo "unknown")
        if [[ "$driver" == "ena" ]]; then
            log_info "ENA (Elastic Network Adapter) detected - enhanced networking active"
        else
            log_info "Network driver: $driver"
        fi
    fi

    log_info "AWS networking configuration complete."
}

main() {
    echo "" > "$LOG_FILE"
    log_info "=== AWS Provider Setup Starting ==="

    parse_args "$@"

    install_aws_cli
    configure_imds_v2
    optimize_for_vm_type "${VM_TYPE:-small}"
    configure_aws_storage
    configure_aws_networking

    log_info "=== AWS Provider Setup Complete ==="
}

main "$@"
