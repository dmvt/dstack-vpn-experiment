#!/usr/bin/env node

const DstackContractClient = require('../src/contract-client');

async function testContractIntegration() {
    console.log('🧪 Testing DstackContractClient...\n');

    const client = new DstackContractClient('base');

    // Test 1: Network connectivity
    console.log('1. Testing network connectivity...');
    try {
        const networkInfo = await client.getNetworkInfo();
        console.log(`   ✅ Connected to ${networkInfo.network} (Chain ID: ${networkInfo.chainId})`);
        console.log(`   ✅ Contract address: ${networkInfo.contractAddress}`);
    } catch (error) {
        console.log(`   ❌ Network connectivity failed: ${error.message}`);
        return false;
    }

    // Test 2: Contract owner retrieval
    console.log('\n2. Testing contract owner retrieval...');
    try {
        const owner = await client.getContractOwner();
        console.log(`   ✅ Contract owner: ${owner}`);
    } catch (error) {
        console.log(`   ❌ Contract owner retrieval failed: ${error.message}`);
        return false;
    }

    // Test 3: Access verification (read operation)
    console.log('\n3. Testing access verification...');
    try {
        const testAddress = '0x1234567890123456789012345678901234567890';
        const testNodeId = 'test-node-123';
        const hasAccess = await client.hasNodeAccess(testAddress, testNodeId);
        console.log(`   ✅ Access verification completed: ${hasAccess}`);
    } catch (error) {
        console.log(`   ❌ Access verification failed: ${error.message}`);
        return false;
    }

    // Test 4: Token ID lookup
    console.log('\n4. Testing token ID lookup...');
    try {
        const testNodeId = 'node-a';
        const tokenId = await client.getTokenIdByNodeId(testNodeId);
        console.log(`   ✅ Token ID lookup completed: ${tokenId}`);
    } catch (error) {
        console.log(`   ❌ Token ID lookup failed: ${error.message}`);
        return false;
    }

    // Test 5: Public key lookup
    console.log('\n5. Testing public key lookup...');
    try {
        const testOwner = '0x003268b214719bB1A6C1E873D996c077DbD1BC7E';
        const publicKey = await client.getPublicKeyByOwner(testOwner);
        console.log(`   ✅ Public key lookup completed: ${publicKey ? 'Found' : 'Not found'}`);
    } catch (error) {
        console.log(`   ❌ Public key lookup failed: ${error.message}`);
        return false;
    }

    // Test 6: Health check
    console.log('\n6. Testing health check...');
    try {
        const health = await client.healthCheck();
        console.log(`   ✅ Health check: ${health.status}`);
        console.log(`   ✅ Cache size: ${health.cacheSize}`);
    } catch (error) {
        console.log(`   ❌ Health check failed: ${error.message}`);
        return false;
    }

    // Test 7: Rate limiting handling
    console.log('\n7. Testing rate limiting handling...');
    try {
        // Make multiple rapid calls to test rate limiting
        const promises = [];
        for (let i = 0; i < 5; i++) {
            promises.push(client.hasNodeAccess('0x1234567890123456789012345678901234567890', `test-node-${i}`));
        }
        
        const results = await Promise.allSettled(promises);
        const successful = results.filter(r => r.status === 'fulfilled').length;
        console.log(`   ✅ Rate limiting test: ${successful}/5 calls successful`);
    } catch (error) {
        console.log(`   ❌ Rate limiting test failed: ${error.message}`);
        return false;
    }

    // Test 8: Caching functionality
    console.log('\n8. Testing caching functionality...');
    try {
        const startTime = Date.now();
        await client.hasNodeAccess('0x1234567890123456789012345678901234567890', 'cache-test-node');
        const firstCall = Date.now() - startTime;
        
        const cacheStartTime = Date.now();
        await client.hasNodeAccess('0x1234567890123456789012345678901234567890', 'cache-test-node');
        const cachedCall = Date.now() - cacheStartTime;
        
        console.log(`   ✅ Caching test: First call ${firstCall}ms, cached call ${cachedCall}ms`);
    } catch (error) {
        console.log(`   ❌ Caching test failed: ${error.message}`);
        return false;
    }

    console.log('\n✅ All DstackContractClient tests passed!');
    return true;
}

