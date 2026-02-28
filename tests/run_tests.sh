#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

PASS=0
FAIL=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $desc (expected: '$expected', got: '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$actual" | grep -q "$expected"; then
        echo -e "${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $desc (expected to contain: '$expected')"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_exists() {
    local desc="$1" filepath="$2"
    TOTAL=$((TOTAL + 1))
    if [[ -f "$filepath" ]]; then
        echo -e "${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $desc (file not found: $filepath)"
        FAIL=$((FAIL + 1))
    fi
}

assert_executable() {
    local desc="$1" filepath="$2"
    TOTAL=$((TOTAL + 1))
    if [[ -x "$filepath" ]]; then
        echo -e "${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $desc (not executable: $filepath)"
        FAIL=$((FAIL + 1))
    fi
}

assert_exit_code() {
    local desc="$1" expected="$2"
    shift 2
    TOTAL=$((TOTAL + 1))
    local actual
    set +e
    "$@" >/dev/null 2>&1
    actual=$?
    set -e
    if [[ "$expected" -eq "$actual" ]]; then
        echo -e "${GREEN}PASS${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $desc (expected exit code: $expected, got: $actual)"
        FAIL=$((FAIL + 1))
    fi
}

echo "======================================"
echo " Cloud Claw Setup - Test Suite"
echo "======================================"
echo ""

# ----------------------------------------
# Test Group 1: File Structure
# ----------------------------------------
echo "--- File Structure Tests ---"

assert_file_exists "SKILL.md exists" "$SKILL_DIR/SKILL.md"
assert_file_exists "package.json exists" "$SKILL_DIR/package.json"
assert_file_exists "README.md exists" "$SKILL_DIR/README.md"
assert_file_exists "install.sh exists" "$SKILL_DIR/scripts/install.sh"
assert_file_exists "configure.sh exists" "$SKILL_DIR/scripts/configure.sh"
assert_file_exists "validate.sh exists" "$SKILL_DIR/scripts/validate.sh"
assert_file_exists "cloud-aws.sh exists" "$SKILL_DIR/scripts/cloud-aws.sh"
assert_file_exists "cloud-gcp.sh exists" "$SKILL_DIR/scripts/cloud-gcp.sh"
assert_file_exists "cloud-azure.sh exists" "$SKILL_DIR/scripts/cloud-azure.sh"
assert_file_exists "cloud-providers.md exists" "$SKILL_DIR/references/cloud-providers.md"
assert_file_exists "dependencies.md exists" "$SKILL_DIR/references/dependencies.md"
assert_file_exists "security.md exists" "$SKILL_DIR/references/security.md"
assert_file_exists "config-template.yaml exists" "$SKILL_DIR/assets/config-template.yaml"
assert_file_exists "example-deployment.json exists" "$SKILL_DIR/assets/example-deployment.json"

echo ""

# ----------------------------------------
# Test Group 2: Script Permissions
# ----------------------------------------
echo "--- Script Permission Tests ---"

assert_executable "install.sh is executable" "$SKILL_DIR/scripts/install.sh"
assert_executable "configure.sh is executable" "$SKILL_DIR/scripts/configure.sh"
assert_executable "validate.sh is executable" "$SKILL_DIR/scripts/validate.sh"
assert_executable "cloud-aws.sh is executable" "$SKILL_DIR/scripts/cloud-aws.sh"
assert_executable "cloud-gcp.sh is executable" "$SKILL_DIR/scripts/cloud-gcp.sh"
assert_executable "cloud-azure.sh is executable" "$SKILL_DIR/scripts/cloud-azure.sh"

echo ""

# ----------------------------------------
# Test Group 3: SKILL.md Frontmatter
# ----------------------------------------
echo "--- SKILL.md Frontmatter Tests ---"

SKILL_CONTENT=$(cat "$SKILL_DIR/SKILL.md")
assert_contains "SKILL.md has YAML frontmatter opening" "^---" "$SKILL_CONTENT"
assert_contains "SKILL.md has name field" "name:" "$SKILL_CONTENT"
assert_contains "SKILL.md has description field" "description:" "$SKILL_CONTENT"

# Extract frontmatter and validate
FRONTMATTER=$(sed -n '/^---$/,/^---$/p' "$SKILL_DIR/SKILL.md" | head -n -1 | tail -n +2)
assert_contains "name is cloud-claw-setup" "cloud-claw-setup" "$FRONTMATTER"

echo ""

# ----------------------------------------
# Test Group 4: package.json Validation
# ----------------------------------------
echo "--- package.json Tests ---"

if command -v jq &>/dev/null; then
    PKG_NAME=$(jq -r '.name' "$SKILL_DIR/package.json")
    PKG_VERSION=$(jq -r '.version' "$SKILL_DIR/package.json")
    PKG_DESC=$(jq -r '.description' "$SKILL_DIR/package.json")

    assert_eq "package.json name" "cloud-claw-setup" "$PKG_NAME"
    assert_eq "package.json version" "1.0.0" "$PKG_VERSION"
    assert_contains "package.json has description" "OpenClaw" "$PKG_DESC"

    # Validate JSON syntax
    TOTAL=$((TOTAL + 1))
    if jq empty "$SKILL_DIR/package.json" 2>/dev/null; then
        echo -e "${GREEN}PASS${NC} package.json is valid JSON"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} package.json is invalid JSON"
        FAIL=$((FAIL + 1))
    fi
