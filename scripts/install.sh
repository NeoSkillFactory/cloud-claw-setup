#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# Defaults
PROVIDER=""
VM_TYPE=""
DRY_RUN=false
LOG_FILE="/tmp/openclaw-install.log"

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

Install OpenClaw and its dependencies on a cloud VM.

Options:
  --provider <aws|gcp|azure>   Cloud provider (default: auto-detect)
  --vm-type <type>             VM instance type for optimization
  --dry-run                    Show what would be done without changes
  -h, --help                   Show this help message

Examples:
  $(basename "$0")                      # Auto-detect provider
  $(basename "$0") --provider aws       # AWS-specific install
  $(basename "$0") --dry-run            # Preview mode
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider)
                PROVIDER="$2"
                shift 2
                ;;
            --vm-type)
                VM_TYPE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    elif [[ -f /etc/redhat-release ]]; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

detect_package_manager() {
    if command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v apk &>/dev/null; then
        echo "apk"
    else
        echo "unknown"
    fi
}

detect_provider() {
    if [[ -n "$PROVIDER" ]]; then
        echo "$PROVIDER"
        return
    fi

    # Check for AWS metadata service
    if curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/ &>/dev/null; then
        echo "aws"
        return
    fi

    # Check for GCP metadata service
    if curl -s --connect-timeout 2 -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/ &>/dev/null; then
        echo "gcp"
        return
    fi

    # Check for Azure metadata service
    if curl -s --connect-timeout 2 -H "Metadata: true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" &>/dev/null; then
        echo "azure"
        return
    fi

    echo "generic"
}

detect_vm_type() {
    if [[ -n "$VM_TYPE" ]]; then
        echo "$VM_TYPE"
        return
    fi

    local cpus mem_kb mem_gb
    cpus=$(nproc 2>/dev/null || echo 1)
    mem_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 1048576)
    mem_gb=$(( mem_kb / 1048576 ))

    if [[ $cpus -ge 8 && $mem_gb -ge 30 ]]; then
        echo "large"
    elif [[ $cpus -ge 4 && $mem_gb -ge 14 ]]; then
        echo "medium"
    else
        echo "small"
    fi
}

install_base_packages() {
    local pkg_mgr="$1"
    log_step "Installing base system packages via $pkg_mgr..."

    local packages=(curl wget git jq openssl ca-certificates gnupg lsb-release unzip)

    if $DRY_RUN; then
        log_info "[DRY RUN] Would install: ${packages[*]}"
        return
    fi

    case "$pkg_mgr" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            if command -v sudo &>/dev/null; then
                sudo apt-get update -qq 2>>"$LOG_FILE"
                sudo apt-get install -y -qq "${packages[@]}" 2>>"$LOG_FILE"
            else
                apt-get update -qq 2>>"$LOG_FILE"
                apt-get install -y -qq "${packages[@]}" 2>>"$LOG_FILE"
            fi
            ;;
        dnf)
            if command -v sudo &>/dev/null; then
                sudo dnf install -y -q "${packages[@]}" 2>>"$LOG_FILE"
            else
                dnf install -y -q "${packages[@]}" 2>>"$LOG_FILE"
            fi
            ;;
        yum)
            if command -v sudo &>/dev/null; then
                sudo yum install -y -q "${packages[@]}" 2>>"$LOG_FILE"
            else
                yum install -y -q "${packages[@]}" 2>>"$LOG_FILE"
            fi
            ;;
        apk)
            if command -v sudo &>/dev/null; then
                sudo apk add --quiet "${packages[@]}" 2>>"$LOG_FILE"
            else
                apk add --quiet "${packages[@]}" 2>>"$LOG_FILE"
            fi
            ;;
        *)
            log_warn "Unknown package manager '$pkg_mgr'. Checking if required packages exist..."
            local missing=()
            for pkg in "${packages[@]}"; do
                if ! command -v "$pkg" &>/dev/null; then
                    missing+=("$pkg")
                fi
            done
            if [[ ${#missing[@]} -gt 0 ]]; then
                log_error "Missing packages and no supported package manager found: ${missing[*]}"
                return 1
            fi
            ;;
    esac
    log_info "Base packages installed successfully."
}

install_nodejs() {
    log_step "Checking Node.js installation..."

    if command -v node &>/dev/null; then
        local node_ver
        node_ver=$(node --version 2>/dev/null || echo "unknown")
        log_info "Node.js already installed: $node_ver"
        return
    fi

    if $DRY_RUN; then
        log_info "[DRY RUN] Would install Node.js LTS"
        return
    fi

    log_info "Installing Node.js LTS..."
    if command -v curl &>/dev/null; then
        if command -v sudo &>/dev/null; then
            curl -fsSL https://deb.nodesource.com/setup_lts.x 2>>"$LOG_FILE" | sudo bash - 2>>"$LOG_FILE"
        else
            curl -fsSL https://deb.nodesource.com/setup_lts.x 2>>"$LOG_FILE" | bash - 2>>"$LOG_FILE"
        fi
        local pkg_mgr
        pkg_mgr=$(detect_package_manager)
        if command -v sudo &>/dev/null; then
            case "$pkg_mgr" in
                apt) sudo apt-get install -y -qq nodejs 2>>"$LOG_FILE" ;;
                dnf) sudo dnf install -y -q nodejs 2>>"$LOG_FILE" ;;
                yum) sudo yum install -y -q nodejs 2>>"$LOG_FILE" ;;
            esac
        else
            case "$pkg_mgr" in
                apt) apt-get install -y -qq nodejs 2>>"$LOG_FILE" ;;
                dnf) dnf install -y -q nodejs 2>>"$LOG_FILE" ;;
                yum) yum install -y -q nodejs 2>>"$LOG_FILE" ;;
            esac
        fi
    fi
    log_info "Node.js installed: $(node --version 2>/dev/null || echo 'installation pending')"
}

