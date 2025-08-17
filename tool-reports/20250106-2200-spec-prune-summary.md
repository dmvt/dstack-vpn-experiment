# Spec-Driven Prune Summary

**Date**: 2025-01-06 22:00  
**Operation**: Repository cleanup based on SPEC.md requirements  
**Goal**: Remove out-of-scope code to provide blank slate for rewrite

## Allowed Surface (Authoritative)

Based on SPEC.md analysis, the following components are in-scope:

**Core Components:**
- **WireGuard** (`wg`/`wg-quick`) on all nodes
- **Firewall** (nftables/UFW) with specific rules
- **PostgreSQL cluster** running on Dstack spokes only
- **Status service** (Go binary on :8000) for spokes
- **Basic networking** (L3 forwarding between spokes via hub)

**Infrastructure:**
- **DigitalOcean hub** (NYC droplet) - WireGuard server only
- **3 Dstack spokes** - WireGuard clients + PostgreSQL
- **Addressing**: `10.88.0.0/24` overlay network

**Files/Patterns to Keep:**
- `SPEC.md` (never touch)
- `docker/wireguard/` (for WireGuard containers)
- `scripts/` (for deployment and key generation)
- Basic project structure files

## Files Removed

**Source Code (5 files):**
- `src/wireguard-contract-bridge.js` - Contract integration (out of scope)
- `src/access-control.js` - NFT access control (out of scope)
- `src/config-manager.js` - Contract config (out of scope)
- `src/peer-registry.js` - Contract registry (out of scope)
- `src/contract-client.js` - Blockchain client (out of scope)

**Smart Contracts (1 file):**
- `contracts/interfaces/IDstackAccessNFT.sol` - NFT contract (out of scope)

**Tests (6 files):**
- `test/integration-layer.test.js` - Contract integration tests
- `test/hardhat-integration.test.js` - Hardhat tests
- `test/setup.js` - Test setup
- `__tests__/access-control.test.js` - Access control tests
- `__tests__/contract-client.test.js` - Contract client tests
- `__tests__/node-registrar.test.js` - Node registrar tests

**Configuration (2 files):**
- `hardhat.config.js` - Hardhat configuration
- `jest.config.js` - Jest configuration

**Dependencies (2 files):**
- `package.json` - Blockchain dependencies (replaced with minimal version)
- `package-lock.json` - Lock file (regenerated)

**NFT Assets (5 files):**
- `nft-metadata/images/node-1.svg` - NFT image
- `nft-metadata/images/node-2.svg` - NFT image
- `nft-metadata/node-1.json` - NFT metadata
- `nft-metadata/node-2.json` - NFT metadata
- `nft-metadata/README.md` - NFT documentation

**Scripts (2 files):**
- `scripts/register-node.js` - Contract-based node registration
- `scripts/test-contract-integration.js` - Contract testing

**Docker Components (2 directories):**
- `docker/mullvad-proxy/` - Mullvad proxy (not in spec)
- `docker/monitoring/` - Monitoring (not in spec)

**Build Artifacts (4 directories):**
- `node_modules/` - Dependencies
- `coverage/` - Test coverage
- `cache/` - Hardhat cache
- `artifacts/` - Hardhat artifacts

**Total Files Removed**: 29 files + 6 directories

## Files Kept

```
dstack-vpn-experiment/
├── SPEC.md                    # Core specification (never touch)
├── .gitignore                # Git ignore rules
├── README.md                 # Project documentation
├── package.json              # Minimal package.json (regenerated)
├── env.example               # Environment template
├── docker-compose.yml        # Docker composition
├── docker/
│   └── wireguard/           # WireGuard containers (in scope)
├── scripts/
│   ├── deploy-docker.sh     # Deployment script (in scope)
│   └── generate-keys.sh     # Key generation (in scope)
├── tool-reports/             # Documentation
├── docs/                     # Documentation
├── config/                   # Configuration
└── .obsidian/                # Obsidian workspace
```

## Follow-ups (Gaps vs. Spec)

**Missing Components Identified:**
1. **Status Service**: Go binary for `:8000` endpoint (specified in Appendix A)
2. **Firewall Rules**: nftables configurations for hub and spokes
3. **PostgreSQL Setup**: Cluster configuration for Dstack spokes
4. **Hub Provisioning**: DigitalOcean droplet setup scripts
5. **Spoke Join Scripts**: Individual spoke configuration scripts

**Spec Requirements Not Yet Implemented:**
- WireGuard hub on DigitalOcean NYC
- 3 Dstack spokes with PostgreSQL
- L3 forwarding between spokes
- Split-horizon DNS (optional)
- Local backup jobs on spokes

## Next Steps for Rewrite

1. **Phase 1: Core Infrastructure**
   - Implement WireGuard hub provisioning (DigitalOcean)
   - Create spoke join scripts with proper addressing
   - Set up basic L3 forwarding

2. **Phase 2: Database Layer**
   - Configure PostgreSQL cluster on Dstack spokes
   - Implement local backup jobs
   - Set up replication

3. **Phase 3: Monitoring & Status**
   - Build Go status service (spec Appendix A)
   - Implement firewall rules (nftables)
   - Add health checks

4. **Phase 4: Testing & Validation**
   - Verify inter-spoke communication
   - Test PostgreSQL connectivity
   - Validate security isolation

## Build Status

**Current State**: Clean slate with minimal dependencies
**Build Artifacts**: All removed
**Dependencies**: Minimal package.json with only deployment scripts
**Test Suite**: Removed (contract tests out of scope)

The repository is now ready for implementing the core WireGuard VPN functionality as specified in SPEC.md, with all blockchain/NFT components removed.
