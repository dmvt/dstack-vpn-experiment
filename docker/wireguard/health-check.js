#!/usr/bin/env node

const http = require('http');
const { exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

// Configuration
const PORT = process.env.HEALTH_CHECK_PORT || 8000;
const NODE_ID = process.env.NODE_ID || 'unknown';

// Helper function to get WireGuard status
async function getWireGuardStatus() {
    try {
        const { stdout } = await execAsync('wg show wg0');
        const lines = stdout.trim().split('\n');
        
        let peerCount = 0;
        let maxHandshakeAge = 0;
        const now = Math.floor(Date.now() / 1000);
        
        for (const line of lines) {
            if (line.includes('latest handshake:')) {
                peerCount++;
                const match = line.match(/latest handshake: (\d+)/);
                if (match) {
                    const handshakeTime = parseInt(match[1]);
                    if (handshakeTime > 0) {
                        const age = now - handshakeTime;
                        if (age > maxHandshakeAge) {
                            maxHandshakeAge = age;
                        }
                    }
                }
            }
        }
        
        return {
            interface: 'wg0',
            peer_count: peerCount,
            max_last_handshake_sec: maxHandshakeAge
        };
    } catch (error) {
        return {
            interface: 'wg0',
            peer_count: 0,
            max_last_handshake_sec: 0,
            error: error.message
        };
    }
}

// Helper function to get overlay IP
async function getOverlayIP() {
    try {
        const { stdout } = await execAsync('ip addr show wg0');
        const match = stdout.match(/inet (10\.88\.0\.\d+)/);
        return match ? match[1] : '';
    } catch (error) {
        return '';
    }
}

// Helper function to get disk free space
async function getDiskFreeGB() {
    try {
        const { stdout } = await execAsync('df / | tail -1');
        const parts = stdout.trim().split(/\s+/);
        const freeKB = parseInt(parts[3]);
        const freeGB = (freeKB * 1024) / (1024 * 1024 * 1024);
        return Math.round(freeGB * 10) / 10; // 0.1 GB precision
    } catch (error) {
        return 0;
    }
}

// Create HTTP server
const server = http.createServer(async (req, res) => {
    try {
        if (req.url === '/status' && req.method === 'GET') {
            const [wgStatus, overlayIP, diskFree] = await Promise.all([
                getWireGuardStatus(),
                getOverlayIP(),
                getDiskFreeGB()
            ]);
            
            const status = {
                node: NODE_ID,
                overlay_ip: overlayIP,
                wg: wgStatus,
                disk_free_gb: diskFree,
                time: new Date().toISOString()
            };
            
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(status, null, 2));
        } else if (req.url === '/health' && req.method === 'GET') {
            const wgStatus = await getWireGuardStatus();
            
            const health = {
                status: wgStatus.peer_count > 0 ? 'healthy' : 'degraded',
                node: NODE_ID,
                wireguard: wgStatus,
                timestamp: new Date().toISOString()
            };
            
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(health, null, 2));
        } else if (req.url === '/ready' && req.method === 'GET') {
            res.writeHead(200, { 'Content-Type': 'text/plain' });
            res.end('ready');
        } else {
            res.writeHead(404, { 'Content-Type': 'text/plain' });
            res.end('Not Found');
        }
    } catch (error) {
        console.error('Health check error:', error);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Internal Server Error' }));
    }
});

// Start server
server.listen(PORT, () => {
    console.log(`Health check server listening on port ${PORT}`);
});

// Handle graceful shutdown
process.on('SIGTERM', () => {
    console.log('Received SIGTERM, shutting down gracefully...');
    server.close(() => {
        console.log('Health check server closed');
        process.exit(0);
    });
});

process.on('SIGINT', () => {
    console.log('Received SIGINT, shutting down gracefully...');
    server.close(() => {
        console.log('Health check server closed');
        process.exit(0);
    });
}); 