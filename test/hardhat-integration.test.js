const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("DStack VPN Integration Tests", function () {
    let owner, user1, user2;
    let accessControl, peerRegistry, configManager, bridge;
    
    // Test configuration with Hardhat accounts
    const TEST_CONFIG = {
        network: 'base', // Use base network for now since we're testing integration layer
        nodeId: 'test-node-1',
        privateKey: '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80', // Hardhat account #0
        contractPrivateKey: '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d' // Hardhat account #1
    };

    before(async function () {
        // Get signers from Hardhat
        [owner, user1, user2] = await ethers.getSigners();
        
        // Import the modules
        const AccessControlMiddleware = require('../src/access-control');
        const PeerRegistry = require('../src/peer-registry');
        const ConfigManager = require('../src/config-manager');
        const WireGuardContractBridge = require('../src/wireguard-contract-bridge');
        
        // Initialize components with base network (we're testing integration, not contract deployment)
        accessControl = new AccessControlMiddleware({
            network: TEST_CONFIG.network,
            privateKey: TEST_CONFIG.contractPrivateKey,
            logLevel: 'error'
        });
        
        peerRegistry = new PeerRegistry({
            network: TEST_CONFIG.network,
            privateKey: TEST_CONFIG.contractPrivateKey,
            logLevel: 'error',
            autoSync: false
        });
        
        configManager = new ConfigManager({
            logLevel: 'error',
            autoRestart: false
        });
        
        bridge = new WireGuardContractBridge({
            nodeId: TEST_CONFIG.nodeId,
            privateKey: TEST_CONFIG.privateKey,
            network: TEST_CONFIG.network,
            contractPrivateKey: TEST_CONFIG.contractPrivateKey,
            logLevel: 'error',
            autoStart: false
        });
    });

    describe("Access Control Middleware", function () {
        it("should initialize successfully", async function () {
            expect(accessControl).to.not.be.undefined;
            expect(accessControl.getCacheStats).to.be.a('function');
            expect(accessControl.getStats).to.be.a('function');
        });

        it("should provide cache statistics", function () {
            const stats = accessControl.getCacheStats();
            expect(stats).to.be.an('object');
            expect(stats.size).to.be.a('number');
        });

        it("should provide general statistics", function () {
            const stats = accessControl.getStats();
            expect(stats).to.be.an('object');
            expect(stats.totalRequests).to.be.a('number');
        });

        it("should pass health check", async function () {
            const health = await accessControl.healthCheck();
            expect(health).to.be.an('object');
            expect(health.status).to.be.a('string');
        });
    });

    describe("Peer Registry", function () {
        it("should initialize successfully", async function () {
            expect(peerRegistry).to.not.be.undefined;
            expect(peerRegistry.registry).to.be.an('object');
            expect(peerRegistry.generateIPAddress).to.be.a('function');
        });

        it("should have valid registry structure", function () {
            const registry = peerRegistry.registry;
            expect(registry).to.have.property('peers');
            expect(registry).to.have.property('version');
            expect(Array.isArray(registry.peers)).to.be.true;
        });

        it("should generate valid IP addresses", function () {
            const ipAddress = peerRegistry.generateIPAddress(1);
            expect(ipAddress).to.match(/^10\.0\.0\.\d+$/);
        });

        it("should provide statistics", function () {
            const stats = peerRegistry.getStats();
            expect(stats).to.be.an('object');
            expect(stats.totalPeers).to.be.a('number');
        });

        it("should pass health check", async function () {
            const health = await peerRegistry.healthCheck();
            expect(health).to.be.an('object');
            expect(health.status).to.be.a('string');
        });
    });

    describe("Configuration Manager", function () {
        it("should initialize successfully", async function () {
            expect(configManager).to.not.be.undefined;
            expect(configManager.validateConfig).to.be.a('function');
            expect(configManager.generateConfigFile).to.be.a('function');
        });

        it("should validate configurations", function () {
            const mockConfig = {
                interface: {
                    PrivateKey: 'test-private-key',
                    Address: '10.0.0.1/24',
                    ListenPort: 51820
                },
                peers: [
                    {
                        PublicKey: 'test-peer-key',
                        AllowedIPs: '10.0.0.2/32'
                    }
                ],
                metadata: {
                    nodeId: 'test-node',
                    totalPeers: 1,
                    generatedAt: new Date().toISOString(),
                    registryVersion: '2.0'
                }
            };

            const validation = configManager.validateConfig(mockConfig);
            expect(validation.valid).to.be.true;
            expect(validation.errors).to.be.an('array');
        });

        it("should generate configuration files", function () {
            const mockConfig = {
                interface: {
                    PrivateKey: 'test-private-key',
                    Address: '10.0.0.1/24',
                    ListenPort: 51820
                },
                peers: [
                    {
                        PublicKey: 'test-peer-key',
                        AllowedIPs: '10.0.0.2/32'
                    }
                ],
                metadata: {
                    nodeId: 'test-node',
                    totalPeers: 1,
                    generatedAt: new Date().toISOString(),
                    registryVersion: '2.0'
                }
            };

            const configContent = configManager.generateConfigFile(mockConfig);
            expect(configContent).to.be.a('string');
            expect(configContent).to.include('[Interface]');
            expect(configContent).to.include('[Peer]');
        });

        it("should provide statistics", function () {
            const stats = configManager.getStats();
            expect(stats).to.be.an('object');
            expect(stats.updateCount).to.be.a('number');
        });
    });

    describe("WireGuard Contract Bridge", function () {
        it("should initialize successfully", async function () {
            expect(bridge).to.not.be.undefined;
            expect(bridge.initialize).to.be.a('function');
        });

        it("should initialize all components", async function () {
            await bridge.initialize();
            expect(bridge.accessControl).to.not.be.undefined;
            expect(bridge.peerRegistry).to.not.be.undefined;
            expect(bridge.configManager).to.not.be.undefined;
        });

        it("should handle events", function () {
            let eventReceived = false;
            bridge.addEventHandler('test_event', (data) => {
                eventReceived = true;
            });
            bridge.triggerEventHandlers('test_event', { test: true });
            expect(eventReceived).to.be.true;
        });

        it("should provide statistics", function () {
            const stats = bridge.getStats();
            expect(stats).to.be.an('object');
            expect(stats.bridge).to.be.an('object');
        });

        it("should pass health check", async function () {
            const health = await bridge.getHealthStatus();
            expect(health).to.be.an('object');
            expect(health.status).to.be.a('string');
        });
    });

    describe("End-to-End Integration", function () {
        it("should integrate all components", async function () {
            // Set registry reference
            configManager.setRegistry(peerRegistry);
            
            expect(accessControl).to.not.be.undefined;
            expect(peerRegistry).to.not.be.undefined;
            expect(configManager).to.not.be.undefined;
            expect(configManager.registry).to.equal(peerRegistry);
        });

        it("should orchestrate bridge successfully", async function () {
            await bridge.initialize();
            expect(bridge.bridgeState.status).to.equal('initialized');
        });
    });

    describe("Hardhat Integration", function () {
        it("should have access to Hardhat signers", function () {
            expect(owner).to.not.be.undefined;
            expect(user1).to.not.be.undefined;
            expect(user2).to.not.be.undefined;
            expect(owner.address).to.be.a('string');
            expect(owner.address).to.match(/^0x[a-fA-F0-9]{40}$/);
        });

        it("should have different addresses for different signers", function () {
            expect(owner.address).to.not.equal(user1.address);
            expect(owner.address).to.not.equal(user2.address);
            expect(user1.address).to.not.equal(user2.address);
        });
    });
}); 