install_python() {
    log_step "Checking Python installation..."

    if command -v python3 &>/dev/null; then
        local py_ver
        py_ver=$(python3 --version 2>/dev/null || echo "unknown")
        log_info "Python already installed: $py_ver"
        return
    fi

    if $DRY_RUN; then
        log_info "[DRY RUN] Would install Python 3"
        return
    fi

    log_info "Installing Python 3..."
    local pkg_mgr
    pkg_mgr=$(detect_package_manager)
    case "$pkg_mgr" in
        apt)
            if command -v sudo &>/dev/null; then
                sudo apt-get install -y -qq python3 python3-pip python3-venv 2>>"$LOG_FILE"
            else
                apt-get install -y -qq python3 python3-pip python3-venv 2>>"$LOG_FILE"
            fi
            ;;
        dnf|yum)
            if command -v sudo &>/dev/null; then
                sudo "$pkg_mgr" install -y -q python3 python3-pip 2>>"$LOG_FILE"
            else
                "$pkg_mgr" install -y -q python3 python3-pip 2>>"$LOG_FILE"
            fi
            ;;
    esac
    log_info "Python installed: $(python3 --version 2>/dev/null || echo 'installation pending')"
}

install_openclaw_packages() {
    log_step "Installing OpenClaw packages..."

    if $DRY_RUN; then
        log_info "[DRY RUN] Would install OpenClaw via npm"
        return
    fi

    if command -v npm &>/dev/null; then
        npm install -g openclaw 2>>"$LOG_FILE" || log_warn "OpenClaw npm package not yet published; skipping global install"
    fi

    if command -v pip3 &>/dev/null; then
        pip3 install --quiet openclaw 2>>"$LOG_FILE" || log_warn "OpenClaw pip package not yet published; skipping pip install"
    fi

    log_info "OpenClaw package installation step complete."
}

run_provider_script() {
    local provider="$1"
    local provider_script="$SCRIPT_DIR/cloud-${provider}.sh"

    if [[ "$provider" == "generic" ]]; then
        log_info "No cloud provider detected, skipping provider-specific setup."
        return
    fi

    if [[ -f "$provider_script" ]]; then
        log_step "Running provider-specific setup for $provider..."
        if $DRY_RUN; then
            log_info "[DRY RUN] Would run: $provider_script"
            return
        fi
        bash "$provider_script" --vm-type "$(detect_vm_type)"
    else
        log_warn "Provider script not found: $provider_script"
    fi
}

create_openclaw_dirs() {
    log_step "Creating OpenClaw directory structure..."

    local dirs=(
        /etc/openclaw
        /var/lib/openclaw
        /var/log/openclaw
        /opt/openclaw
    )

    if $DRY_RUN; then
        log_info "[DRY RUN] Would create: ${dirs[*]}"
        return
    fi

    for dir in "${dirs[@]}"; do
        if command -v sudo &>/dev/null; then
            sudo mkdir -p "$dir" 2>/dev/null || mkdir -p "$dir" 2>/dev/null || log_warn "Could not create $dir"
        else
            mkdir -p "$dir" 2>/dev/null || log_warn "Could not create $dir (permission denied)"
        fi
    done
    log_info "OpenClaw directories created."
}

generate_deployment_script() {
    local provider="$1"
    local vm_type="$2"
    local deploy_script="/tmp/openclaw-deployment.sh"

    log_step "Generating deployment script at $deploy_script..."

    if $DRY_RUN; then
        log_info "[DRY RUN] Would generate deployment script"
        return
    fi

    cat > "$deploy_script" <<'DEPLOY_HEADER'
#!/usr/bin/env bash
DEPLOY_HEADER
    cat >> "$deploy_script" <<DEPLOY_EOF
# OpenClaw Deployment Script
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Provider: $provider
# VM Type: $vm_type
# Original script directory: $SCRIPT_DIR
set -euo pipefail

SKILL_SCRIPTS="$SCRIPT_DIR"

echo "Replaying OpenClaw installation..."

# Step 1: Install dependencies
bash "\$SKILL_SCRIPTS/install.sh" --provider "$provider"

# Step 2: Configure
bash "\$SKILL_SCRIPTS/configure.sh" --provider "$provider"

# Step 3: Validate
bash "\$SKILL_SCRIPTS/validate.sh"

echo "OpenClaw deployment complete."
DEPLOY_EOF

    chmod +x "$deploy_script"
    log_info "Deployment script generated: $deploy_script"
}

main() {
    echo "" > "$LOG_FILE"
    log_info "=== OpenClaw Installation Starting ==="
    log_info "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    parse_args "$@"

    local os pkg_mgr provider vm_type
    os=$(detect_os)
    pkg_mgr=$(detect_package_manager)
    provider=$(detect_provider)
    vm_type=$(detect_vm_type)

    log_info "OS: $os"
    log_info "Package Manager: $pkg_mgr"
    log_info "Cloud Provider: $provider"
    log_info "VM Type: $vm_type"

    if $DRY_RUN; then
        log_info "=== DRY RUN MODE ==="
    fi

    install_base_packages "$pkg_mgr"
    install_nodejs
    install_python
    create_openclaw_dirs
    install_openclaw_packages
    run_provider_script "$provider"
    generate_deployment_script "$provider" "$vm_type"

    log_info "=== OpenClaw Installation Complete ==="
    log_info "Log file: $LOG_FILE"
    log_info "Next step: Run scripts/configure.sh to configure OpenClaw"
}

main "$@"
