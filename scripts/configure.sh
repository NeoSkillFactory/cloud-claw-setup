#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# Defaults
PROVIDER=""
CONFIG_TEMPLATE="$SKILL_DIR/assets/config-template.yaml"
OUTPUT_CONFIG="/tmp/openclaw-config.yaml"
VM_TYPE=""
DRY_RUN=false
LOG_FILE="/tmp/openclaw-configure.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $*" | tee -a "$LOG_FILE"; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Configure OpenClaw on a cloud VM with optimized settings.

Options:
  --provider <aws|gcp|azure>   Cloud provider (default: auto-detect)
  --config <path>              Custom config template (default: assets/config-template.yaml)
  --output <path>              Output config path (default: /tmp/openclaw-config.yaml)
  --vm-type <type>             VM instance type
  --dry-run                    Show what would be configured
  -h, --help                   Show this help message
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider)  PROVIDER="$2"; shift 2 ;;
            --config)    CONFIG_TEMPLATE="$2"; shift 2 ;;
            --output)    OUTPUT_CONFIG="$2"; shift 2 ;;
            --vm-type)   VM_TYPE="$2"; shift 2 ;;
            --dry-run)   DRY_RUN=true; shift ;;
            -h|--help)   usage ;;
            *)           log_error "Unknown option: $1"; usage ;;
        esac
    done
}

detect_provider() {
    if [[ -n "$PROVIDER" ]]; then
        echo "$PROVIDER"
        return
    fi

    if curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/ &>/dev/null; then
        echo "aws"; return
    fi
    if curl -s --connect-timeout 2 -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/ &>/dev/null; then
        echo "gcp"; return
    fi
    if curl -s --connect-timeout 2 -H "Metadata: true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" &>/dev/null; then
        echo "azure"; return
    fi

    echo "generic"
}

get_system_resources() {
    local cpus mem_kb mem_gb
    cpus=$(nproc 2>/dev/null || echo 2)
    mem_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 4194304)
    mem_gb=$(( mem_kb / 1048576 ))

    echo "$cpus $mem_gb"
}

calculate_worker_count() {
    local cpus="$1"
    # Use 75% of CPUs for workers, minimum 1
    local workers=$(( cpus * 3 / 4 ))
    [[ $workers -lt 1 ]] && workers=1
    echo "$workers"
}

calculate_memory_limit() {
    local mem_gb="$1"
    # Allocate 60% of RAM for OpenClaw
    local limit=$(( mem_gb * 60 / 100 ))
    [[ $limit -lt 1 ]] && limit=1
    echo "${limit}g"
}

get_provider_settings() {
    local provider="$1"
    case "$provider" in
        aws)
            cat <<EOF
  cloud:
    provider: aws
    region: auto
    use_imds_v2: true
    storage_backend: s3
    network_mode: vpc
    metadata_endpoint: "http://169.254.169.254/latest"
EOF
            ;;
        gcp)
            cat <<EOF
  cloud:
    provider: gcp
    region: auto
    storage_backend: gcs
    network_mode: vpc
    metadata_endpoint: "http://metadata.google.internal"
    metadata_flavor: Google
EOF
            ;;
        azure)
            cat <<EOF
  cloud:
    provider: azure
    region: auto
    storage_backend: blob
    network_mode: vnet
    metadata_endpoint: "http://169.254.169.254/metadata"
    metadata_version: "2021-02-01"
EOF
            ;;
        *)
            cat <<EOF
  cloud:
    provider: generic
    region: local
    storage_backend: filesystem
    network_mode: host
EOF
            ;;
    esac
}

