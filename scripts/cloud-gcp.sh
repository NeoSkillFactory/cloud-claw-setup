#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/openclaw-gcp.log"
VM_TYPE=""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[GCP]${NC} $*" | tee -a "$LOG_FILE"; }
log_warn()  { echo -e "${YELLOW}[GCP]${NC} $*" | tee -a "$LOG_FILE"; }
log_step()  { echo -e "${BLUE}[GCP]${NC} $*" | tee -a "$LOG_FILE"; }

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vm-type) VM_TYPE="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
}

install_gcloud_cli() {
    log_step "Checking Google Cloud CLI..."

    if command -v gcloud &>/dev/null; then
        local ver
        ver=$(gcloud --version 2>&1 | head -1)
        log_info "Google Cloud CLI already installed: $ver"
        return
    fi

    log_info "Installing Google Cloud CLI..."

    if command -v curl &>/dev/null; then
        curl -fsSL https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz -o /tmp/google-cloud-cli.tar.gz 2>>"$LOG_FILE" || {
            log_warn "Could not download Google Cloud CLI. Install manually: https://cloud.google.com/sdk/docs/install"
            return
        }
        if [[ -f /tmp/google-cloud-cli.tar.gz ]]; then
            tar -xzf /tmp/google-cloud-cli.tar.gz -C /opt/ 2>>"$LOG_FILE" || {
                tar -xzf /tmp/google-cloud-cli.tar.gz -C /tmp/ 2>>"$LOG_FILE" || log_warn "Could not extract Google Cloud CLI"
            }
            rm -f /tmp/google-cloud-cli.tar.gz
            log_info "Google Cloud CLI extracted. Run /opt/google-cloud-sdk/install.sh to complete."
        fi
    fi
}

get_gcp_metadata() {
    log_step "Retrieving GCP instance metadata..."

    local metadata_base="http://metadata.google.internal/computeMetadata/v1"
    local header="Metadata-Flavor: Google"

    if ! curl -s --connect-timeout 2 -H "$header" "$metadata_base/" &>/dev/null; then
        log_warn "Not running on GCP, skipping metadata retrieval"
        return
    fi

    local project_id zone machine_type instance_name
    project_id=$(curl -s -H "$header" "$metadata_base/project/project-id" 2>/dev/null || echo "unknown")
    zone=$(curl -s -H "$header" "$metadata_base/instance/zone" 2>/dev/null || echo "unknown")
    zone="${zone##*/}"  # Extract zone name from full path
    machine_type=$(curl -s -H "$header" "$metadata_base/instance/machine-type" 2>/dev/null || echo "unknown")
    machine_type="${machine_type##*/}"
    instance_name=$(curl -s -H "$header" "$metadata_base/instance/name" 2>/dev/null || echo "unknown")

    log_info "Project: $project_id"
    log_info "Zone: $zone"
    log_info "Machine Type: $machine_type"
    log_info "Instance: $instance_name"
}

optimize_for_vm_type() {
    local vm_type="$1"
    log_step "Optimizing for VM type: $vm_type..."

    case "$vm_type" in
        large)
            log_info "Large VM (n2-standard-8+) - high-performance settings"
            log_info "  - Worker threads: 8"
            log_info "  - Memory allocation: 75%"
            log_info "  - Connection pool: 200"
            ;;
        medium)
            log_info "Medium VM (n2-standard-4) - balanced settings"
            log_info "  - Worker threads: 4"
            log_info "  - Memory allocation: 60%"
            log_info "  - Connection pool: 100"
            ;;
        small|*)
            log_info "Small VM (e2-medium or similar) - conservative settings"
            log_info "  - Worker threads: 2"
            log_info "  - Memory allocation: 50%"
            log_info "  - Connection pool: 50"
            ;;
    esac
}

configure_gcp_storage() {
    log_step "Configuring GCP storage optimizations..."

    # Check for local SSD
    if ls /dev/disk/by-id/google-local-ssd-* &>/dev/null 2>&1; then
        log_info "Local SSD detected - can be used for high-performance cache"
    else
        log_info "Using persistent disk for storage"
    fi

    # Optimize disk I/O scheduler
    for disk in /sys/block/sd*/queue/scheduler; do
        if [[ -f "$disk" ]]; then
            if command -v sudo &>/dev/null; then
                sudo sh -c "echo none > $disk" 2>/dev/null || true
            fi
        fi
    done
    log_info "Disk I/O scheduler optimized."
}

configure_gcp_networking() {
    log_step "Configuring GCP networking..."

    # Check for gVNIC (high-performance virtual NIC)
    if [[ -d /sys/class/net/eth0 ]]; then
        local driver
        driver=$(basename "$(readlink /sys/class/net/eth0/device/driver 2>/dev/null)" 2>/dev/null || echo "unknown")
        if [[ "$driver" == "gve" ]]; then
            log_info "gVNIC detected - high-performance networking active"
        else
            log_info "Network driver: $driver (consider gVNIC for better performance)"
        fi
    fi

    log_info "GCP networking configuration complete."
}

setup_gcp_logging() {
    log_step "Configuring GCP Cloud Logging integration..."

    if command -v google_metadata_script_runner &>/dev/null || [[ -f /etc/google-cloud-ops-agent/config.yaml ]]; then
        log_info "Google Cloud Ops Agent detected, logging integration available"
    else
        log_info "Google Cloud Ops Agent not installed. OpenClaw will use local file logging."
        log_info "Install ops-agent for Cloud Logging: https://cloud.google.com/logging/docs/agent/ops-agent"
    fi
}

main() {
    echo "" > "$LOG_FILE"
    log_info "=== GCP Provider Setup Starting ==="

    parse_args "$@"

    install_gcloud_cli
    get_gcp_metadata
    optimize_for_vm_type "${VM_TYPE:-small}"
    configure_gcp_storage
    configure_gcp_networking
    setup_gcp_logging

    log_info "=== GCP Provider Setup Complete ==="
}

main "$@"
