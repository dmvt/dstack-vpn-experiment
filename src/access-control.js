const DstackContractClient = require('./contract-client');
const fs = require('fs');
const path = require('path');

class AccessControlMiddleware {
    constructor(options = {}) {
        this.options = {
            network: options.network || 'base',
            privateKey: options.privateKey || process.env.PRIVATE_KEY,
            cacheTimeout: options.cacheTimeout || 30000, // 30 seconds
            maxCacheSize: options.maxCacheSize || 1000,
            logLevel: options.logLevel || 'info',
            ...options
        };

        // Initialize contract client
        this.contractClient = new DstackContractClient(
            this.options.network,
            this.options.privateKey
        );

        // Access cache for performance
        this.accessCache = new Map();
        this.cacheHits = 0;
        this.cacheMisses = 0;

        // Statistics tracking
        this.stats = {
            totalRequests: 0,
            grantedAccess: 0,
            deniedAccess: 0,
            errors: 0,
            lastReset: new Date().toISOString()
        };

        // Event listeners for real-time updates
        this.eventListeners = new Map();
        this.setupEventListeners();

        this.log('info', 'AccessControlMiddleware initialized', {
            network: this.options.network,
            cacheTimeout: this.options.cacheTimeout,
            logLevel: this.options.logLevel
        });
    }

    /**
     * Verify access for a public key and node ID
     * @param {string} publicKey - WireGuard public key
     * @param {string} nodeId - Node identifier
     * @param {Object} options - Additional options
     * @returns {Promise<Object>} Access verification result
     */
    async verifyAccess(publicKey, nodeId, options = {}) {
        const startTime = Date.now();
        this.stats.totalRequests++;

        try {
            this.log('debug', 'Access verification request', {
                publicKey: this.maskPublicKey(publicKey),
                nodeId,
                options
            });

            // Check cache first
            const cacheKey = this.getCacheKey(publicKey, nodeId);
            const cachedResult = this.getFromCache(cacheKey);
            
            if (cachedResult !== null) {
                this.cacheHits++;
                this.log('debug', 'Cache hit for access verification', {
                    publicKey: this.maskPublicKey(publicKey),
                    nodeId,
                    cached: true
                });
                
                return {
                    ...cachedResult,
                    cached: true,
                    responseTime: Date.now() - startTime
                };
            }

            this.cacheMisses++;

            // Get token ID for the node
            const tokenId = await this.contractClient.getTokenIdByNodeId(nodeId);
            if (!tokenId || tokenId.toString() === '0') {
                const result = {
                    granted: false,
                    reason: 'NODE_NOT_FOUND',
                    message: `Node ${nodeId} not found in registry`,
                    nodeId,
                    publicKey: this.maskPublicKey(publicKey),
                    timestamp: new Date().toISOString()
                };

                this.stats.deniedAccess++;
                this.setCache(cacheKey, result);
                
                this.log('info', 'Access denied - node not found', result);
                return {
                    ...result,
                    cached: false,
                    responseTime: Date.now() - startTime
                };
            }

            // Get node access details
            const nodeAccess = await this.contractClient.getNodeAccess(tokenId);
            if (!nodeAccess.isActive) {
                const result = {
                    granted: false,
                    reason: 'NODE_INACTIVE',
                    message: `Node ${nodeId} is inactive`,
                    nodeId,
                    tokenId: tokenId.toString(),
                    publicKey: this.maskPublicKey(publicKey),
                    timestamp: new Date().toISOString()
                };

                this.stats.deniedAccess++;
                this.setCache(cacheKey, result);
                
                this.log('info', 'Access denied - node inactive', result);
                return {
                    ...result,
                    cached: false,
                    responseTime: Date.now() - startTime
                };
            }

            // Verify public key matches
            if (nodeAccess.wireguardPublicKey !== publicKey) {
                const result = {
                    granted: false,
                    reason: 'PUBLIC_KEY_MISMATCH',
                    message: `Public key mismatch for node ${nodeId}`,
                    nodeId,
                    tokenId: tokenId.toString(),
                    expectedKey: this.maskPublicKey(nodeAccess.wireguardPublicKey),
                    providedKey: this.maskPublicKey(publicKey),
                    timestamp: new Date().toISOString()
                };

                this.stats.deniedAccess++;
                this.setCache(cacheKey, result);
                
                this.log('warn', 'Access denied - public key mismatch', result);
                return {
                    ...result,
                    cached: false,
                    responseTime: Date.now() - startTime
                };
            }

            // Get owner address for the token
            const ownerAddress = await this.contractClient.contract.ownerOf(tokenId);
            
            // Verify access for the owner
            const hasAccess = await this.contractClient.hasNodeAccess(ownerAddress, nodeId);
            
            if (!hasAccess) {
                const result = {
                    granted: false,
                    reason: 'ACCESS_DENIED',
                    message: `Access denied for node ${nodeId}`,
                    nodeId,
                    tokenId: tokenId.toString(),
                    ownerAddress,
                    publicKey: this.maskPublicKey(publicKey),
                    timestamp: new Date().toISOString()
                };

                this.stats.deniedAccess++;
                this.setCache(cacheKey, result);
                
                this.log('info', 'Access denied - no permissions', result);
                return {
                    ...result,
                    cached: false,
                    responseTime: Date.now() - startTime
                };
            }

            // Access granted
            const result = {
                granted: true,
                reason: 'ACCESS_GRANTED',
                message: `Access granted for node ${nodeId}`,
                nodeId,
                tokenId: tokenId.toString(),
                ownerAddress,
                publicKey: this.maskPublicKey(publicKey),
                createdAt: nodeAccess.createdAt.toString(),
                timestamp: new Date().toISOString()
            };

            this.stats.grantedAccess++;
            this.setCache(cacheKey, result);
            
            this.log('info', 'Access granted', result);
            return {
                ...result,
                cached: false,
                responseTime: Date.now() - startTime
            };

        } catch (error) {
            this.stats.errors++;
            
            const errorResult = {
                granted: false,
                reason: 'VERIFICATION_ERROR',
                message: `Error during access verification: ${error.message}`,
                nodeId,
                publicKey: this.maskPublicKey(publicKey),
                error: error.message,
                timestamp: new Date().toISOString()
            };

            this.log('error', 'Access verification error', {
                ...errorResult,
                stack: error.stack
            });

            return {
                ...errorResult,
                cached: false,
                responseTime: Date.now() - startTime
            };
        }
    }