generate_config() {
    local provider="$1"
    local cpus="$2"
    local mem_gb="$3"

    local workers mem_limit
    workers=$(calculate_worker_count "$cpus")
    mem_limit=$(calculate_memory_limit "$mem_gb")

    log_step "Generating OpenClaw configuration..."
    log_info "  Provider: $provider"
    log_info "  CPUs: $cpus, Workers: $workers"
    log_info "  Memory: ${mem_gb}GB, Limit: $mem_limit"

    if $DRY_RUN; then
        log_info "[DRY RUN] Would generate config at $OUTPUT_CONFIG"
        return
    fi

    cat > "$OUTPUT_CONFIG" <<CONFIG_EOF
# OpenClaw Configuration
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Provider: $provider

openclaw:
  version: "1.0"
  environment: production

  server:
    host: "0.0.0.0"
    port: 8080
    workers: $workers
    max_connections: $(( workers * 50 ))
    request_timeout: 300
    keep_alive: true

  resources:
    memory_limit: "$mem_limit"
    cpu_limit: "$cpus"
    max_concurrent_agents: $(( workers * 2 ))
    task_queue_size: $(( workers * 10 ))

  agent:
    default_model: "claude-sonnet-4-6"
    max_turns: 25
    enable_tools: true
    sandbox_mode: true

  logging:
    level: info
    format: json
    output: /var/log/openclaw/openclaw.log
    max_size: "100m"
    max_backups: 5

  security:
    enable_tls: true
    api_key_required: true
    rate_limiting:
      enabled: true
      requests_per_minute: 60
    cors:
      enabled: true
      allowed_origins:
        - "https://*"

$(get_provider_settings "$provider")

  storage:
    data_dir: /var/lib/openclaw/data
    cache_dir: /var/lib/openclaw/cache
    temp_dir: /tmp/openclaw

  health:
    enabled: true
    endpoint: /health
    interval: 30
CONFIG_EOF

    log_info "Configuration written to $OUTPUT_CONFIG"
}

copy_config_to_system() {
    if $DRY_RUN; then
        log_info "[DRY RUN] Would copy config to /etc/openclaw/config.yaml"
        return
    fi

    local target="/etc/openclaw/config.yaml"
    if command -v sudo &>/dev/null; then
        sudo mkdir -p /etc/openclaw 2>/dev/null || true
        sudo cp "$OUTPUT_CONFIG" "$target" 2>/dev/null || {
            log_warn "Could not copy to $target (permission denied). Config remains at $OUTPUT_CONFIG"
            return
        }
    else
        mkdir -p /etc/openclaw 2>/dev/null || true
        cp "$OUTPUT_CONFIG" "$target" 2>/dev/null || {
            log_warn "Could not copy to $target (permission denied). Config remains at $OUTPUT_CONFIG"
            return
        }
    fi
    log_info "Configuration installed to $target"
}

apply_template_overrides() {
    if [[ ! -f "$CONFIG_TEMPLATE" ]]; then
        log_info "No custom template found at $CONFIG_TEMPLATE, using defaults."
        return
    fi

    log_step "Applying template overrides from $CONFIG_TEMPLATE..."

    if $DRY_RUN; then
        log_info "[DRY RUN] Would merge overrides from $CONFIG_TEMPLATE"
        return
    fi

    # Append template comments to generated config for traceability
    echo "" >> "$OUTPUT_CONFIG"
    echo "# Template overrides applied from: $CONFIG_TEMPLATE" >> "$OUTPUT_CONFIG"
    echo "# Override timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$OUTPUT_CONFIG"
    log_info "Template overrides noted in config."
}

configure_network() {
    local provider="$1"
    log_step "Configuring network settings for $provider..."

    if $DRY_RUN; then
        log_info "[DRY RUN] Would configure network for $provider"
        return
    fi

    # Optimize TCP settings for AI workload traffic
    local sysctl_conf="/tmp/openclaw-sysctl.conf"
    cat > "$sysctl_conf" <<SYSCTL_EOF
# OpenClaw Network Optimizations
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
SYSCTL_EOF

    if command -v sudo &>/dev/null && command -v sysctl &>/dev/null; then
        sudo cp "$sysctl_conf" /etc/sysctl.d/99-openclaw.conf 2>/dev/null && \
        sudo sysctl --system &>/dev/null || \
        log_warn "Could not apply sysctl settings (permission denied or sysctl unavailable)"
    else
        log_warn "sysctl not available, network optimizations skipped. Settings saved to $sysctl_conf"
    fi

    log_info "Network configuration complete."
}

main() {
    echo "" > "$LOG_FILE"
    log_info "=== OpenClaw Configuration Starting ==="

    parse_args "$@"

    local provider
    provider=$(detect_provider)

    local resources cpus mem_gb
    resources=$(get_system_resources)
    cpus=$(echo "$resources" | awk '{print $1}')
    mem_gb=$(echo "$resources" | awk '{print $2}')

    generate_config "$provider" "$cpus" "$mem_gb"
    apply_template_overrides
    configure_network "$provider"
    copy_config_to_system

    log_info "=== OpenClaw Configuration Complete ==="
    log_info "Config: $OUTPUT_CONFIG"
    log_info "Log: $LOG_FILE"
    log_info "Next step: Run scripts/validate.sh to verify installation"
}

main "$@"