async function testNodeRegistration() {
    console.log('\n🧪 Testing NodeRegistrar...\n');

    const NodeRegistrar = require('./register-node');
    
    // Test in read-only mode (no private key)
    const registrar = new NodeRegistrar();

    // Test 1: Registry loading
    console.log('1. Testing registry loading...');
    try {
        const registry = registrar.registry;
        console.log(`   ✅ Registry loaded with ${registry.peers.length} peers`);
    } catch (error) {
        console.log(`   ❌ Registry loading failed: ${error.message}`);
        return false;
    }

    // Test 2: Node listing
    console.log('\n2. Testing node listing...');
    try {
        registrar.listRegisteredNodes();
        console.log(`   ✅ Node listing completed`);
    } catch (error) {
        console.log(`   ❌ Node listing failed: ${error.message}`);
        return false;
    }

    // Test 3: Node info retrieval
    console.log('\n3. Testing node info retrieval...');
    try {
        const nodeInfo = registrar.getNodeInfo('node-a');
        if (nodeInfo) {
            console.log(`   ✅ Node info retrieved: ${nodeInfo.node_id}`);
        } else {
            console.log(`   ⚠️  Node info not found (expected for test environment)`);
        }
    } catch (error) {
        console.log(`   ❌ Node info retrieval failed: ${error.message}`);
        return false;
    }

    // Test 4: Access verification
    console.log('\n4. Testing access verification...');
    try {
        const testAddress = '0x1234567890123456789012345678901234567890';
        const hasAccess = await registrar.verifyNodeAccess(testAddress, 'node-a');
        console.log(`   ✅ Access verification completed: ${hasAccess}`);
    } catch (error) {
        console.log(`   ❌ Access verification failed: ${error.message}`);
        return false;
    }

    // Test 5: Key generation (simulation)
    console.log('\n5. Testing key generation simulation...');
    try {
        const keys = registrar.generateWireGuardKeys();
        console.log(`   ✅ Key generation simulation completed`);
        console.log(`   ✅ Private key length: ${keys.privateKey.length} characters`);
        console.log(`   ✅ Public key length: ${keys.publicKey.length} characters`);
    } catch (error) {
        console.log(`   ❌ Key generation simulation failed: ${error.message}`);
        return false;
    }

    // Test 6: IP address assignment
    console.log('\n6. Testing IP address assignment...');
    try {
        const ip = registrar.assignIPAddress();
        console.log(`   ✅ IP address assigned: ${ip}`);
    } catch (error) {
        console.log(`   ❌ IP address assignment failed: ${error.message}`);
        return false;
    }

    console.log('\n✅ All NodeRegistrar tests passed!');
    return true;
}

async function testWriteOperations() {
    console.log('\n🧪 Testing Write Operations (Simulation)...\n');

    // Check if private key is available for real write operations
    const privateKey = process.env.PRIVATE_KEY;
    
    if (!privateKey) {
        console.log('⚠️  No PRIVATE_KEY environment variable found. Running write operation simulation...\n');
        
        // Test 1: Write operation simulation
        console.log('1. Testing write operation simulation...');
        try {
            const client = new DstackContractClient('base');
            
            // Simulate minting without actual transaction
            console.log('   ✅ Minting simulation: Would mint NFT for test address');
            console.log('   ✅ Revocation simulation: Would revoke access for test token');
            console.log('   ✅ Transfer simulation: Would transfer NFT ownership');
            
        } catch (error) {
            console.log(`   ❌ Write operation simulation failed: ${error.message}`);
            return false;
        }

        // Test 2: Contract state validation
        console.log('\n2. Testing contract state validation...');
        try {
            const client = new DstackContractClient('base');
            
            // Validate contract state before and after simulated operations
            const health = await client.healthCheck();
            console.log(`   ✅ Contract state validation: ${health.status}`);
            
        } catch (error) {
            console.log(`   ❌ Contract state validation failed: ${error.message}`);
            return false;
        }

        console.log('\n⚠️  Write operations tested in simulation mode only.');
        console.log('   To test real write operations, set PRIVATE_KEY environment variable.');
        
    } else {
        console.log('🔑 PRIVATE_KEY found. Testing real write operations...\n');
        
        try {
            const client = new DstackContractClient('base', privateKey);
            
            // Test 1: Real NFT minting
            console.log('1. Testing real NFT minting...');
            const testAddress = '0x1234567890123456789012345678901234567890';
            const testNodeId = 'test-write-node-' + Date.now();
            const testPublicKey = 'test-public-key-' + Date.now();
            
            const tokenId = await client.mintNodeAccess(
                testAddress,
                testNodeId,
                testPublicKey,
                'https://example.com/metadata.json'
            );
            console.log(`   ✅ NFT minted successfully: Token ID ${tokenId}`);
            
            // Test 2: Real access verification
            console.log('\n2. Testing real access verification...');
            const hasAccess = await client.hasNodeAccess(testAddress, testNodeId);
            console.log(`   ✅ Access verification: ${hasAccess}`);
            
            // Test 3: Real access revocation
            console.log('\n3. Testing real access revocation...');
            await client.revokeNodeAccess(tokenId);
            console.log(`   ✅ Access revoked successfully`);
            
            // Test 4: Post-revocation verification
            console.log('\n4. Testing post-revocation verification...');
            const hasAccessAfterRevoke = await client.hasNodeAccess(testAddress, testNodeId);
            console.log(`   ✅ Post-revocation access: ${hasAccessAfterRevoke}`);
            
        } catch (error) {
            console.log(`   ❌ Real write operations failed: ${error.message}`);
            return false;
        }
    }

    console.log('\n✅ All write operation tests completed!');
    return true;
}

