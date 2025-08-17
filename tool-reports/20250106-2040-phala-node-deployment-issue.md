# Phala Node Deployment Issue - Environment Variables Not Set

**Date:** 2025-01-06 20:40  
**Issue:** Phala nodes failing to start due to missing environment variables  
**Status:** 🔴 Critical - Blocking deployment

## Problem Description

During VPN deployment, the Phala nodes are being created but failing to start properly. The logs show:

```
app-compose.sh[747]: time="2025-08-17T17:49:26Z" level=warning msg="The \"HUB_PUBLIC_IP\" variable is not set. Defaulting to a blank string."
app-compose.sh[747]: time="2025-08-17T17:49:26Z" level=warning msg="The \"HUB_PUBLIC_KEY\" variable is not set. Defaulting to a blank string."
app-compose.sh[747]: time="2025-08-17T17:49:26Z" level=warning msg="The \"WIREGUARD_PRIVATE_KEY_A\" variable is not set. Defaulting to a blank string."
```

## Root Cause Analysis

The issue stems from a **design mismatch** between the deployment approach and the Phala CVM system:

1. **Deployment Script Design**: The script is designed to deploy directly to Phala CVMs using SSH and manual configuration
2. **Docker Compose Usage**: The script incorrectly uses `--compose docker-compose.yml` when creating Phala CVMs
3. **Environment Variable Mismatch**: The `docker-compose.yml` expects environment variables that aren't being set
4. **Architecture Confusion**: Mixing Docker Compose deployment with direct CVM deployment

## Current Deployment Flow (Broken)

```
1. Generate WireGuard keys ✅
2. Create DigitalOcean hub ✅  
3. Create Phala CVM with --compose docker-compose.yml ❌
4. CVM tries to use Docker Compose but env vars missing ❌
5. WireGuard fails to start ❌
```

## Expected Deployment Flow

```
1. Generate WireGuard keys ✅
2. Create DigitalOcean hub ✅
3. Create Phala CVM (no compose file) ✅
4. SSH to CVM and configure WireGuard directly ✅
5. Deploy status service directly to CVM ✅
```

## Files Affected

- `scripts/deploy-vpn.sh` - Main deployment script
- `docker-compose.yml` - Not needed for Phala deployment
- `config/nodes/*.conf` - WireGuard configs (working)

## Technical Details

### Phala CVM Creation Command (Current - Broken)
```bash
phala cvms create \
    --name ${NODE_NAME} \
    --teepod-id ${NODE_ID} \
    --image dstack-0.3.6 \
    --vcpu 1 \
    --memory 2048 \
    --disk-size 40 \
    --compose docker-compose.yml \  # ❌ This is wrong
    --skip-env
```

### Phala CVM Creation Command (Correct)
```bash
phala cvms create \
    --name ${NODE_NAME} \
    --teepod-id ${NODE_ID} \
    --image dstack-0.3.6 \
    --vcpu 1 \
    --memory 2048 \
    --disk-size 40
    # No --compose flag needed
```

## Solution Plan

1. **Remove Docker Compose dependency** from Phala CVM creation
2. **Fix CVM creation command** to not use compose files
3. **Ensure direct SSH deployment** works properly
4. **Test end-to-end deployment** without Docker Compose
5. **Update documentation** to reflect correct deployment approach

## Impact Assessment

- **Deployment Status**: Currently blocked
- **Infrastructure**: DigitalOcean hub working, Phala nodes failing
- **User Experience**: Cannot complete VPN setup
- **Cost**: Phala CVMs being created but not functional

## Next Steps

1. Fix the deployment script to remove Docker Compose usage
2. Test Phala CVM creation and direct configuration
3. Verify WireGuard connectivity between hub and nodes
4. Complete the deployment and test VPN functionality

## Files to Modify

- `scripts/deploy-vpn.sh` - Remove `--compose` flag and fix CVM creation
- Consider removing `docker-compose.yml` if not needed for local development

## Testing Required

- Phala CVM creation without compose files
- SSH access to CVMs
- WireGuard configuration deployment
- Status service deployment
- End-to-end VPN connectivity testing
