const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

class ConfigManager {
    constructor(options = {}) {
        this.options = {
            wireguardPath: options.wireguardPath || '/etc/wireguard',
            configPath: options.configPath || '/etc/wireguard/wg0.conf',
            interfaceName: options.interfaceName || 'wg0',
            backupPath: options.backupPath || '/etc/wireguard/backups',
            maxBackups: options.maxBackups || 10,
            logLevel: options.logLevel || 'info',
            validateConfig: options.validateConfig !== false, // Default to true
            autoRestart: options.autoRestart !== false, // Default to true
            ...options
        };

        // Registry reference (will be set by setRegistry)
        this.registry = null;

        // Configuration state
        this.configState = {
            lastUpdate: null,
            lastBackup: null,
            updateCount: 0,
            errors: 0,
            lastError: null
        };

        // Ensure directories exist
        this.ensureDirectories();

        this.log('info', 'ConfigManager initialized', {
            wireguardPath: this.options.wireguardPath,
            configPath: this.options.configPath,
            interfaceName: this.options.interfaceName,
            backupPath: this.options.backupPath
        });
    }

    /**
     * Set registry reference
     * @param {PeerRegistry} registry - Peer registry instance
     */
    setRegistry(registry) {
        this.registry = registry;
        this.log('info', 'Registry reference set');
    }

    /**
     * Ensure required directories exist
     */
    ensureDirectories() {
        const directories = [
            this.options.wireguardPath,
            this.options.backupPath
        ];

        for (const dir of directories) {
            if (!fs.existsSync(dir)) {
                try {
                    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
                    this.log('info', `Created directory: ${dir}`);
                } catch (error) {
                    this.log('error', `Failed to create directory: ${dir}`, { error: error.message });
                }
            }
        }
    }

    /**
     * Update WireGuard configuration
     * @param {string} nodeId - Current node ID
     * @param {string} privateKey - Current node's private key
     * @param {Object} options - Update options
     * @returns {Promise<Object>} Update result
     */
    async updateWireGuardConfig(nodeId, privateKey, options = {}) {
        if (!this.registry) {
            throw new Error('Registry not set. Call setRegistry() first.');
        }

        const startTime = Date.now();
        this.configState.updateCount++;

        try {
            this.log('info', 'Starting WireGuard configuration update', {
                nodeId,
                updateCount: this.configState.updateCount
            });

            // Generate new configuration
            const config = this.registry.generateWireGuardConfig(nodeId, privateKey);
            
            // Validate configuration
            if (this.options.validateConfig) {
                const validation = this.validateConfig(config);
                if (!validation.valid) {
                    throw new Error(`Configuration validation failed: ${validation.errors.join(', ')}`);
                }
            }

            // Create backup of current configuration
            await this.createBackup();

            // Write new configuration
            const configContent = this.generateConfigFile(config);
            await this.writeConfigFile(configContent);

            // Restart WireGuard service if auto-restart is enabled
            if (this.options.autoRestart) {
                await this.restartWireGuard();
            }

            // Update state
            this.configState.lastUpdate = new Date().toISOString();
            this.configState.errors = 0;
            this.configState.lastError = null;

            const updateTime = Date.now() - startTime;
            this.log('info', 'WireGuard configuration updated successfully', {
                nodeId,
                peers: config.peers.length,
                updateTime: `${updateTime}ms`
            });

            return {
                status: 'success',
                nodeId,
                peers: config.peers.length,
                updateTime,
                timestamp: new Date().toISOString()
            };

        } catch (error) {
            this.configState.errors++;
            this.configState.lastError = error.message;

            this.log('error', 'WireGuard configuration update failed', {
                error: error.message,
                errors: this.configState.errors
            });

            // Attempt rollback if backup exists
            try {
                await this.rollback();
                this.log('info', 'Configuration rolled back successfully');
            } catch (rollbackError) {
                this.log('error', 'Rollback failed', { error: rollbackError.message });
            }

            return {
                status: 'error',
                error: error.message,
                errors: this.configState.errors,
                timestamp: new Date().toISOString()
            };
        }
    }

