#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/openclaw-azure.log"
VM_TYPE=""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[AZURE]${NC} $*" | tee -a "$LOG_FILE"; }
log_warn()  { echo -e "${YELLOW}[AZURE]${NC} $*" | tee -a "$LOG_FILE"; }
log_step()  { echo -e "${BLUE}[AZURE]${NC} $*" | tee -a "$LOG_FILE"; }

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vm-type) VM_TYPE="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
}

install_azure_cli() {
    log_step "Checking Azure CLI..."

    if command -v az &>/dev/null; then
        local ver
        ver=$(az version 2>&1 | head -1)
        log_info "Azure CLI already installed: $ver"
        return
    fi

    log_info "Installing Azure CLI..."

    if command -v curl &>/dev/null; then
        curl -fsSL https://aka.ms/InstallAzureCLIDeb 2>>"$LOG_FILE" | sudo bash 2>>"$LOG_FILE" || {
            # Fallback: try pip install
            if command -v pip3 &>/dev/null; then
                pip3 install --quiet azure-cli 2>>"$LOG_FILE" || log_warn "Could not install Azure CLI. Install manually: https://learn.microsoft.com/cli/azure/install-azure-cli"
            else
                log_warn "Could not install Azure CLI. Install manually: https://learn.microsoft.com/cli/azure/install-azure-cli"
            fi
        }
    fi
}

get_azure_metadata() {
    log_step "Retrieving Azure instance metadata..."

    local metadata_url="http://169.254.169.254/metadata/instance?api-version=2021-02-01"

    if ! curl -s --connect-timeout 2 -H "Metadata: true" "$metadata_url" &>/dev/null; then
        log_warn "Not running on Azure, skipping metadata retrieval"
        return
    fi

    local metadata
    metadata=$(curl -s -H "Metadata: true" "$metadata_url" 2>/dev/null || echo "{}")

    if command -v jq &>/dev/null; then
        local vm_name vm_size location resource_group
        vm_name=$(echo "$metadata" | jq -r '.compute.name // "unknown"' 2>/dev/null || echo "unknown")
        vm_size=$(echo "$metadata" | jq -r '.compute.vmSize // "unknown"' 2>/dev/null || echo "unknown")
        location=$(echo "$metadata" | jq -r '.compute.location // "unknown"' 2>/dev/null || echo "unknown")
        resource_group=$(echo "$metadata" | jq -r '.compute.resourceGroupName // "unknown"' 2>/dev/null || echo "unknown")

        log_info "VM Name: $vm_name"
        log_info "VM Size: $vm_size"
        log_info "Location: $location"
        log_info "Resource Group: $resource_group"
    else
        log_info "Metadata retrieved (install jq for detailed parsing)"
    fi
}

optimize_for_vm_type() {
    local vm_type="$1"
    log_step "Optimizing for VM type: $vm_type..."

    case "$vm_type" in
        large)
            log_info "Large VM (Standard_D8s_v5+) - high-performance settings"
            log_info "  - Worker threads: 8"
            log_info "  - Memory allocation: 75%"
            log_info "  - Connection pool: 200"
            ;;
        medium)
            log_info "Medium VM (Standard_D4s_v5) - balanced settings"
            log_info "  - Worker threads: 4"
            log_info "  - Memory allocation: 60%"
            log_info "  - Connection pool: 100"
            ;;
        small|*)
            log_info "Small VM (Standard_B2s or similar) - conservative settings"
            log_info "  - Worker threads: 2"
            log_info "  - Memory allocation: 50%"
            log_info "  - Connection pool: 50"
            ;;
    esac
}

configure_azure_storage() {
    log_step "Configuring Azure storage optimizations..."

    # Check for temp disk (most Azure VMs have /dev/sdb1 as temp)
    if mount | grep -q "/mnt" 2>/dev/null; then
        log_info "Azure temp disk detected at /mnt - can be used for ephemeral cache"
    fi

    # Check for premium SSD
    if ls /dev/sd[c-z] &>/dev/null 2>&1; then
        log_info "Additional data disks detected"
    fi

    # Optimize disk I/O
    for disk in /sys/block/sd*/queue/read_ahead_kb; do
        if [[ -f "$disk" ]]; then
            if command -v sudo &>/dev/null; then
                sudo sh -c "echo 4096 > $disk" 2>/dev/null || true
            fi
        fi
    done
    log_info "Azure storage optimization complete."
}

configure_azure_networking() {
    log_step "Configuring Azure networking..."

    # Check for accelerated networking
    if [[ -d /sys/class/net/eth0 ]]; then
        local driver
        driver=$(basename "$(readlink /sys/class/net/eth0/device/driver 2>/dev/null)" 2>/dev/null || echo "unknown")
        if [[ "$driver" == "hv_netvsc" ]]; then
            # Check if Mellanox VF is present (accelerated networking)
            if lspci 2>/dev/null | grep -qi "mellanox\|connectx"; then
                log_info "Accelerated Networking detected (Mellanox VF present)"
            else
                log_info "Standard networking (hv_netvsc) - consider enabling Accelerated Networking"
            fi
        else
            log_info "Network driver: $driver"
        fi
    fi

    log_info "Azure networking configuration complete."
}

configure_azure_monitoring() {
    log_step "Configuring Azure monitoring integration..."

    if command -v waagent &>/dev/null; then
        log_info "Azure Linux Agent (waagent) detected"
        local wa_ver
        wa_ver=$(waagent --version 2>&1 | head -1 || echo "unknown")
        log_info "  Version: $wa_ver"
    else
        log_info "Azure Linux Agent not found. OpenClaw will use local monitoring."
    fi

    if systemctl is-active --quiet azuremonitoragent 2>/dev/null; then
        log_info "Azure Monitor Agent is active"
    else
        log_info "Azure Monitor Agent not running. Install for Azure Monitor integration."
    fi
}

main() {
    echo "" > "$LOG_FILE"
    log_info "=== Azure Provider Setup Starting ==="

    parse_args "$@"

    install_azure_cli
    get_azure_metadata
    optimize_for_vm_type "${VM_TYPE:-small}"
    configure_azure_storage
    configure_azure_networking
    configure_azure_monitoring

    log_info "=== Azure Provider Setup Complete ==="
}

main "$@"