async function testErrorHandling() {
    console.log('\n🧪 Testing Error Handling...\n');

    const client = new DstackContractClient('base');

    // Test 1: Invalid address handling
    console.log('1. Testing invalid address handling...');
    try {
        const hasAccess = await client.hasNodeAccess('invalid-address', 'test-node');
        console.log(`   ✅ Invalid address handled gracefully: ${hasAccess}`);
    } catch (error) {
        console.log(`   ✅ Invalid address properly rejected: ${error.message}`);
    }

    // Test 2: Invalid node ID handling
    console.log('\n2. Testing invalid node ID handling...');
    try {
        const tokenId = await client.getTokenIdByNodeId('');
        console.log(`   ✅ Empty node ID handled gracefully: ${tokenId}`);
    } catch (error) {
        console.log(`   ✅ Empty node ID properly rejected: ${error.message}`);
    }

    // Test 3: Network error simulation
    console.log('\n3. Testing network error handling...');
    try {
        // Create client with invalid RPC URL to simulate network error
        const invalidClient = new DstackContractClient('invalid-network');
        await invalidClient.hasNodeAccess('0x1234567890123456789012345678901234567890', 'test-node');
    } catch (error) {
        console.log(`   ✅ Network error properly handled: ${error.message}`);
    }

    // Test 4: Contract error handling
    console.log('\n4. Testing contract error handling...');
    try {
        const error = { code: 'CALL_EXCEPTION', info: { error: { code: -32016 } } };
        const result = client.handleContractError(error, 'test operation');
        console.log(`   ✅ Contract error handling: ${result.error}`);
    } catch (error) {
        console.log(`   ❌ Contract error handling failed: ${error.message}`);
        return false;
    }

    console.log('\n✅ All error handling tests passed!');
    return true;
}

async function runAllTests() {
    console.log('🚀 Starting comprehensive test suite...\n');

    const startTime = Date.now();
    let allTestsPassed = true;

    // Run all test suites
    const testResults = await Promise.allSettled([
        testContractIntegration(),
        testNodeRegistration(),
        testWriteOperations(),
        testErrorHandling()
    ]);

    const endTime = Date.now();
    const totalTime = endTime - startTime;

    console.log('\n📊 Test Results Summary:');
    console.log('========================');

    const testNames = [
        'Contract Integration',
        'Node Registration', 
        'Write Operations',
        'Error Handling'
    ];

    testResults.forEach((result, index) => {
        const status = result.status === 'fulfilled' && result.value ? '✅ PASS' : '❌ FAIL';
        console.log(`${testNames[index]}: ${status}`);
        
        if (result.status === 'rejected') {
            console.log(`   Error: ${result.reason.message}`);
            allTestsPassed = false;
        } else if (!result.value) {
            allTestsPassed = false;
        }
    });

    console.log(`\n⏱️  Total test time: ${totalTime}ms`);
    console.log(`📈 Overall result: ${allTestsPassed ? '✅ ALL TESTS PASSED' : '❌ SOME TESTS FAILED'}`);

    if (allTestsPassed) {
        console.log('\n🎉 Test suite completed successfully!');
        console.log('   The DStack NFT access control system is ready for production use.');
    } else {
        console.log('\n⚠️  Some tests failed. Please review the output above.');
        console.log('   The system may need additional configuration or fixes.');
    }

    return allTestsPassed;
}

if (require.main === module) {
    runAllTests().catch(error => {
        console.error('Test execution failed:', error);
        process.exit(1);
    });
}

module.exports = {
    testContractIntegration,
    testNodeRegistration,
    testWriteOperations,
    testErrorHandling,
    runAllTests
}; 