#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

LOG_FILE="/tmp/openclaw-validate.log"
CONFIG_FILE="/tmp/openclaw-config.yaml"
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
CHECKS_RUN=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"; WARN_COUNT=$((WARN_COUNT + 1)); }
log_error() { echo -e "${RED}[FAIL]${NC} $*" | tee -a "$LOG_FILE"; }
log_step()  { echo -e "${BLUE}[CHECK]${NC} $*" | tee -a "$LOG_FILE"; }

check_pass() {
    echo -e "  ${GREEN}✓${NC} $*" | tee -a "$LOG_FILE"
    PASS_COUNT=$((PASS_COUNT + 1))
    CHECKS_RUN=$((CHECKS_RUN + 1))
}

check_fail() {
    echo -e "  ${RED}✗${NC} $*" | tee -a "$LOG_FILE"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    CHECKS_RUN=$((CHECKS_RUN + 1))
}

check_warn() {
    echo -e "  ${YELLOW}!${NC} $*" | tee -a "$LOG_FILE"
    WARN_COUNT=$((WARN_COUNT + 1))
    CHECKS_RUN=$((CHECKS_RUN + 1))
}

check_command_exists() {
    local cmd="$1"
    local label="${2:-$cmd}"
    if command -v "$cmd" &>/dev/null; then
        local version
        version=$("$cmd" --version 2>/dev/null | head -1 || echo "installed")
        check_pass "$label: $version"
        return 0
    else
        check_fail "$label: not found"
        return 1
    fi
}

validate_core_dependencies() {
    log_step "Validating core dependencies..."

    check_command_exists "bash" "Bash"
    check_command_exists "curl" "cURL"
    check_command_exists "wget" "wget"
    check_command_exists "git" "Git"
    check_command_exists "jq" "jq" || check_warn "jq not installed (optional but recommended)"
    check_command_exists "openssl" "OpenSSL"
}

validate_runtime_dependencies() {
    log_step "Validating runtime dependencies..."

    if command -v node &>/dev/null; then
        local node_ver
        node_ver=$(node --version 2>/dev/null)
        local major
        major=$(echo "$node_ver" | sed 's/v//' | cut -d. -f1)
        if [[ "$major" -ge 18 ]]; then
            check_pass "Node.js $node_ver (>= 18 required)"
        else
            check_warn "Node.js $node_ver (>= 18 recommended)"
        fi
    else
        check_warn "Node.js not installed"
    fi

    if command -v python3 &>/dev/null; then
        local py_ver
        py_ver=$(python3 --version 2>/dev/null | awk '{print $2}')
        local py_major py_minor
        py_major=$(echo "$py_ver" | cut -d. -f1)
        py_minor=$(echo "$py_ver" | cut -d. -f2)
        if [[ "$py_major" -ge 3 && "$py_minor" -ge 9 ]]; then
            check_pass "Python $py_ver (>= 3.9 required)"
        else
            check_warn "Python $py_ver (>= 3.9 recommended)"
        fi
    else
        check_warn "Python 3 not installed"
    fi
}

validate_directories() {
    log_step "Validating directory structure..."

    local dirs=(/tmp)
    # Only check system dirs if they could have been created
    for dir in /etc/openclaw /var/lib/openclaw /var/log/openclaw /opt/openclaw; do
        if [[ -d "$dir" ]]; then
            dirs+=("$dir")
        fi
    done

    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            if [[ -w "$dir" ]]; then
                check_pass "Directory $dir exists and is writable"
            else
                check_warn "Directory $dir exists but is not writable by current user"
            fi
        else
            check_fail "Directory $dir does not exist"
        fi
    done
}

validate_config() {
    log_step "Validating configuration..."

    local config_found=false

    # Check multiple config locations
    for cfg in "$CONFIG_FILE" /etc/openclaw/config.yaml; do
        if [[ -f "$cfg" ]]; then
            check_pass "Config file found: $cfg"
            config_found=true

            # Validate config is valid YAML (basic check)
            if command -v python3 &>/dev/null; then
                if python3 -c "
import sys
try:
    import yaml
    yaml.safe_load(open('$cfg'))
    sys.exit(0)
except ImportError:
    # No yaml module, do basic check
    sys.exit(0)
except Exception as e:
    print(str(e))
    sys.exit(1)
" 2>/dev/null; then
                    check_pass "Config file is valid YAML: $cfg"
                else
                    check_warn "Config file may have YAML issues: $cfg"
                fi
            else
                check_pass "Config file exists (YAML validation skipped, no python3)"
            fi
            break
        fi
    done

    if ! $config_found; then
        check_warn "No config file found. Run configure.sh first."
    fi
}

