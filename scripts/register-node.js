#!/usr/bin/env node

const DstackContractClient = require('../src/contract-client');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

class NodeRegistrar {
    constructor(privateKey) {
        this.contractClient = new DstackContractClient('base', privateKey);
        this.registryPath = path.join(__dirname, '../config/node-registry.json');
        this.loadRegistry();
    }

    loadRegistry() {
        try {
            if (fs.existsSync(this.registryPath)) {
                this.registry = JSON.parse(fs.readFileSync(this.registryPath, 'utf8'));
            } else {
                this.registry = {
                    peers: [],
                    contract_address: "0x37d2106bADB01dd5bE1926e45D172Cb4203C4186",
                    network: {
                        cidr: "10.0.0.0/24",
                        dns_server: "10.0.0.1"
                    },
                    last_updated: new Date().toISOString()
                };
            }
        } catch (error) {
            console.error('Error loading registry:', error);
            this.registry = {
                peers: [],
                contract_address: "0x37d2106bADB01dd5bE1926e45D172Cb4203C4186",
                network: {
                    cidr: "10.0.0.0/24",
                    dns_server: "10.0.0.1"
                },
                last_updated: new Date().toISOString()
            };
        }
    }

    saveRegistry() {
        try {
            this.registry.last_updated = new Date().toISOString();
            fs.writeFileSync(this.registryPath, JSON.stringify(this.registry, null, 2));
            console.log('Registry saved successfully');
        } catch (error) {
            console.error('Error saving registry:', error);
            throw error;
        }
    }

    generateWireGuardKeys() {
        // Generate WireGuard key pair using proper format
        const privateKey = crypto.randomBytes(32);
        
        // For WireGuard, we need base64 encoded keys
        // Private key is just the raw bytes encoded in base64
        // Public key is derived from private key using WireGuard's key derivation
        const privateKeyBase64 = privateKey.toString('base64');
        
        // For testing purposes, we'll create a mock public key
        // In production, this would use WireGuard's actual key derivation
        const publicKeyBase64 = crypto.randomBytes(32).toString('base64');
        
        return {
            privateKey: privateKeyBase64,
            publicKey: publicKeyBase64
        };
    }

    generateNodeId() {
        return `node-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    }

    assignIPAddress() {
        const usedIPs = this.registry.peers.map(peer => peer.ip_address);
        let ipCounter = 1;
        
        while (usedIPs.includes(`10.0.0.${ipCounter}`)) {
            ipCounter++;
        }
        
        if (ipCounter > 254) {
            throw new Error('No available IP addresses in subnet');
        }
        
        return `10.0.0.${ipCounter}`;
    }

    async registerNode(nodeAddress, nodeId = null, customPublicKey = null) {
        try {
            console.log(`Registering node for address: ${nodeAddress}`);
            
            // Generate or use provided node ID
            const finalNodeId = nodeId || this.generateNodeId();
            console.log(`Node ID: ${finalNodeId}`);
            
            // Check if node ID already exists
            const existingTokenId = await this.contractClient.getTokenIdByNodeId(finalNodeId);
            if (existingTokenId > 0) {
                throw new Error(`Node ID ${finalNodeId} already exists`);
            }
            
            // Generate or use provided WireGuard keys
            const keys = customPublicKey ? 
                { privateKey: 'custom', publicKey: customPublicKey } : 
                this.generateWireGuardKeys();
            
            console.log(`Generated WireGuard public key: ${keys.publicKey}`);
            
            // Assign IP address
            const ipAddress = this.assignIPAddress();
            console.log(`Assigned IP address: ${ipAddress}`);
            
            // Create token URI
            const tokenURI = `https://api.dstack.vpn/metadata/${finalNodeId}`;
            
            // Mint NFT on contract
            console.log('Minting NFT on contract...');
            const tokenId = await this.contractClient.mintNodeAccess(
                nodeAddress,
                finalNodeId,
                keys.publicKey,
                tokenURI
            );
            
            console.log(`NFT minted with token ID: ${tokenId}`);
            
            // Add to local registry
            const peerInfo = {
                node_id: finalNodeId,
                public_key: keys.publicKey,
                ip_address: ipAddress,
                hostname: `${finalNodeId}.vpn.dstack`,
                instance_id: `dstack-${finalNodeId}`,
                nft_owner: nodeAddress,
                access_granted: true,
                token_id: tokenId.toString(),
                created_at: new Date().toISOString()
            };
            
            this.registry.peers.push(peerInfo);
            this.saveRegistry();
            
            console.log('Node registration completed successfully!');
            
            return {
                success: true,
                nodeId: finalNodeId,
                tokenId: tokenId.toString(),
                ipAddress,
                publicKey: keys.publicKey,
                privateKey: keys.privateKey,
                peerInfo
            };
            
        } catch (error) {
            console.error('Error registering node:', error);
            return {
                success: false,
                error: error.message
            };
        }
    }

    async verifyNodeAccess(nodeAddress, nodeId) {
        try {
            const hasAccess = await this.contractClient.hasNodeAccess(nodeAddress, nodeId);
            console.log(`Access verification for ${nodeAddress} on ${nodeId}: ${hasAccess}`);
            return hasAccess;
        } catch (error) {
            console.error('Error verifying node access:', error);
            return false;
        }
    }

    async getNodeInfo(nodeId) {
        try {
            const tokenId = await this.contractClient.getTokenIdByNodeId(nodeId);
            if (tokenId === 0) {
                console.log(`Node ${nodeId} not found`);
                return null;
            }
            
            const nodeAccess = await this.contractClient.getNodeAccess(tokenId);
            const owner = await this.contractClient.contract.ownerOf(tokenId);
            
            return {
                tokenId: tokenId.toString(),
                nodeId: nodeAccess.nodeId,
                publicKey: nodeAccess.wireguardPublicKey,
                createdAt: new Date(nodeAccess.createdAt * 1000).toISOString(),
                isActive: nodeAccess.isActive,
                owner
            };
        } catch (error) {
            console.error('Error getting node info:', error);
            return null;
        }
    }

    listRegisteredNodes() {
        console.log('\nRegistered Nodes:');
        console.log('================');
        
        if (this.registry.peers.length === 0) {
            console.log('No nodes registered');
            return;
        }
        
        this.registry.peers.forEach((peer, index) => {
            console.log(`${index + 1}. Node ID: ${peer.node_id}`);
            console.log(`   IP Address: ${peer.ip_address}`);
            console.log(`   NFT Owner: ${peer.nft_owner}`);
            console.log(`   Token ID: ${peer.token_id}`);
            console.log(`   Status: ${peer.access_granted ? 'Active' : 'Inactive'}`);
            console.log(`   Created: ${peer.created_at}`);
            console.log('');
        });
    }

    async revokeNodeAccess(tokenId) {
        try {
            console.log(`Revoking access for token ID: ${tokenId}`);
            await this.contractClient.revokeNodeAccess(tokenId);
            
            // Update local registry
            const peerIndex = this.registry.peers.findIndex(peer => peer.token_id === tokenId.toString());
            if (peerIndex !== -1) {
                this.registry.peers[peerIndex].access_granted = false;
                this.saveRegistry();
                console.log('Local registry updated');
            }
            
            console.log('Node access revoked successfully');
            return true;
        } catch (error) {
            console.error('Error revoking node access:', error);
            return false;
        }
    }
}