else
    echo -e "${YELLOW}SKIP${NC} jq not available, skipping JSON validation"
fi

echo ""

# ----------------------------------------
# Test Group 5: Script Dry Run Tests
# ----------------------------------------
echo "--- Script Dry Run Tests ---"

# Test install.sh --help
assert_exit_code "install.sh --help exits 0" 0 bash "$SKILL_DIR/scripts/install.sh" --help

# Test configure.sh --help
assert_exit_code "configure.sh --help exits 0" 0 bash "$SKILL_DIR/scripts/configure.sh" --help

# Test install.sh --dry-run with generic provider
TOTAL=$((TOTAL + 1))
DRY_RUN_OUT=$(bash "$SKILL_DIR/scripts/install.sh" --dry-run --provider generic 2>&1) || true
if echo "$DRY_RUN_OUT" | grep -q "DRY RUN"; then
    echo -e "${GREEN}PASS${NC} install.sh dry-run mode works"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} install.sh dry-run mode did not produce expected output"
    FAIL=$((FAIL + 1))
fi

# Test configure.sh --dry-run
TOTAL=$((TOTAL + 1))
DRY_RUN_OUT=$(bash "$SKILL_DIR/scripts/configure.sh" --dry-run --provider generic 2>&1) || true
if echo "$DRY_RUN_OUT" | grep -q "DRY RUN"; then
    echo -e "${GREEN}PASS${NC} configure.sh dry-run mode works"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} configure.sh dry-run mode did not produce expected output"
    FAIL=$((FAIL + 1))
fi

echo ""

# ----------------------------------------
# Test Group 6: Configure Script Output
# ----------------------------------------
echo "--- Configuration Generation Tests ---"

# Run configure.sh with generic provider (no cloud metadata needed)
CONFIG_OUT="/tmp/openclaw-test-config-$$.yaml"
TOTAL=$((TOTAL + 1))
set +e
CONFIGURE_OUTPUT=$(bash "$SKILL_DIR/scripts/configure.sh" --provider generic --output "$CONFIG_OUT" 2>&1)
set -e
if echo "$CONFIGURE_OUTPUT" | grep -q "Configuration Complete"; then
    echo -e "${GREEN}PASS${NC} configure.sh generates config successfully"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} configure.sh did not complete successfully"
    FAIL=$((FAIL + 1))
fi

assert_file_exists "Generated config file exists" "$CONFIG_OUT"

# Validate generated config content
if [[ -f "$CONFIG_OUT" ]]; then
    CONFIG_CONTENT=$(cat "$CONFIG_OUT")
    assert_contains "Config has openclaw section" "openclaw:" "$CONFIG_CONTENT"
    assert_contains "Config has server section" "server:" "$CONFIG_CONTENT"
    assert_contains "Config has resources section" "resources:" "$CONFIG_CONTENT"
    assert_contains "Config has security section" "security:" "$CONFIG_CONTENT"
    assert_contains "Config has cloud section" "cloud:" "$CONFIG_CONTENT"
    assert_contains "Config has provider set to generic" "provider: generic" "$CONFIG_CONTENT"
fi

# Cleanup
rm -f "$CONFIG_OUT"

echo ""

# ----------------------------------------
# Test Group 7: Config Template Validation
# ----------------------------------------
echo "--- Config Template Tests ---"

TEMPLATE_CONTENT=$(cat "$SKILL_DIR/assets/config-template.yaml")
assert_contains "Template has openclaw section" "openclaw:" "$TEMPLATE_CONTENT"
assert_contains "Template has server port" "port: 8080" "$TEMPLATE_CONTENT"
assert_contains "Template has auto workers" "workers: auto" "$TEMPLATE_CONTENT"

echo ""

# ----------------------------------------
# Test Group 8: Example Deployment JSON
# ----------------------------------------
echo "--- Example Deployment Tests ---"

if command -v jq &>/dev/null; then
    TOTAL=$((TOTAL + 1))
    if jq empty "$SKILL_DIR/assets/example-deployment.json" 2>/dev/null; then
        echo -e "${GREEN}PASS${NC} example-deployment.json is valid JSON"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} example-deployment.json is invalid JSON"
        FAIL=$((FAIL + 1))
    fi

    DEPLOY_PROVIDER=$(jq -r '.deployment.provider' "$SKILL_DIR/assets/example-deployment.json")
    assert_eq "Deployment provider is aws" "aws" "$DEPLOY_PROVIDER"
fi

echo ""

# ----------------------------------------
# Summary
# ----------------------------------------
echo "======================================"
echo " Test Results"
echo "======================================"
echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${RED}Failed:${NC}  $FAIL"
echo "  Total:   $TOTAL"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}ALL TESTS PASSED${NC}"
    exit 0
else
    echo -e "${RED}$FAIL TEST(S) FAILED${NC}"
    exit 1
fi
