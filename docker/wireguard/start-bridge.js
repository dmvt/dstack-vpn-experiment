#!/usr/bin/env node

const { WireGuardContractBridge } = require('./src/wireguard-contract-bridge');
const fs = require('fs');
const path = require('path');

// Function to log messages
function log(message) {
    console.log(`[${new Date().toISOString()}] ${message}`);
}

// Function to wait for bridge to be ready
function waitForBridgeReady(bridge, maxAttempts = 30) {
    return new Promise((resolve, reject) => {
        let attempts = 0;
        
        const checkHealth = async () => {
            try {
                const health = await bridge.getHealthStatus();
                if (health.status === 'healthy') {
                    log('Bridge is ready');
                    resolve();
                } else {
                    attempts++;
                    if (attempts >= maxAttempts) {
                        reject(new Error('Bridge failed to become ready within timeout'));
                    } else {
                        setTimeout(checkHealth, 1000);
                    }
                }
            } catch (error) {
                attempts++;
                if (attempts >= maxAttempts) {
                    reject(error);
                } else {
                    setTimeout(checkHealth, 1000);
                }
            }
        };
        
        checkHealth();
    });
}

async function startBridge() {
    try {
        log('Starting WireGuard Contract Bridge...');
        
        // Load configuration
        const configPath = process.env.CONFIG_PATH || path.join('/app/config/contract-config.json');
        if (!fs.existsSync(configPath)) {
            throw new Error(`Contract configuration not found at ${configPath}`);
        }
        
        const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
        
        // Read WireGuard private key
        const privateKeyPath = process.env.WIREGUARD_PRIVATE_KEY_PATH || '/etc/wireguard/private.key';
        if (!fs.existsSync(privateKeyPath)) {
            throw new Error(`WireGuard private key not found at ${privateKeyPath}`);
        }
        
        const privateKey = fs.readFileSync(privateKeyPath, 'utf8').trim();
        
        // Create bridge instance
        const bridge = new WireGuardContractBridge({
            nodeId: config.nodeId,
            privateKey: privateKey,
            network: config.network,
            contractPrivateKey: process.env.CONTRACT_PRIVATE_KEY,
            autoSync: true,
            syncInterval: config.syncInterval,
            logLevel: config.logLevel,
            contractAddress: config.contractAddress,
            rpcUrl: config.rpcUrl
        });
        
        // Start the bridge
        await bridge.start();
        log('Bridge started successfully');
        
        // Wait for bridge to be ready
        await waitForBridgeReady(bridge);
        
        // Handle graceful shutdown
        const shutdown = async (signal) => {
            log(`Received ${signal}, shutting down gracefully...`);
            try {
                await bridge.stop();
                log('Bridge stopped successfully');
                process.exit(0);
            } catch (error) {
                log(`Error during shutdown: ${error.message}`);
                process.exit(1);
            }
        };
        
        process.on('SIGTERM', () => shutdown('SIGTERM'));
        process.on('SIGINT', () => shutdown('SIGINT'));
        
        // Monitor bridge health
        setInterval(async () => {
            try {
                const health = await bridge.getHealthStatus();
                if (health.status !== 'healthy') {
                    log(`Warning: Bridge health status is ${health.status}`);
                }
            } catch (error) {
                log(`Error checking bridge health: ${error.message}`);
            }
        }, 30000); // Check every 30 seconds
        
        log('Bridge is running and monitoring health...');
        
    } catch (error) {
        log(`Error starting bridge: ${error.message}`);
        process.exit(1);
    }
}

// Start the bridge
startBridge().catch((error) => {
    log(`Fatal error: ${error.message}`);
    process.exit(1);
}); 