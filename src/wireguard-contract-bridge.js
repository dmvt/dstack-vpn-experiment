const AccessControlMiddleware = require('./access-control');
const PeerRegistry = require('./peer-registry');
const ConfigManager = require('./config-manager');
const DstackContractClient = require('./contract-client');
const fs = require('fs');
const path = require('path');

class WireGuardContractBridge {
    constructor(options = {}) {
        this.options = {
            nodeId: options.nodeId || process.env.NODE_ID,
            privateKey: options.privateKey || process.env.PRIVATE_KEY,
            network: options.network || 'base',
            contractPrivateKey: options.contractPrivateKey || process.env.CONTRACT_PRIVATE_KEY,
            logLevel: options.logLevel || 'info',
            autoStart: options.autoStart !== false, // Default to true
            healthCheckInterval: options.healthCheckInterval || 30000, // 30 seconds
            ...options
        };

        // Validate required options
        if (!this.options.nodeId) {
            throw new Error('NODE_ID is required');
        }
        if (!this.options.privateKey) {
            throw new Error('PRIVATE_KEY is required');
        }

        // Initialize components
        this.contractClient = null;
        this.accessControl = null;
        this.peerRegistry = null;
        this.configManager = null;

        // Bridge state
        this.bridgeState = {
            status: 'initializing',
            startTime: null,
            lastHealthCheck: null,
            errors: 0,
            lastError: null
        };

        // Health check timer
        this.healthCheckTimer = null;

        // Event handlers
        this.eventHandlers = new Map();

        this.log('info', 'WireGuardContractBridge initializing', {
            nodeId: this.options.nodeId,
            network: this.options.network,
            autoStart: this.options.autoStart
        });
    }

    /**
     * Initialize all components
     * @returns {Promise<void>}
     */
    async initialize() {
        try {
            this.log('info', 'Initializing WireGuard contract bridge components');

            // Initialize contract client
            this.contractClient = new DstackContractClient(
                this.options.network,
                this.options.contractPrivateKey
            );

            // Initialize access control middleware
            this.accessControl = new AccessControlMiddleware({
                network: this.options.network,
                privateKey: this.options.contractPrivateKey,
                logLevel: this.options.logLevel
            });

            // Initialize peer registry
            this.peerRegistry = new PeerRegistry({
                network: this.options.network,
                privateKey: this.options.contractPrivateKey,
                logLevel: this.options.logLevel
            });

            // Initialize config manager
            this.configManager = new ConfigManager({
                logLevel: this.options.logLevel
            });

            // Set registry reference in config manager
            this.configManager.setRegistry(this.peerRegistry);

            // Setup event handlers
            this.setupEventHandlers();

            this.log('info', 'All components initialized successfully');
            this.bridgeState.status = 'initialized';

        } catch (error) {
            this.bridgeState.status = 'error';
            this.bridgeState.errors++;
            this.bridgeState.lastError = error.message;

            this.log('error', 'Failed to initialize bridge components', {
                error: error.message,
                stack: error.stack
            });

            throw error;
        }
    }

    /**
     * Start the bridge
     * @returns {Promise<void>}
     */
    async start() {
        try {
            this.log('info', 'Starting WireGuard contract bridge');

            // Initialize if not already done
            if (this.bridgeState.status === 'initializing') {
                await this.initialize();
            }

            // Perform initial registry sync
            await this.peerRegistry.syncWithContract(true);

            // Perform initial configuration update
            await this.configManager.updateWireGuardConfig(
                this.options.nodeId,
                this.options.privateKey
            );

            // Start contract event monitoring
            await this.configManager.monitorContractEvents(this.contractClient);

            // Start health check timer
            this.startHealthCheck();

            this.bridgeState.status = 'running';
            this.bridgeState.startTime = new Date().toISOString();

            this.log('info', 'WireGuard contract bridge started successfully');

        } catch (error) {
            this.bridgeState.status = 'error';
            this.bridgeState.errors++;
            this.bridgeState.lastError = error.message;

            this.log('error', 'Failed to start bridge', {
                error: error.message,
                stack: error.stack
            });

            throw error;
        }
    }