validate_network() {
    log_step "Validating network connectivity..."

    # Test outbound internet access
    if curl -s --connect-timeout 5 -o /dev/null -w "%{http_code}" https://api.github.com 2>/dev/null | grep -q "^[23]"; then
        check_pass "Internet connectivity (github.com reachable)"
    else
        check_warn "Internet connectivity check failed (may be expected in isolated environments)"
    fi

    # Test DNS resolution
    if command -v nslookup &>/dev/null; then
        if nslookup github.com &>/dev/null; then
            check_pass "DNS resolution working"
        else
            check_warn "DNS resolution issue detected"
        fi
    elif command -v host &>/dev/null; then
        if host github.com &>/dev/null; then
            check_pass "DNS resolution working"
        else
            check_warn "DNS resolution issue detected"
        fi
    else
        check_warn "DNS tools not available (nslookup/host), skipping DNS check"
    fi
}

validate_system_resources() {
    log_step "Validating system resources..."

    local cpus mem_kb mem_gb disk_avail_kb disk_avail_gb

    cpus=$(nproc 2>/dev/null || echo 0)
    if [[ $cpus -ge 2 ]]; then
        check_pass "CPU cores: $cpus (>= 2 recommended)"
    else
        check_warn "CPU cores: $cpus (>= 2 recommended)"
    fi

    mem_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
    mem_gb=$(( mem_kb / 1048576 ))
    if [[ $mem_gb -ge 4 ]]; then
        check_pass "Memory: ${mem_gb}GB (>= 4GB recommended)"
    else
        check_warn "Memory: ${mem_gb}GB (>= 4GB recommended)"
    fi

    disk_avail_kb=$(df /tmp 2>/dev/null | tail -1 | awk '{print $4}' || echo 0)
    disk_avail_gb=$(( disk_avail_kb / 1048576 ))
    if [[ $disk_avail_gb -ge 10 ]]; then
        check_pass "Disk space: ${disk_avail_gb}GB available (>= 10GB recommended)"
    else
        check_warn "Disk space: ${disk_avail_gb}GB available (>= 10GB recommended)"
    fi
}

validate_skill_files() {
    log_step "Validating skill file integrity..."

    local required_files=(
        "$SKILL_DIR/SKILL.md"
        "$SKILL_DIR/scripts/install.sh"
        "$SKILL_DIR/scripts/configure.sh"
        "$SKILL_DIR/scripts/validate.sh"
        "$SKILL_DIR/scripts/cloud-aws.sh"
        "$SKILL_DIR/scripts/cloud-gcp.sh"
        "$SKILL_DIR/scripts/cloud-azure.sh"
        "$SKILL_DIR/assets/config-template.yaml"
    )

    for f in "${required_files[@]}"; do
        if [[ -f "$f" ]]; then
            check_pass "File exists: $(basename "$f")"
        else
            check_fail "Missing file: $f"
        fi
    done

    # Check scripts are executable
    for s in "$SKILL_DIR"/scripts/*.sh; do
        if [[ -x "$s" ]]; then
            check_pass "Executable: $(basename "$s")"
        else
            check_warn "Not executable: $(basename "$s") (run chmod +x)"
        fi
    done
}

print_report() {
    echo ""
    echo "========================================" | tee -a "$LOG_FILE"
    echo " OpenClaw Validation Report" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo -e "  ${GREEN}Passed:${NC}   $PASS_COUNT" | tee -a "$LOG_FILE"
    echo -e "  ${RED}Failed:${NC}   $FAIL_COUNT" | tee -a "$LOG_FILE"
    echo -e "  ${YELLOW}Warnings:${NC} $WARN_COUNT" | tee -a "$LOG_FILE"
    echo "  Total:    $CHECKS_RUN" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    if [[ $FAIL_COUNT -eq 0 ]]; then
        echo -e "${GREEN}Status: ALL CRITICAL CHECKS PASSED${NC}" | tee -a "$LOG_FILE"
    else
        echo -e "${RED}Status: $FAIL_COUNT CRITICAL CHECK(S) FAILED${NC}" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        echo "Suggestions:" | tee -a "$LOG_FILE"
        echo "  1. Run scripts/install.sh to install missing dependencies" | tee -a "$LOG_FILE"
        echo "  2. Run scripts/configure.sh to generate configuration" | tee -a "$LOG_FILE"
        echo "  3. Check $LOG_FILE for detailed error information" | tee -a "$LOG_FILE"
    fi

    echo "" | tee -a "$LOG_FILE"
    echo "Full log: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
}

main() {
    echo "" > "$LOG_FILE"
    log_info "=== OpenClaw Validation Starting ==="
    log_info "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    validate_skill_files
    validate_core_dependencies
    validate_runtime_dependencies
    validate_directories
    validate_config
    validate_network
    validate_system_resources

    print_report

    # Exit non-zero if any critical checks failed
    if [[ $FAIL_COUNT -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
