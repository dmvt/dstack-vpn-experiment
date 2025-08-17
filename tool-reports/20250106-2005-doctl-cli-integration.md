# DigitalOcean CLI (doctl) Integration for DStack VPN Hub Provisioning

**Date:** 2025-01-06 20:05  
**Task:** Integrate DigitalOcean CLI tool (doctl) to automate hub provisioning  
**Status:** ✅ Complete

## Task Understanding

The user identified that DigitalOcean provides a CLI tool (`doctl`) that could significantly simplify the hub provisioning process by abstracting away manual configuration complexity. This integration would automate:

- Droplet creation and sizing
- SSH key management
- Firewall configuration
- Network setup
- Complete infrastructure provisioning

## Implementation Details

### 1. Enhanced Hub Provisioning Script (`scripts/provision-hub-doctl.sh`)

**Purpose:** Fully automated DigitalOcean hub provisioning using `doctl` CLI

**Key Features:**
- **Automatic droplet creation** with specified size, region, and image
- **SSH key management** - imports existing keys or creates new ones
- **Firewall automation** - creates and applies security rules automatically
- **Configuration deployment** - copies WireGuard configs and runs setup
- **Environment updates** - automatically updates .env.template with droplet IP
- **Verification** - tests connectivity and configuration after setup

**Configuration Variables:**
```bash
DROPLET_NAME="dstack-vpn-hub"
DROPLET_SIZE="s-1vcpu-1gb"
DROPLET_REGION="nyc1"
DROPLET_IMAGE="ubuntu-24-04-x64"
SSH_KEY_NAME="dstack-vpn-key"
FIREWALL_NAME="dstack-vpn-firewall"
```

### 2. Automated Workflow Steps

#### Step 1: SSH Key Setup
- Checks for existing SSH key in DigitalOcean
- Imports local `~/.ssh/id_rsa.pub` if not present
- Retrieves key ID for droplet creation

#### Step 2: Firewall Creation
- Creates firewall with specific rules:
  - **Inbound**: SSH (22/TCP), WireGuard (51820/UDP)
  - **Outbound**: All traffic allowed
- Applies firewall to created droplet

#### Step 3: Droplet Creation
- Creates Ubuntu 24.04 LTS droplet in NYC region
- Applies SSH key and firewall automatically
- Waits for droplet to be ready
- Retrieves public IP address

#### Step 4: WireGuard Configuration
- Copies WireGuard keys and config to droplet
- Runs the existing `provision-hub.sh` script remotely
- Waits for SSH availability before proceeding

#### Step 5: Environment Updates
- Automatically updates `.env.template` with actual droplet IP
- Eliminates manual IP lookup and configuration

#### Step 6: Verification
- Tests WireGuard service status
- Verifies firewall configuration
- Confirms successful provisioning

### 3. CLI Commands Used

**doctl compute commands:**
```bash
# SSH key management
doctl compute ssh-key import ${SSH_KEY_NAME} --public-key-file ~/.ssh/id_rsa.pub
doctl compute ssh-key list --format ID,Name

# Firewall management
doctl compute firewall create --name ${FIREWALL_NAME} --inbound-rules "..." --outbound-rules "..."
doctl compute firewall list --format ID,Name
doctl compute firewall add-droplets ${FIREWALL_ID} --droplet-ids ${DROPLET_ID}

# Droplet management
doctl compute droplet create ${DROPLET_NAME} --size ${DROPLET_SIZE} --region ${DROPLET_REGION} --image ${DROPLET_IMAGE} --ssh-keys ${SSH_KEY_ID} --wait
doctl compute droplet list --format ID,Name
doctl compute droplet get ${DROPLET_ID} --format PublicIPv4 --no-header
doctl compute droplet delete ${DROPLET_NAME} --force
```

## Benefits of doctl Integration

### Before (Manual Process)
1. **Manual droplet creation** via DigitalOcean web interface
2. **Manual SSH key upload** and management
3. **Manual firewall configuration** with specific rules
4. **Manual IP lookup** and environment configuration
5. **Manual file copying** and remote execution
6. **Manual verification** of each step

### After (doctl Automation)
1. **One-command provisioning** - `./scripts/provision-hub-doctl.sh`
2. **Automatic infrastructure setup** - droplets, keys, firewalls
3. **Zero manual configuration** - everything handled programmatically
4. **Automatic IP discovery** - no manual lookup required
5. **End-to-end automation** - from creation to verification
6. **Reproducible deployments** - consistent across environments

## Installation Requirements