    /**
     * Stop the bridge
     * @returns {Promise<void>}
     */
    async stop() {
        try {
            this.log('info', 'Stopping WireGuard contract bridge');

            // Stop health check timer
            this.stopHealthCheck();

            // Stop auto-sync in peer registry
            if (this.peerRegistry) {
                this.peerRegistry.stopAutoSync();
            }

            this.bridgeState.status = 'stopped';

            this.log('info', 'WireGuard contract bridge stopped successfully');

        } catch (error) {
            this.log('error', 'Error stopping bridge', {
                error: error.message
            });

            throw error;
        }
    }

    /**
     * Handle WireGuard connection attempt
     * @param {string} publicKey - WireGuard public key
     * @param {string} nodeId - Node identifier
     * @returns {Promise<Object>} Access verification result
     */
    async handleConnection(publicKey, nodeId) {
        try {
            this.log('info', 'Handling WireGuard connection attempt', {
                publicKey: this.maskPublicKey(publicKey),
                nodeId
            });

            // Verify access through middleware
            const result = await this.accessControl.verifyAccess(publicKey, nodeId);

            // Log the access attempt
            this.log(result.granted ? 'info' : 'warn', 'Access verification result', {
                granted: result.granted,
                reason: result.reason,
                nodeId,
                publicKey: this.maskPublicKey(publicKey),
                responseTime: result.responseTime
            });

            // Trigger event handlers
            this.triggerEventHandlers('connection', {
                publicKey: this.maskPublicKey(publicKey),
                nodeId,
                result
            });

            return result;

        } catch (error) {
            this.bridgeState.errors++;
            this.bridgeState.lastError = error.message;

            this.log('error', 'Error handling connection', {
                error: error.message,
                publicKey: this.maskPublicKey(publicKey),
                nodeId
            });

            return {
                granted: false,
                reason: 'BRIDGE_ERROR',
                message: `Bridge error: ${error.message}`,
                error: error.message,
                timestamp: new Date().toISOString()
            };
        }
    }

    /**
     * Update WireGuard configuration
     * @param {Object} options - Update options
     * @returns {Promise<Object>} Update result
     */
    async updateConfiguration(options = {}) {
        try {
            this.log('info', 'Updating WireGuard configuration');

            const result = await this.configManager.updateWireGuardConfig(
                this.options.nodeId,
                this.options.privateKey,
                options
            );

            this.log('info', 'Configuration update completed', result);

            return result;

        } catch (error) {
            this.bridgeState.errors++;
            this.bridgeState.lastError = error.message;

            this.log('error', 'Configuration update failed', {
                error: error.message
            });

            throw error;
        }
    }

    /**
     * Sync peer registry with contract
     * @param {boolean} force - Force sync
     * @returns {Promise<Object>} Sync result
     */
    async syncRegistry(force = false) {
        try {
            this.log('info', 'Syncing peer registry with contract');

            const result = await this.peerRegistry.syncWithContract(force);

            this.log('info', 'Registry sync completed', result);

            return result;

        } catch (error) {
            this.bridgeState.errors++;
            this.bridgeState.lastError = error.message;

            this.log('error', 'Registry sync failed', {
                error: error.message
            });

            throw error;
        }
    }

    /**
     * Get comprehensive health status
     * @returns {Promise<Object>} Health status
     */
    async getHealthStatus() {
        try {
            const contractHealth = await this.contractClient.healthCheck();
            const accessControlHealth = await this.accessControl.healthCheck();
            const registryHealth = await this.peerRegistry.healthCheck();
            const configHealth = await this.configManager.healthCheck();

            // Determine overall status
            const componentStatuses = [
                contractHealth.status,
                accessControlHealth.status,
                registryHealth.status,
                configHealth.status
            ];

            const overallStatus = componentStatuses.every(status => status === 'healthy') 
                ? 'healthy' 
                : componentStatuses.some(status => status === 'unhealthy') 
                    ? 'unhealthy' 
                    : 'degraded';

            const healthStatus = {
                status: overallStatus,
                bridge: {
                    status: this.bridgeState.status,
                    startTime: this.bridgeState.startTime,
                    uptime: this.bridgeState.startTime 
                        ? Date.now() - new Date(this.bridgeState.startTime).getTime()
                        : 0,
                    errors: this.bridgeState.errors,
                    lastError: this.bridgeState.lastError
                },
                components: {
                    contract: contractHealth,
                    accessControl: accessControlHealth,
                    registry: registryHealth,
                    config: configHealth
                },
                timestamp: new Date().toISOString()
            };

            this.bridgeState.lastHealthCheck = new Date().toISOString();

            return healthStatus;

        } catch (error) {
            return {
                status: 'unhealthy',
                error: error.message,
                timestamp: new Date().toISOString()
            };
        }
    }