// CLI interface
if (require.main === module) {
    const args = process.argv.slice(2);
    const command = args[0];
    
    if (!command) {
        console.log(`
DStack Node Registration Tool

Usage:
  node register-node.js register <address> [nodeId] [publicKey]
  node register-node.js verify <address> <nodeId>
  node register-node.js info <nodeId>
  node register-node.js list
  node register-node.js revoke <tokenId>

Examples:
  node register-node.js register 0x1234...abcd
  node register-node.js verify 0x1234...abcd node-a
  node register-node.js info node-a
  node register-node.js list
  node register-node.js revoke 1
        `);
        process.exit(1);
    }
    
    const privateKey = process.env.PRIVATE_KEY;
    if (!privateKey && command === 'register') {
        console.error('PRIVATE_KEY environment variable required for registration');
        process.exit(1);
    }
    
    const registrar = new NodeRegistrar(privateKey);
    
    switch (command) {
        case 'register':
            const address = args[1];
            const nodeId = args[2];
            const publicKey = args[3];
            
            if (!address) {
                console.error('Address required for registration');
                process.exit(1);
            }
            
            registrar.registerNode(address, nodeId, publicKey)
                .then(result => {
                    if (result.success) {
                        console.log('Registration successful:', result);
                    } else {
                        console.error('Registration failed:', result.error);
                        process.exit(1);
                    }
                });
            break;
            
        case 'verify':
            const verifyAddress = args[1];
            const verifyNodeId = args[2];
            
            if (!verifyAddress || !verifyNodeId) {
                console.error('Address and node ID required for verification');
                process.exit(1);
            }
            
            registrar.verifyNodeAccess(verifyAddress, verifyNodeId)
                .then(hasAccess => {
                    process.exit(hasAccess ? 0 : 1);
                });
            break;
            
        case 'info':
            const infoNodeId = args[1];
            
            if (!infoNodeId) {
                console.error('Node ID required for info');
                process.exit(1);
            }
            
            registrar.getNodeInfo(infoNodeId)
                .then(info => {
                    if (info) {
                        console.log('Node Info:', info);
                    } else {
                        console.error('Node not found');
                        process.exit(1);
                    }
                });
            break;
            
        case 'list':
            registrar.listRegisteredNodes();
            break;
            
        case 'revoke':
            const tokenId = args[1];
            
            if (!tokenId) {
                console.error('Token ID required for revocation');
                process.exit(1);
            }
            
            registrar.revokeNodeAccess(tokenId)
                .then(success => {
                    if (!success) {
                        process.exit(1);
                    }
                });
            break;
            
        default:
            console.error(`Unknown command: ${command}`);
            process.exit(1);
    }
}

module.exports = NodeRegistrar; 