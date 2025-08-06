const DstackContractClient = require('./contract-client');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

class PeerRegistry {
    constructor(options = {}) {
        this.options = {
            configPath: options.configPath || path.join(__dirname, '../config/peer-registry-v2.json'),
            network: options.network || 'base',
            privateKey: options.privateKey || process.env.PRIVATE_KEY,
            autoSync: options.autoSync !== false, // Default to true
            syncInterval: options.syncInterval || 60000, // 1 minute
            logLevel: options.logLevel || 'info',
            ...options
        };

        // Initialize contract client
        this.contractClient = new DstackContractClient(
            this.options.network,
            this.options.privateKey
        );

        // Registry data structure
        this.registry = this.loadRegistry();

        // Sync state
        this.syncState = {
            lastSync: null,
            syncInProgress: false,
            syncErrors: 0,
            lastError: null
        };

        // Event listeners
        this.eventListeners = new Map();
        this.setupEventListeners();

        // Auto-sync timer
        if (this.options.autoSync) {
            this.startAutoSync();
        }

        this.log('info', 'PeerRegistry initialized', {
            configPath: this.options.configPath,
            network: this.options.network,
            autoSync: this.options.autoSync,
            syncInterval: this.options.syncInterval
        });
    }

    /**
     * Load registry from file
     * @returns {Object} Registry data
     */
    loadRegistry() {
        try {
            if (fs.existsSync(this.options.configPath)) {
                const data = fs.readFileSync(this.options.configPath, 'utf8');
                const registry = JSON.parse(data);
                
                // Validate registry structure
                if (this.validateRegistry(registry)) {
                    this.log('info', 'Registry loaded from file', {
                        peers: registry.peers?.length || 0,
                        version: registry.version
                    });
                    return registry;
                } else {
                    this.log('warn', 'Invalid registry structure, creating new one');
                }
            }
        } catch (error) {
            this.log('error', 'Error loading registry', { error: error.message });
        }

        // Create new registry if file doesn't exist or is invalid
        return this.createNewRegistry();
    }

    /**
     * Create new registry structure
     * @returns {Object} New registry
     */
    createNewRegistry() {
        const registry = {
            peers: [],
            contract_address: this.contractClient.networkConfig.contractAddress,
            network: {
                cidr: "10.0.0.0/24",
                dns_server: "10.0.0.1"
            },
            last_sync: null,
            version: "2.0",
            created_at: new Date().toISOString()
        };

        this.saveRegistry(registry);
        this.log('info', 'New registry created');
        return registry;
    }

    /**
     * Validate registry structure
     * @param {Object} registry - Registry to validate
     * @returns {boolean} Validation result
     */
    validateRegistry(registry) {
        return registry &&
               typeof registry === 'object' &&
               Array.isArray(registry.peers) &&
               registry.contract_address &&
               registry.network &&
               registry.version;
    }

    /**
     * Save registry to file
     * @param {Object} registry - Registry to save
     */
    saveRegistry(registry) {
        try {
            // Ensure directory exists
            const dir = path.dirname(this.options.configPath);
            if (!fs.existsSync(dir)) {
                fs.mkdirSync(dir, { recursive: true });
            }

            // Save with pretty formatting
            fs.writeFileSync(this.options.configPath, JSON.stringify(registry, null, 2));
            this.log('debug', 'Registry saved to file');
        } catch (error) {
            this.log('error', 'Error saving registry', { error: error.message });
            throw error;
        }
    }

    /**
     * Sync registry with contract
     * @param {boolean} force - Force sync even if in progress
     * @returns {Promise<Object>} Sync result
     */
    async syncWithContract(force = false) {
        if (this.syncState.syncInProgress && !force) {
            this.log('warn', 'Sync already in progress, skipping');
            return { status: 'skipped', reason: 'sync_in_progress' };
        }

        this.syncState.syncInProgress = true;
        const startTime = Date.now();

        try {
            this.log('info', 'Starting registry sync with contract');

            // Get all registered nodes from contract
            const contractPeers = await this.getAllContractPeers();
            
            // Update registry with contract data
            const updatedRegistry = {
                ...this.registry,
                peers: contractPeers,
                last_sync: new Date().toISOString(),
                contract_address: this.contractClient.networkConfig.contractAddress
            };

            // Save updated registry
            this.registry = updatedRegistry;
            this.saveRegistry(updatedRegistry);

            // Update sync state
            this.syncState.lastSync = new Date().toISOString();
            this.syncState.syncErrors = 0;
            this.syncState.lastError = null;

            const syncTime = Date.now() - startTime;
            this.log('info', 'Registry sync completed', {
                peers: contractPeers.length,
                syncTime: `${syncTime}ms`
            });

            return {
                status: 'success',
                peers: contractPeers.length,
                syncTime,
                timestamp: new Date().toISOString()
            };

        } catch (error) {
            this.syncState.syncErrors++;
            this.syncState.lastError = error.message;

            this.log('error', 'Registry sync failed', {
                error: error.message,
                syncErrors: this.syncState.syncErrors
            });

            return {
                status: 'error',
                error: error.message,
                syncErrors: this.syncState.syncErrors,
                timestamp: new Date().toISOString()
            };

        } finally {
            this.syncState.syncInProgress = false;
        }
    }

