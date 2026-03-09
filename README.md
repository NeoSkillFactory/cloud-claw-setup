# cloud-claw-setup

![Audit](https://img.shields.io/badge/audit%3A%20PASS-brightgreen) ![License](https://img.shields.io/badge/license-MIT-blue) ![OpenClaw](https://img.shields.io/badge/OpenClaw-skill-orange)

> Automatically installs and configures OpenClaw on cloud VMs for AI agent deployment

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

## Configuration

./scripts/configure.sh --config my-config.yaml

## GitHub

Source code: [github.com/NeoSkillFactory/cloud-claw-setup](https://github.com/NeoSkillFactory/cloud-claw-setup)

**Price suggestion:** $29.99 USD

## License

MIT © NeoSkillFactory
