const express = require('express');
const { WireGuardContractBridge } = require('./src/wireguard-contract-bridge');
const fs = require('fs');
const path = require('path');

const app = express();
app.use(express.json());

// Global bridge instance
let bridge = null;

// Function to log messages
function log(message) {
    console.log(`[${new Date().toISOString()}] ${message}`);
}

// Initialize bridge instance
async function initializeBridge() {
    try {
        // Load configuration
        const configPath = path.join('/app/config/contract-config.json');
        if (!fs.existsSync(configPath)) {
            throw new Error('Contract configuration not found');
        }
        
        const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
        
        // Read WireGuard private key
        const privateKeyPath = '/etc/wireguard/private.key';
        if (!fs.existsSync(privateKeyPath)) {
            throw new Error('WireGuard private key not found');
        }
        
        const privateKey = fs.readFileSync(privateKeyPath, 'utf8').trim();
        
        // Create bridge instance
        bridge = new WireGuardContractBridge({
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
        
        await bridge.start();
        log('Bridge initialized for health checks');
        
    } catch (error) {
        log(`Error initializing bridge: ${error.message}`);
        throw error;
    }
}

// Health check endpoint
app.get('/health', async (req, res) => {
    try {
        if (!bridge) {
            return res.status(503).json({
                status: 'unhealthy',
                error: 'Bridge not initialized',
                timestamp: new Date().toISOString()
            });
        }
        
        const health = await bridge.getHealthStatus();
        res.json({
            ...health,
            timestamp: new Date().toISOString()
        });
        
    } catch (error) {
        log(`Health check error: ${error.message}`);
        res.status(500).json({
            status: 'unhealthy',
            error: error.message,
            timestamp: new Date().toISOString()
        });
    }
});

// Statistics endpoint
app.get('/stats', async (req, res) => {
    try {
        if (!bridge) {
            return res.status(503).json({
                error: 'Bridge not initialized',
                timestamp: new Date().toISOString()
            });
        }
        
        const stats = bridge.getStats();
        res.json({
            ...stats,
            timestamp: new Date().toISOString()
        });
        
    } catch (error) {
        log(`Stats error: ${error.message}`);
        res.status(500).json({
            error: error.message,
            timestamp: new Date().toISOString()
        });
    }
});

// WireGuard status endpoint
app.get('/wireguard', async (req, res) => {
    try {
        const { exec } = require('child_process');
        const util = require('util');
        const execAsync = util.promisify(exec);
        
        // Check if WireGuard interface exists
        const { stdout: interfaceStatus } = await execAsync('wg show wg0 2>/dev/null || echo "Interface not found"');
        
        // Check interface status
        const { stdout: ipStatus } = await execAsync('ip addr show wg0 2>/dev/null || echo "Interface not found"');
        
        res.json({
            interface: interfaceStatus.trim(),
            ipStatus: ipStatus.trim(),
            timestamp: new Date().toISOString()
        });
        
    } catch (error) {
        log(`WireGuard status error: ${error.message}`);
        res.status(500).json({
            error: error.message,
            timestamp: new Date().toISOString()
        });
    }
});

// Configuration endpoint
app.get('/config', async (req, res) => {
    try {
        const configPath = path.join('/app/config/contract-config.json');
        if (!fs.existsSync(configPath)) {
            return res.status(404).json({
                error: 'Configuration not found',
                timestamp: new Date().toISOString()
            });
        }
        
        const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
        
        // Remove sensitive information
        const safeConfig = {
            ...config,
            contractPrivateKey: '[REDACTED]'
        };
        
        res.json({
            config: safeConfig,
            timestamp: new Date().toISOString()
        });
        
    } catch (error) {
        log(`Config error: ${error.message}`);
        res.status(500).json({
            error: error.message,
            timestamp: new Date().toISOString()
        });
    }
});

// Ready endpoint for container health checks
app.get('/ready', async (req, res) => {
    try {
        if (!bridge) {
            return res.status(503).json({
                status: 'not ready',
                error: 'Bridge not initialized',
                timestamp: new Date().toISOString()
            });
        }
        
        const health = await bridge.getHealthStatus();
        if (health.status === 'healthy') {
            res.json({
                status: 'ready',
                timestamp: new Date().toISOString()
            });
        } else {
            res.status(503).json({
                status: 'not ready',
                error: 'Bridge not healthy',
                timestamp: new Date().toISOString()
            });
        }
        
    } catch (error) {
        log(`Ready check error: ${error.message}`);
        res.status(503).json({
            status: 'not ready',
            error: error.message,
            timestamp: new Date().toISOString()
        });
    }
});

// Start the server
const PORT = process.env.HEALTH_CHECK_PORT || 8080;

async function startServer() {
    try {
        // Initialize bridge
        await initializeBridge();
        
        // Start server
        app.listen(PORT, () => {
            log(`Health check server running on port ${PORT}`);
        });
        
    } catch (error) {
        log(`Failed to start health check server: ${error.message}`);
        process.exit(1);
    }
}

// Handle graceful shutdown
process.on('SIGTERM', async () => {
    log('Received SIGTERM, shutting down health check server...');
    if (bridge) {
        await bridge.stop();
    }
    process.exit(0);
});

process.on('SIGINT', async () => {
    log('Received SIGINT, shutting down health check server...');
    if (bridge) {
        await bridge.stop();
    }
    process.exit(0);
});

// Start the server
startServer().catch((error) => {
    log(`Fatal error: ${error.message}`);
    process.exit(1);
}); 