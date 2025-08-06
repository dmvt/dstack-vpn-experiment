const AccessControlMiddleware = require('../src/access-control');
const PeerRegistry = require('../src/peer-registry');
const ConfigManager = require('../src/config-manager');
const WireGuardContractBridge = require('../src/wireguard-contract-bridge');
const DstackContractClient = require('../src/contract-client');
const fs = require('fs');
const path = require('path');

// Test configuration
const TEST_CONFIG = {
    network: 'base',
    nodeId: 'test-node-1',
    privateKey: 'test-private-key',
    contractPrivateKey: process.env.CONTRACT_PRIVATE_KEY || 'test-contract-key'
};

// Mock data for testing
const MOCK_PEER_DATA = {
    node_id: 'test-node-1',
    public_key: 'test-public-key-1234567890abcdef',
    ip_address: '10.0.0.1',
    hostname: 'test-node-1.vpn.dstack',
    instance_id: 'dstack-test-node-1',
    nft_owner: '0x1234567890123456789012345678901234567890',
    access_granted: true,
    token_id: 1,
    last_verified: new Date().toISOString(),
    status: 'active',
    created_at: new Date().toISOString()
};

class IntegrationLayerTest {
    constructor() {
        this.testResults = [];
        this.startTime = Date.now();
    }

    /**
     * Run all tests
     */
    async runAllTests() {
        console.log('🚀 Starting DStack Integration Layer Tests\n');

        try {
            // Test 1: Access Control Middleware
            await this.testAccessControlMiddleware();

            // Test 2: Peer Registry
            await this.testPeerRegistry();

            // Test 3: Configuration Manager
            await this.testConfigManager();

            // Test 4: WireGuard Contract Bridge
            await this.testWireGuardContractBridge();

            // Test 5: End-to-End Integration
            await this.testEndToEndIntegration();

            this.printTestSummary();

        } catch (error) {
            console.error('❌ Test suite failed:', error.message);
            this.addTestResult('Test Suite', false, error.message);
            this.printTestSummary();
        }
    }

    /**
     * Test Access Control Middleware
     */
    async testAccessControlMiddleware() {
        console.log('🔐 Testing Access Control Middleware...');

        try {
            // Initialize middleware
            const accessControl = new AccessControlMiddleware({
                network: TEST_CONFIG.network,
                privateKey: TEST_CONFIG.contractPrivateKey,
                logLevel: 'error' // Reduce log noise during tests
            });

            // Test 1.1: Basic initialization
            this.addTestResult('Access Control - Initialization', true, 'Middleware initialized successfully');

            // Test 1.2: Cache functionality
            const cacheStats = accessControl.getCacheStats();
            this.addTestResult('Access Control - Cache Stats', 
                typeof cacheStats === 'object' && cacheStats.size !== undefined,
                `Cache stats: ${JSON.stringify(cacheStats)}`
            );

            // Test 1.3: Statistics functionality
            const stats = accessControl.getStats();
            this.addTestResult('Access Control - Statistics', 
                typeof stats === 'object' && stats.totalRequests !== undefined,
                `Stats: ${JSON.stringify(stats)}`
            );

            // Test 1.4: Health check
            const health = await accessControl.healthCheck();
            this.addTestResult('Access Control - Health Check', 
                typeof health === 'object' && health.status !== undefined,
                `Health: ${JSON.stringify(health)}`
            );

            console.log('✅ Access Control Middleware tests completed\n');

        } catch (error) {
            this.addTestResult('Access Control Middleware', false, error.message);
            console.error('❌ Access Control Middleware test failed:', error.message);
        }
    }