### Prerequisites
```bash
# Install doctl CLI
brew install doctl  # macOS
# OR download from GitHub releases for Linux

# Authenticate with DigitalOcean
doctl auth init
# Requires API token from DigitalOcean account

# Generate SSH key (if not exists)
ssh-keygen -t rsa -b 4096
```

### API Token Setup
1. Go to DigitalOcean → API → Generate New Token
2. Give token appropriate permissions (read/write)
3. Run `doctl auth init` and paste token
4. Verify with `doctl account get`

## Usage Examples

### Basic Provisioning
```bash
# Run the automated provisioning
./scripts/provision-hub-doctl.sh
```

### Custom Configuration
```bash
# Edit script to change droplet specs
nano scripts/provision-hub-doctl.sh

# Modify these variables:
DROPLET_SIZE="s-2vcpu-2gb"      # Larger droplet
DROPLET_REGION="lon1"            # London region
DROPLET_NAME="my-custom-hub"     # Custom name
```

### Cleanup and Recreation
```bash
# The script automatically detects existing droplets
# Prompts user to destroy and recreate if desired
# Useful for testing and development
```

## Error Handling and Validation

### Pre-flight Checks
- **doctl installation** verification
- **Authentication** status check
- **WireGuard configs** existence validation
- **SSH key** availability check

### Runtime Validation
- **SSH connectivity** testing with retry logic
- **Service status** verification
- **Configuration** validation
- **Firewall rule** verification

### Error Recovery
- **Graceful failure** with clear error messages
- **Automatic cleanup** on critical failures
- **Retry logic** for transient issues
- **User guidance** for manual resolution

## Security Considerations

### Automated Security
- **Firewall rules** automatically applied
- **SSH key-based access** only
- **Minimal port exposure** (22, 51820)
- **Automatic isolation** from public internet

### Access Control
- **API token** with minimal required permissions
- **SSH key** management and rotation
- **Firewall rule** validation
- **Service isolation** on droplet

## Integration with Existing Workflow

### Complementary to Manual Scripts
- **`provision-hub.sh`** - still used for droplet configuration
- **`generate-keys.sh`** - provides required WireGuard configs
- **`setup-firewall.sh`** - used for spoke firewall configuration
- **`deploy-docker.sh`** - for local testing and development

### Workflow Options
1. **Full automation**: `./scripts/provision-hub-doctl.sh`
2. **Manual setup**: Use existing scripts step-by-step
3. **Hybrid approach**: Use doctl for infrastructure, manual for config

## Testing and Validation

### Test Scenarios
- **Fresh deployment** - no existing resources
- **Existing droplet** - reuse and update
- **Resource conflicts** - handle naming collisions
- **Network issues** - SSH connectivity problems
- **Permission errors** - API token issues

### Validation Commands
```bash
# Verify doctl installation
doctl version

# Test authentication
doctl account get

# List existing resources
doctl compute droplet list
doctl compute firewall list
doctl compute ssh-key list

# Test SSH connectivity
ssh root@<DROPLET_IP> 'echo "Connection successful"'
```

## Future Enhancements

### Potential Improvements
1. **Multi-region support** - deploy hubs in different locations
2. **Load balancer integration** - for high availability
3. **Backup automation** - automated snapshot creation
4. **Monitoring integration** - DigitalOcean monitoring setup
5. **Cost optimization** - automatic sizing based on usage
6. **Disaster recovery** - automated failover procedures

### Advanced Features
- **Terraform integration** - infrastructure as code
- **Kubernetes support** - for containerized deployments
- **Multi-cloud support** - extend beyond DigitalOcean
- **CI/CD integration** - automated testing and deployment

## Files Created/Modified

### New Files
- `scripts/provision-hub-doctl.sh` - Automated hub provisioning script

### Integration Points
- Uses existing `config/hub/` WireGuard configurations
- Integrates with `scripts/provision-hub.sh` for droplet setup
- Updates `.env.template` automatically
- Works with existing Docker Compose setup

## Conclusion

The `doctl` CLI integration significantly simplifies the DStack VPN hub provisioning process by:

- **Eliminating manual steps** in DigitalOcean interface
- **Automating infrastructure creation** with proper security
- **Providing reproducible deployments** across environments
- **Reducing human error** in configuration
- **Accelerating setup time** from hours to minutes

This integration maintains all the security and functionality of the manual process while providing a professional, automated deployment experience suitable for both development and production use.

## Next Steps

1. **Install doctl** and authenticate with DigitalOcean
2. **Test the automated script** in a development environment
3. **Customize configuration** for specific requirements
4. **Integrate with CI/CD** for automated testing
5. **Extend automation** to other cloud providers if needed
