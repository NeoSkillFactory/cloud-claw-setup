# Security Reference

## Network Security

### Firewall Rules
Configure the VM firewall to allow only necessary traffic:

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| 22 | TCP | Inbound | SSH access (restrict to known IPs) |
| 8080 | TCP | Inbound | OpenClaw API (internal only by default) |
| 443 | TCP | Outbound | HTTPS for API calls and updates |
| 80 | TCP | Outbound | HTTP for package downloads |

### Recommended iptables Rules
```bash
# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow SSH from specific IPs
iptables -A INPUT -p tcp --dport 22 -s YOUR_IP/32 -j ACCEPT

# Allow OpenClaw API on localhost and VPC
iptables -A INPUT -p tcp --dport 8080 -s 10.0.0.0/8 -j ACCEPT
iptables -A INPUT -p tcp --dport 8080 -i lo -j ACCEPT

# Drop all other inbound
iptables -A INPUT -j DROP
```

### Cloud Provider Security Groups

#### AWS Security Group
```json
{
  "SecurityGroupRules": [
    {"IpProtocol": "tcp", "FromPort": 22, "ToPort": 22, "CidrIp": "YOUR_IP/32"},
    {"IpProtocol": "tcp", "FromPort": 8080, "ToPort": 8080, "CidrIp": "10.0.0.0/8"}
  ]
}
```

#### GCP Firewall Rules
```bash
gcloud compute firewall-rules create openclaw-ssh --allow tcp:22 --source-ranges YOUR_IP/32
gcloud compute firewall-rules create openclaw-api --allow tcp:8080 --source-ranges 10.0.0.0/8
```

#### Azure NSG Rules
```bash
az network nsg rule create --name AllowSSH --nsg-name openclaw-nsg --priority 100 \
  --access Allow --protocol Tcp --destination-port-ranges 22 --source-address-prefixes YOUR_IP/32
az network nsg rule create --name AllowAPI --nsg-name openclaw-nsg --priority 200 \
  --access Allow --protocol Tcp --destination-port-ranges 8080 --source-address-prefixes 10.0.0.0/8
```

## Authentication & Secrets

### API Key Management
- Generate strong API keys (minimum 32 characters)
- Store API keys in cloud provider secret managers:
  - AWS: Secrets Manager or Parameter Store
  - GCP: Secret Manager
  - Azure: Key Vault
- Never commit API keys to version control
- Rotate keys regularly (recommended: every 90 days)

### TLS Configuration
- Always enable TLS for production deployments
- Use certificates from trusted CAs (Let's Encrypt recommended)
- Minimum TLS version: 1.2
- Recommended cipher suites: ECDHE-RSA-AES256-GCM-SHA384, ECDHE-RSA-AES128-GCM-SHA256

## Instance Security

### IMDSv2 (AWS)
Always use IMDSv2 (token-based) instead of IMDSv1:
```bash
# Enforce IMDSv2
aws ec2 modify-instance-metadata-options --instance-id i-xxx --http-tokens required
```

### OS Hardening
- Keep packages updated: `apt-get update && apt-get upgrade`
- Enable automatic security updates
- Disable root SSH login
- Use SSH key authentication only (no password auth)
- Run OpenClaw as a non-root user

### File Permissions
```bash
# Config files: readable by openclaw user only
chmod 600 /etc/openclaw/config.yaml
chown openclaw:openclaw /etc/openclaw/config.yaml

# Log directory: writable by openclaw user
chmod 750 /var/log/openclaw
chown openclaw:openclaw /var/log/openclaw

# Data directory: writable by openclaw user
chmod 750 /var/lib/openclaw
chown openclaw:openclaw /var/lib/openclaw
```

## Rate Limiting

### Default Configuration
- 60 requests per minute per API key
- 10 concurrent agent sessions
- 100 MB max request body size

### Recommendations
- Adjust rate limits based on VM size and workload
- Monitor rate limit hits via logging
- Use cloud provider WAF/DDoS protection for public-facing deployments