    /**
     * Get all peers from contract
     * @returns {Promise<Array>} Array of peer objects
     */
    async getAllContractPeers() {
        const peers = [];
        
        try {
            // Get total supply or iterate through known tokens
            // For now, we'll use a reasonable range and filter out invalid tokens
            const maxTokens = 1000; // Reasonable upper limit
            
            for (let tokenId = 1; tokenId <= maxTokens; tokenId++) {
                try {
                    const nodeAccess = await this.contractClient.getNodeAccess(tokenId);
                    
                    if (nodeAccess && nodeAccess.nodeId && nodeAccess.isActive) {
                        // Get owner address
                        const ownerAddress = await this.contractClient.contract.ownerOf(tokenId);
                        
                        // Generate IP address based on token ID
                        const ipAddress = this.generateIPAddress(tokenId);
                        
                        const peer = {
                            node_id: nodeAccess.nodeId,
                            public_key: nodeAccess.wireguardPublicKey,
                            ip_address: ipAddress,
                            hostname: `${nodeAccess.nodeId}.vpn.dstack`,
                            instance_id: `dstack-${nodeAccess.nodeId}`,
                            nft_owner: ownerAddress,
                            access_granted: nodeAccess.isActive,
                            token_id: tokenId,
                            last_verified: new Date().toISOString(),
                            status: nodeAccess.isActive ? 'active' : 'inactive',
                            created_at: new Date(parseInt(nodeAccess.createdAt) * 1000).toISOString()
                        };
                        
                        peers.push(peer);
                    }
                } catch (error) {
                    // Token doesn't exist or other error, continue to next
                    if (error.message.includes('ERC721: invalid token ID')) {
                        // Token doesn't exist, continue
                        continue;
                    }
                    
                    // Log other errors but continue
                    this.log('warn', `Error getting token ${tokenId}`, { error: error.message });
                }
            }
            
        } catch (error) {
            this.log('error', 'Error getting contract peers', { error: error.message });
            throw error;
        }

        return peers;
    }

    /**
     * Generate IP address for token ID
     * @param {number} tokenId - Token ID
     * @returns {string} IP address
     */
    generateIPAddress(tokenId) {
        // Use token ID to generate deterministic IP address
        // Base: 10.0.0.0/24, so we can use 10.0.0.1 to 10.0.0.254
        const baseIP = 1; // Start from 10.0.0.1
        const ipOctet = baseIP + (tokenId % 254);
        return `10.0.0.${ipOctet}`;
    }

    /**
     * Get peer by node ID
     * @param {string} nodeId - Node identifier
     * @returns {Object|null} Peer object or null
     */
    getPeerByNodeId(nodeId) {
        return this.registry.peers.find(peer => peer.node_id === nodeId) || null;
    }

    /**
     * Get peer by public key
     * @param {string} publicKey - WireGuard public key
     * @returns {Object|null} Peer object or null
     */
    getPeerByPublicKey(publicKey) {
        return this.registry.peers.find(peer => peer.public_key === publicKey) || null;
    }

    /**
     * Get peer by IP address
     * @param {string} ipAddress - IP address
     * @returns {Object|null} Peer object or null
     */
    getPeerByIP(ipAddress) {
        return this.registry.peers.find(peer => peer.ip_address === ipAddress) || null;
    }

    /**
     * Get all active peers
     * @returns {Array} Array of active peers
     */
    getActivePeers() {
        return this.registry.peers.filter(peer => peer.status === 'active');
    }

    /**
     * Get all peers owned by address
     * @param {string} ownerAddress - Owner address
     * @returns {Array} Array of peers owned by address
     */
    getPeersByOwner(ownerAddress) {
        return this.registry.peers.filter(peer => 
            peer.nft_owner.toLowerCase() === ownerAddress.toLowerCase()
        );
    }