    /**
     * Batch verify access for multiple public keys
     * @param {Array} requests - Array of {publicKey, nodeId} objects
     * @returns {Promise<Array>} Array of verification results
     */
    async batchVerifyAccess(requests) {
        const results = [];
        
        for (const request of requests) {
            const result = await this.verifyAccess(request.publicKey, request.nodeId, request.options);
            results.push(result);
        }
        
        return results;
    }

    /**
     * Get cache statistics
     * @returns {Object} Cache statistics
     */
    getCacheStats() {
        return {
            size: this.accessCache.size,
            hits: this.cacheHits,
            misses: this.cacheMisses,
            hitRate: this.cacheHits / (this.cacheHits + this.cacheMisses) || 0,
            maxSize: this.options.maxCacheSize
        };
    }

    /**
     * Get overall statistics
     * @returns {Object} Complete statistics
     */
    getStats() {
        return {
            ...this.stats,
            cache: this.getCacheStats(),
            uptime: Date.now() - new Date(this.stats.lastReset).getTime()
        };
    }

    /**
     * Reset statistics
     */
    resetStats() {
        this.stats = {
            totalRequests: 0,
            grantedAccess: 0,
            deniedAccess: 0,
            errors: 0,
            lastReset: new Date().toISOString()
        };
        this.cacheHits = 0;
        this.cacheMisses = 0;
        
        this.log('info', 'Statistics reset');
    }

    /**
     * Clear access cache
     */
    clearCache() {
        this.accessCache.clear();
        this.log('info', 'Access cache cleared');
    }

    /**
     * Setup contract event listeners for real-time updates
     */
    setupEventListeners() {
        // Listen for access granted events
        this.contractClient.listenToNodeAccessGranted((event) => {
            this.log('info', 'Node access granted event', event);
            this.clearCache(); // Clear cache when access changes
        });

        // Listen for access revoked events
        this.contractClient.listenToNodeAccessRevoked((event) => {
            this.log('info', 'Node access revoked event', event);
            this.clearCache(); // Clear cache when access changes
        });

        // Listen for access transferred events
        this.contractClient.listenToNodeAccessTransferred((event) => {
            this.log('info', 'Node access transferred event', event);
            this.clearCache(); // Clear cache when access changes
        });
    }

    /**
     * Health check for the middleware
     * @returns {Promise<Object>} Health status
     */
    async healthCheck() {
        try {
            const contractHealth = await this.contractClient.healthCheck();
            const stats = this.getStats();
            
            return {
                status: contractHealth.status === 'healthy' ? 'healthy' : 'degraded',
                contract: contractHealth,
                middleware: {
                    cacheStats: stats.cache,
                    requestStats: {
                        total: stats.totalRequests,
                        granted: stats.grantedAccess,
                        denied: stats.deniedAccess,
                        errors: stats.errors
                    },
                    uptime: stats.uptime
                },
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

    // Private helper methods

    /**
     * Get cache key for public key and node ID
     */
    getCacheKey(publicKey, nodeId) {
        return `${publicKey}:${nodeId}`;
    }

    /**
     * Get value from cache
     */
    getFromCache(key) {
        const cached = this.accessCache.get(key);
        if (cached && Date.now() - cached.timestamp < this.options.cacheTimeout) {
            return cached.data;
        }
        
        if (cached) {
            this.accessCache.delete(key);
        }
        
        return null;
    }

    /**
     * Set value in cache
     */
    setCache(key, data) {
        // Implement LRU eviction if cache is full
        if (this.accessCache.size >= this.options.maxCacheSize) {
            const firstKey = this.accessCache.keys().next().value;
            this.accessCache.delete(firstKey);
        }
        
        this.accessCache.set(key, {
            data,
            timestamp: Date.now()
        });
    }

    /**
     * Mask public key for logging (show only first and last 8 characters)
     */
    maskPublicKey(publicKey) {
        if (!publicKey || publicKey.length < 16) {
            return '***';
        }
        return `${publicKey.substring(0, 8)}...${publicKey.substring(publicKey.length - 8)}`;
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

module.exports = AccessControlMiddleware; 