    /**
     * Get bridge statistics
     * @returns {Object} Bridge statistics
     */
    getStats() {
        return {
            bridge: this.bridgeState,
            accessControl: this.accessControl ? this.accessControl.getStats() : null,
            registry: this.peerRegistry ? this.peerRegistry.getStats() : null,
            config: this.configManager ? this.configManager.getStats() : null,
            timestamp: new Date().toISOString()
        };
    }

    /**
     * Add event handler
     * @param {string} event - Event name
     * @param {Function} handler - Event handler function
     */
    addEventHandler(event, handler) {
        if (!this.eventHandlers.has(event)) {
            this.eventHandlers.set(event, []);
        }
        this.eventHandlers.get(event).push(handler);
    }

    /**
     * Remove event handler
     * @param {string} event - Event name
     * @param {Function} handler - Event handler function
     */
    removeEventHandler(event, handler) {
        if (this.eventHandlers.has(event)) {
            const handlers = this.eventHandlers.get(event);
            const index = handlers.indexOf(handler);
            if (index > -1) {
                handlers.splice(index, 1);
            }
        }
    }

    /**
     * Trigger event handlers
     * @param {string} event - Event name
     * @param {Object} data - Event data
     */
    triggerEventHandlers(event, data) {
        if (this.eventHandlers.has(event)) {
            const handlers = this.eventHandlers.get(event);
            for (const handler of handlers) {
                try {
                    handler(data);
                } catch (error) {
                    this.log('error', 'Event handler error', {
                        event,
                        error: error.message
                    });
                }
            }
        }
    }

    /**
     * Setup event handlers
     */
    setupEventHandlers() {
        // Handle access control events
        this.addEventHandler('connection', (data) => {
            this.log('debug', 'Connection event', data);
        });

        // Handle registry sync events
        this.addEventHandler('registry_sync', (data) => {
            this.log('debug', 'Registry sync event', data);
        });

        // Handle configuration update events
        this.addEventHandler('config_update', (data) => {
            this.log('debug', 'Configuration update event', data);
        });
    }

    /**
     * Start health check timer
     */
    startHealthCheck() {
        if (this.healthCheckTimer) {
            clearInterval(this.healthCheckTimer);
        }

        this.healthCheckTimer = setInterval(async () => {
            try {
                const health = await this.getHealthStatus();
                
                if (health.status === 'unhealthy') {
                    this.log('error', 'Health check failed', health);
                    this.triggerEventHandlers('health_check_failed', health);
                } else if (health.status === 'degraded') {
                    this.log('warn', 'Health check degraded', health);
                    this.triggerEventHandlers('health_check_degraded', health);
                } else {
                    this.log('debug', 'Health check passed', health);
                }
            } catch (error) {
                this.log('error', 'Health check error', { error: error.message });
            }
        }, this.options.healthCheckInterval);

        this.log('info', 'Health check timer started', {
            interval: this.options.healthCheckInterval
        });
    }

    /**
     * Stop health check timer
     */
    stopHealthCheck() {
        if (this.healthCheckTimer) {
            clearInterval(this.healthCheckTimer);
            this.healthCheckTimer = null;
            this.log('info', 'Health check timer stopped');
        }
    }

    /**
     * Mask public key for logging
     * @param {string} publicKey - Public key to mask
     * @returns {string} Masked public key
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
                component: 'WireGuardContractBridge',
                nodeId: this.options.nodeId,
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

module.exports = WireGuardContractBridge; 