    /**
     * Generate WireGuard configuration file content
     * @param {Object} config - Configuration object
     * @returns {string} Configuration file content
     */
    generateConfigFile(config) {
        let content = '';

        // Interface section
        content += '[Interface]\n';
        content += `PrivateKey = ${config.interface.PrivateKey}\n`;
        content += `Address = ${config.interface.Address}\n`;
        content += `ListenPort = ${config.interface.ListenPort}\n`;
        
        if (config.interface.PostUp) {
            content += `PostUp = ${config.interface.PostUp}\n`;
        }
        
        if (config.interface.PostDown) {
            content += `PostDown = ${config.interface.PostDown}\n`;
        }

        content += '\n';

        // Peer sections
        for (const peer of config.peers) {
            content += '[Peer]\n';
            content += `PublicKey = ${peer.PublicKey}\n`;
            content += `AllowedIPs = ${peer.AllowedIPs}\n`;
            
            if (peer.Endpoint) {
                content += `Endpoint = ${peer.Endpoint}\n`;
            }
            
            if (peer.PersistentKeepalive) {
                content += `PersistentKeepalive = ${peer.PersistentKeepalive}\n`;
            }

            content += '\n';
        }

        // Add metadata as comments
        content += `# Generated by DStack VPN Config Manager\n`;
        content += `# Node ID: ${config.metadata.nodeId}\n`;
        content += `# Total Peers: ${config.metadata.totalPeers}\n`;
        content += `# Generated At: ${config.metadata.generatedAt}\n`;
        content += `# Registry Version: ${config.metadata.registryVersion}\n`;

        return content;
    }

    /**
     * Validate WireGuard configuration
     * @param {Object} config - Configuration to validate
     * @returns {Object} Validation result
     */
    validateConfig(config) {
        const errors = [];

        // Validate interface configuration
        if (!config.interface) {
            errors.push('Missing interface configuration');
        } else {
            if (!config.interface.PrivateKey) {
                errors.push('Missing private key');
            }
            if (!config.interface.Address) {
                errors.push('Missing address');
            }
            if (!config.interface.ListenPort) {
                errors.push('Missing listen port');
            }
        }

        // Validate peers
        if (!Array.isArray(config.peers)) {
            errors.push('Peers must be an array');
        } else {
            for (let i = 0; i < config.peers.length; i++) {
                const peer = config.peers[i];
                if (!peer.PublicKey) {
                    errors.push(`Peer ${i}: Missing public key`);
                }
                if (!peer.AllowedIPs) {
                    errors.push(`Peer ${i}: Missing allowed IPs`);
                }
            }
        }

        // Validate metadata
        if (!config.metadata) {
            errors.push('Missing metadata');
        }

        return {
            valid: errors.length === 0,
            errors
        };
    }

    /**
     * Write configuration file
     * @param {string} content - Configuration content
     * @returns {Promise<void>}
     */
    async writeConfigFile(content) {
        try {
            // Write to temporary file first
            const tempPath = `${this.options.configPath}.tmp`;
            fs.writeFileSync(tempPath, content, { mode: 0o600 });

            // Move to final location atomically
            fs.renameSync(tempPath, this.options.configPath);

            this.log('debug', 'Configuration file written successfully');
        } catch (error) {
            this.log('error', 'Failed to write configuration file', { error: error.message });
            throw error;
        }
    }

    /**
     * Create backup of current configuration
     * @returns {Promise<string>} Backup file path
     */
    async createBackup() {
        try {
            if (!fs.existsSync(this.options.configPath)) {
                this.log('warn', 'No existing configuration to backup');
                return null;
            }

            const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
            const backupPath = path.join(this.options.backupPath, `wg0-${timestamp}.conf`);
            
            fs.copyFileSync(this.options.configPath, backupPath);
            fs.chmodSync(backupPath, 0o600);

            this.configState.lastBackup = backupPath;
            this.log('info', 'Configuration backup created', { backupPath });

            // Clean up old backups
            await this.cleanupBackups();

            return backupPath;
        } catch (error) {
            this.log('error', 'Failed to create backup', { error: error.message });
            throw error;
        }
    }

    /**
     * Clean up old backups
     * @returns {Promise<void>}
     */
    async cleanupBackups() {
        try {
            const files = fs.readdirSync(this.options.backupPath)
                .filter(file => file.startsWith('wg0-') && file.endsWith('.conf'))
                .map(file => ({
                    name: file,
                    path: path.join(this.options.backupPath, file),
                    mtime: fs.statSync(path.join(this.options.backupPath, file)).mtime
                }))
                .sort((a, b) => b.mtime - a.mtime);

            // Remove old backups beyond maxBackups
            if (files.length > this.options.maxBackups) {
                const toRemove = files.slice(this.options.maxBackups);
                for (const file of toRemove) {
                    fs.unlinkSync(file.path);
                    this.log('debug', 'Removed old backup', { file: file.name });
                }
            }
        } catch (error) {
            this.log('warn', 'Failed to cleanup backups', { error: error.message });
        }
    }