    /**
     * Test Peer Registry
     */
    async testPeerRegistry() {
        console.log('📋 Testing Peer Registry...');

        try {
            // Initialize registry with test config path
            const testConfigPath = path.join(__dirname, '../config/test-peer-registry.json');
            const peerRegistry = new PeerRegistry({
                configPath: testConfigPath,
                network: TEST_CONFIG.network,
                privateKey: TEST_CONFIG.contractPrivateKey,
                logLevel: 'error',
                autoSync: false // Disable auto-sync for testing
            });

            // Test 2.1: Basic initialization
            this.addTestResult('Peer Registry - Initialization', true, 'Registry initialized successfully');

            // Test 2.2: Registry structure validation
            const registry = peerRegistry.registry;
            this.addTestResult('Peer Registry - Structure', 
                registry && Array.isArray(registry.peers) && registry.version,
                `Registry version: ${registry.version}, peers: ${registry.peers.length}`
            );

            // Test 2.3: IP address generation
            const ipAddress = peerRegistry.generateIPAddress(1);
            this.addTestResult('Peer Registry - IP Generation', 
                ipAddress && ipAddress.startsWith('10.0.0.'),
                `Generated IP: ${ipAddress}`
            );

            // Test 2.4: Statistics functionality
            const stats = peerRegistry.getStats();
            this.addTestResult('Peer Registry - Statistics', 
                typeof stats === 'object' && stats.totalPeers !== undefined,
                `Stats: ${JSON.stringify(stats)}`
            );

            // Test 2.5: Health check
            const health = await peerRegistry.healthCheck();
            this.addTestResult('Peer Registry - Health Check', 
                typeof health === 'object' && health.status !== undefined,
                `Health: ${JSON.stringify(health)}`
            );

            // Cleanup test file
            if (fs.existsSync(testConfigPath)) {
                fs.unlinkSync(testConfigPath);
            }

            console.log('✅ Peer Registry tests completed\n');

        } catch (error) {
            this.addTestResult('Peer Registry', false, error.message);
            console.error('❌ Peer Registry test failed:', error.message);
        }
    }

    /**
     * Test Configuration Manager
     */
    async testConfigManager() {
        console.log('⚙️ Testing Configuration Manager...');

        try {
            // Initialize config manager with test paths
            const testWireguardPath = path.join(__dirname, '../test-temp/wireguard');
            const testConfigPath = path.join(testWireguardPath, 'wg0.conf');
            const testBackupPath = path.join(testWireguardPath, 'backups');

            const configManager = new ConfigManager({
                wireguardPath: testWireguardPath,
                configPath: testConfigPath,
                backupPath: testBackupPath,
                logLevel: 'error',
                validateConfig: true,
                autoRestart: false // Disable auto-restart for testing
            });

            // Test 3.1: Basic initialization
            this.addTestResult('Config Manager - Initialization', true, 'Config manager initialized successfully');

            // Test 3.2: Directory creation
            this.addTestResult('Config Manager - Directory Creation', 
                fs.existsSync(testWireguardPath) && fs.existsSync(testBackupPath),
                `Directories created: ${testWireguardPath}, ${testBackupPath}`
            );

            // Test 3.3: Configuration validation
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
            this.addTestResult('Config Manager - Validation', 
                validation.valid,
                `Validation result: ${JSON.stringify(validation)}`
            );

            // Test 3.4: Configuration file generation
            const configContent = configManager.generateConfigFile(mockConfig);
            this.addTestResult('Config Manager - File Generation', 
                configContent && configContent.includes('[Interface]') && configContent.includes('[Peer]'),
                `Generated config length: ${configContent.length} characters`
            );

            // Test 3.5: Statistics functionality
            const stats = configManager.getStats();
            this.addTestResult('Config Manager - Statistics', 
                typeof stats === 'object' && stats.updateCount !== undefined,
                `Stats: ${JSON.stringify(stats)}`
            );

            // Cleanup test directories
            if (fs.existsSync(testWireguardPath)) {
                fs.rmSync(testWireguardPath, { recursive: true, force: true });
            }

            console.log('✅ Configuration Manager tests completed\n');

        } catch (error) {
            this.addTestResult('Configuration Manager', false, error.message);
            console.error('❌ Configuration Manager test failed:', error.message);
        }
    }

    /**
     * Test WireGuard Contract Bridge
     */
    async testWireGuardContractBridge() {
        console.log('🌉 Testing WireGuard Contract Bridge...');

        try {
            // Initialize bridge
            const bridge = new WireGuardContractBridge({
                nodeId: TEST_CONFIG.nodeId,
                privateKey: TEST_CONFIG.privateKey,
                network: TEST_CONFIG.network,
                contractPrivateKey: TEST_CONFIG.contractPrivateKey,
                logLevel: 'error',
                autoStart: false // Disable auto-start for testing
            });

            // Test 4.1: Basic initialization
            this.addTestResult('Bridge - Initialization', true, 'Bridge initialized successfully');

            // Test 4.2: Component initialization
            await bridge.initialize();
            this.addTestResult('Bridge - Component Initialization', 
                bridge.accessControl && bridge.peerRegistry && bridge.configManager,
                'All components initialized'
            );

            // Test 4.3: Event handler functionality
            let eventReceived = false;
            bridge.addEventHandler('test_event', (data) => {
                eventReceived = true;
            });
            bridge.triggerEventHandlers('test_event', { test: true });
            this.addTestResult('Bridge - Event Handlers', 
                eventReceived,
                'Event handler triggered successfully'
            );

            // Test 4.4: Statistics functionality
            const stats = bridge.getStats();
            this.addTestResult('Bridge - Statistics', 
                typeof stats === 'object' && stats.bridge !== undefined,
                `Stats: ${JSON.stringify(stats)}`
            );

            // Test 4.5: Health check
            const health = await bridge.getHealthStatus();
            this.addTestResult('Bridge - Health Check', 
                typeof health === 'object' && health.status !== undefined,
                `Health: ${JSON.stringify(health)}`
            );

            console.log('✅ WireGuard Contract Bridge tests completed\n');

        } catch (error) {
            this.addTestResult('WireGuard Contract Bridge', false, error.message);
            console.error('❌ WireGuard Contract Bridge test failed:', error.message);
        }
    }

