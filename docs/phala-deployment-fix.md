# Phala Deployment Fix: Node-Specific Services

## Problem

The original `docker-compose.phala.yml` configuration was deploying **both** nginx-server and test-client services on **every node**. This violated the MVP specification which requires:

- **Node 1**: Run nginx server
- **Node 2**: Run test client

## Solution

### 1. Docker Compose Profiles

Added Docker Compose profiles to conditionally start services:

```yaml
# nginx-server (only on node-1)
nginx-server:
  profiles:
    - node-1

# test-client (only on node-2)  
test-client:
  profiles:
    - node-2
```

### 2. Deployment Script Updates

Modified `scripts/deploy-phala.sh` to use the appropriate profile:

```bash
# Use the appropriate profile based on node ID
local profile_arg=""
if [[ "$node_id" == "node-1" ]]; then
    profile_arg="--profile node-1"
    print_status "Deploying with profile: node-1 (nginx server)"
elif [[ "$node_id" == "node-2" ]]; then
    profile_arg="--profile node-2"
    print_status "Deploying with profile: node-2 (test client)"
fi

npx phala cvms create \
    --name "$deployment_name" \
    --compose "$DOCKER_COMPOSE_FILE" \
    $profile_arg \
    # ... other args
```

### 3. Enhanced Nginx Configuration

Created a custom nginx configuration (`docker/nginx/nginx.conf`) that:

- Serves a hello world page identifying the node
- Provides health check endpoints
- Shows node information and role

### 4. Improved Test Client

Updated the test client to:

- Identify itself as node-2 (client node)
- Test connectivity to node-1 (server node) at `10.0.0.1:80`
- Provide clear feedback about the test results

## Result

Now when deploying to Phala Cloud:

- **Node 1** will run: wireguard-vpn, mullvad-proxy, nginx-server
- **Node 2** will run: wireguard-vpn, mullvad-proxy, test-client

This matches the MVP specification exactly.

## Testing

Use the new test script to verify the deployment:

```bash
./scripts/test-phala-deployment.sh test
```

This will check that each CVM has the correct services running based on its node ID. 