    /**
     * Generate WireGuard configuration
     * @param {string} nodeId - Current node ID
     * @param {string} privateKey - Current node's private key
     * @param {string} listenPort - Listen port (default: 51820)
     * @returns {Object} WireGuard configuration
     */
    generateWireGuardConfig(nodeId, privateKey, listenPort = 51820) {
        const currentNode = this.getPeerByNodeId(nodeId);
        if (!currentNode) {
            throw new Error(`Node ${nodeId} not found in registry`);
        }

        // Generate interface configuration
        const interfaceConfig = {
            PrivateKey: privateKey,
            Address: `${currentNode.ip_address}/24`,
            ListenPort: listenPort,
            PostUp: [
                'iptables -A FORWARD -i %i -j ACCEPT',
                'iptables -A FORWARD -o %i -j ACCEPT',
                'iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE'
            ].join('; '),
            PostDown: [
                'iptables -D FORWARD -i %i -j ACCEPT',
                'iptables -D FORWARD -o %i -j ACCEPT',
                'iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE'
            ].join('; ')
        };

        // Generate peer configurations
        const peers = this.registry.peers
            .filter(peer => peer.node_id !== nodeId && peer.status === 'active')
            .map(peer => ({
                PublicKey: peer.public_key,
                AllowedIPs: `${peer.ip_address}/32`,
                Endpoint: `${peer.hostname}:${listenPort}`,
                PersistentKeepalive: 25
            }));

        return {
            interface: interfaceConfig,
            peers: peers,
            metadata: {
                nodeId,
                totalPeers: peers.length,
                generatedAt: new Date().toISOString(),
                registryVersion: this.registry.version
            }
        };
    }

    /**
     * Start auto-sync timer
     */
    startAutoSync() {
        if (this.autoSyncTimer) {
            clearInterval(this.autoSyncTimer);
        }

        this.autoSyncTimer = setInterval(async () => {
            try {
                await this.syncWithContract();
            } catch (error) {
                this.log('error', 'Auto-sync failed', { error: error.message });
            }
        }, this.options.syncInterval);

        this.log('info', 'Auto-sync started', { interval: this.options.syncInterval });
    }

    /**
     * Stop auto-sync timer
     */
    stopAutoSync() {
        if (this.autoSyncTimer) {
            clearInterval(this.autoSyncTimer);
            this.autoSyncTimer = null;
            this.log('info', 'Auto-sync stopped');
        }
    }

    /**
     * Setup contract event listeners
     */
    setupEventListeners() {
        // Listen for access granted events
        this.contractClient.listenToNodeAccessGranted((event) => {
            this.log('info', 'Node access granted event', event);
            // Trigger sync after a short delay to allow contract to update
            setTimeout(() => this.syncWithContract(), 5000);
        });

        // Listen for access revoked events
        this.contractClient.listenToNodeAccessRevoked((event) => {
            this.log('info', 'Node access revoked event', event);
            // Trigger sync after a short delay
            setTimeout(() => this.syncWithContract(), 5000);
        });

        // Listen for access transferred events
        this.contractClient.listenToNodeAccessTransferred((event) => {
            this.log('info', 'Node access transferred event', event);
            // Trigger sync after a short delay
            setTimeout(() => this.syncWithContract(), 5000);
        });
    }

    /**
     * Get registry statistics
     * @returns {Object} Registry statistics
     */
    getStats() {
        const activePeers = this.getActivePeers();
        const inactivePeers = this.registry.peers.filter(peer => peer.status === 'inactive');

        return {
            totalPeers: this.registry.peers.length,
            activePeers: activePeers.length,
            inactivePeers: inactivePeers.length,
            syncState: {
                lastSync: this.syncState.lastSync,
                syncInProgress: this.syncState.syncInProgress,
                syncErrors: this.syncState.syncErrors,
                lastError: this.syncState.lastError
            },
            registry: {
                version: this.registry.version,
                contractAddress: this.registry.contract_address,
                network: this.registry.network
            },
            timestamp: new Date().toISOString()
        };
    }

    /**
     * Health check for the registry
     * @returns {Promise<Object>} Health status
     */
    async healthCheck() {
        try {
            const contractHealth = await this.contractClient.healthCheck();
            const stats = this.getStats();
            
            return {
                status: contractHealth.status === 'healthy' ? 'healthy' : 'degraded',
                contract: contractHealth,
                registry: stats,
                timestamp: new Date().toISOString()
            };
        } catch (error) {
            return {
                status: 'unhealthy',
                error: error.message,
                timestamp: new Date().toISOString()
            };
        }
    }

    /**
     * Log message with appropriate level
     */
    log(level, message, data = {}) {
        const levels = {
            error: 0,
            warn: 1,
            info: 2,
            debug: 3
        };

        const currentLevel = levels[this.options.logLevel] || 2;
        const messageLevel = levels[level] || 2;

        if (messageLevel <= currentLevel) {
            const timestamp = new Date().toISOString();
            const logEntry = {
                timestamp,
                level: level.toUpperCase(),
                component: 'PeerRegistry',
                message,
                ...data
            };

            if (level === 'error') {
                console.error(JSON.stringify(logEntry));
            } else if (level === 'warn') {
                console.warn(JSON.stringify(logEntry));
            } else if (level === 'info') {
                console.log(JSON.stringify(logEntry));
            } else if (level === 'debug') {
                console.debug(JSON.stringify(logEntry));
            }
        }
    }
}

module.exports = PeerRegistry; 