    /**
     * Test End-to-End Integration
     */
    async testEndToEndIntegration() {
        console.log('🔗 Testing End-to-End Integration...');

        try {
            // Test 5.1: Contract client connectivity
            const contractClient = new DstackContractClient(TEST_CONFIG.network);
            const networkInfo = await contractClient.getNetworkInfo();
            this.addTestResult('E2E - Contract Connectivity', 
                networkInfo && networkInfo.contractAddress,
                `Connected to contract: ${networkInfo.contractAddress}`
            );

            // Test 5.2: Component integration
            const accessControl = new AccessControlMiddleware({
                network: TEST_CONFIG.network,
                logLevel: 'error'
            });

            const peerRegistry = new PeerRegistry({
                network: TEST_CONFIG.network,
                logLevel: 'error',
                autoSync: false
            });

            const configManager = new ConfigManager({
                logLevel: 'error',
                autoRestart: false
            });

            configManager.setRegistry(peerRegistry);

            this.addTestResult('E2E - Component Integration', 
                accessControl && peerRegistry && configManager,
                'All components integrated successfully'
            );

            // Test 5.3: Bridge orchestration
            const bridge = new WireGuardContractBridge({
                nodeId: TEST_CONFIG.nodeId,
                privateKey: TEST_CONFIG.privateKey,
                network: TEST_CONFIG.network,
                logLevel: 'error',
                autoStart: false
            });

            await bridge.initialize();
            this.addTestResult('E2E - Bridge Orchestration', 
                bridge.bridgeState.status === 'initialized',
                `Bridge status: ${bridge.bridgeState.status}`
            );

            console.log('✅ End-to-End Integration tests completed\n');

        } catch (error) {
            this.addTestResult('End-to-End Integration', false, error.message);
            console.error('❌ End-to-End Integration test failed:', error.message);
        }
    }

    /**
     * Add test result
     */
    addTestResult(testName, passed, details) {
        this.testResults.push({
            name: testName,
            passed,
            details,
            timestamp: new Date().toISOString()
        });

        const status = passed ? '✅' : '❌';
        console.log(`${status} ${testName}: ${details}`);
    }

    /**
     * Print test summary
     */
    printTestSummary() {
        const totalTests = this.testResults.length;
        const passedTests = this.testResults.filter(r => r.passed).length;
        const failedTests = totalTests - passedTests;
        const duration = Date.now() - this.startTime;

        console.log('\n📊 Test Summary');
        console.log('='.repeat(50));
        console.log(`Total Tests: ${totalTests}`);
        console.log(`Passed: ${passedTests} ✅`);
        console.log(`Failed: ${failedTests} ❌`);
        console.log(`Success Rate: ${((passedTests / totalTests) * 100).toFixed(1)}%`);
        console.log(`Duration: ${duration}ms`);
        console.log('='.repeat(50));

        if (failedTests > 0) {
            console.log('\n❌ Failed Tests:');
            this.testResults
                .filter(r => !r.passed)
                .forEach(r => {
                    console.log(`  - ${r.name}: ${r.details}`);
                });
        }

        console.log('\n🎯 Test Results:');
        this.testResults.forEach(r => {
            const status = r.passed ? '✅' : '❌';
            console.log(`${status} ${r.name}`);
        });

        // Exit with appropriate code
        process.exit(failedTests > 0 ? 1 : 0);
    }
}

// Run tests if this file is executed directly
if (require.main === module) {
    const testSuite = new IntegrationLayerTest();
    testSuite.runAllTests().catch(error => {
        console.error('Test suite execution failed:', error);
        process.exit(1);
    });
}

module.exports = IntegrationLayerTest; 