    /**
     * Rollback to previous configuration
     * @returns {Promise<void>}
     */
    async rollback() {
        try {
            if (!this.configState.lastBackup || !fs.existsSync(this.configState.lastBackup)) {
                throw new Error('No backup available for rollback');
            }

            // Copy backup to current configuration
            fs.copyFileSync(this.configState.lastBackup, this.options.configPath);
            fs.chmodSync(this.options.configPath, 0o600);

            // Restart WireGuard service
            if (this.options.autoRestart) {
                await this.restartWireGuard();
            }

            this.log('info', 'Configuration rolled back successfully', {
                backupPath: this.configState.lastBackup
            });
        } catch (error) {
            this.log('error', 'Rollback failed', { error: error.message });
            throw error;
        }
    }

    /**
     * Restart WireGuard service
     * @returns {Promise<void>}
     */
    async restartWireGuard() {
        try {
            this.log('info', 'Restarting WireGuard service');

            // Stop WireGuard interface
            await execAsync(`wg-quick down ${this.options.interfaceName}`);

            // Start WireGuard interface
            await execAsync(`wg-quick up ${this.options.interfaceName}`);

            this.log('info', 'WireGuard service restarted successfully');
        } catch (error) {
            this.log('error', 'Failed to restart WireGuard service', { error: error.message });
            throw error;
        }
    }

    /**
     * Get WireGuard interface status
     * @returns {Promise<Object>} Interface status
     */
    async getInterfaceStatus() {
        try {
            const { stdout } = await execAsync(`wg show ${this.options.interfaceName}`);
            
            const status = {
                interface: this.options.interfaceName,
                status: 'active',
                peers: 0,
                lastHandshake: null,
                transferRx: 0,
                transferTx: 0
            };

            // Parse wg show output
            const lines = stdout.split('\n');
            for (const line of lines) {
                if (line.includes('peer:')) {
                    status.peers++;
                }
                if (line.includes('latest handshake:')) {
                    status.lastHandshake = line.split(':')[1].trim();
                }
                if (line.includes('transfer:')) {
                    const transfer = line.split(':')[1].trim();
                    const [rx, tx] = transfer.split(', ');
                    status.transferRx = parseInt(rx.split(' ')[0]) || 0;
                    status.transferTx = parseInt(tx.split(' ')[0]) || 0;
                }
            }

            return status;
        } catch (error) {
            return {
                interface: this.options.interfaceName,
                status: 'inactive',
                error: error.message
            };
        }
    }

    /**
     * Monitor contract events and update configuration
     * @param {DstackContractClient} contractClient - Contract client
     * @returns {Promise<void>}
     */
    async monitorContractEvents(contractClient) {
        this.log('info', 'Starting contract event monitoring');

        // Listen for access granted events
        contractClient.listenToNodeAccessGranted(async (event) => {
            this.log('info', 'Node access granted event', event);
            // Trigger config update after a delay to allow registry to sync
            setTimeout(async () => {
                if (this.registry) {
                    await this.updateWireGuardConfig('current-node', 'current-private-key');
                }
            }, 10000);
        });

        // Listen for access revoked events
        contractClient.listenToNodeAccessRevoked(async (event) => {
            this.log('info', 'Node access revoked event', event);
            // Trigger config update after a delay
            setTimeout(async () => {
                if (this.registry) {
                    await this.updateWireGuardConfig('current-node', 'current-private-key');
                }
            }, 10000);
        });

        // Listen for access transferred events
        contractClient.listenToNodeAccessTransferred(async (event) => {
            this.log('info', 'Node access transferred event', event);
            // Trigger config update after a delay
            setTimeout(async () => {
                if (this.registry) {
                    await this.updateWireGuardConfig('current-node', 'current-private-key');
                }
            }, 10000);
        });
    }

    /**
     * Get configuration statistics
     * @returns {Object} Configuration statistics
     */
    getStats() {
        return {
            ...this.configState,
            options: {
                wireguardPath: this.options.wireguardPath,
                configPath: this.options.configPath,
                interfaceName: this.options.interfaceName,
                validateConfig: this.options.validateConfig,
                autoRestart: this.options.autoRestart
            },
            timestamp: new Date().toISOString()
        };
    }

    /**
     * Health check for the configuration manager
     * @returns {Promise<Object>} Health status
     */
    async healthCheck() {
        try {
            const interfaceStatus = await this.getInterfaceStatus();
            const stats = this.getStats();
            
            return {
                status: interfaceStatus.status === 'active' ? 'healthy' : 'degraded',
                interface: interfaceStatus,
                config: stats,
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
                component: 'ConfigManager',
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

module.exports = ConfigManager; 