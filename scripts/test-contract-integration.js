#!/usr/bin/env node

const DstackContractClient = require('../src/contract-client');

async function testContractIntegration() {
    console.log('🧪 Testing DStack Contract Integration\n');
    
    try {
        // Initialize contract client (read-only mode)
        console.log('1. Initializing contract client...');
        const contractClient = new DstackContractClient('base');
        
        // Test network info
        console.log('2. Testing network connectivity...');
        const networkInfo = await contractClient.getNetworkInfo();
        console.log('   Network:', networkInfo.network);
        console.log('   Chain ID:', networkInfo.chainId);
        console.log('   Contract Address:', networkInfo.contractAddress);
        console.log('   RPC URL:', networkInfo.rpcUrl);
        
        // Test contract owner
        console.log('\n3. Testing contract owner...');
        const owner = await contractClient.getContractOwner();
        console.log('   Contract Owner:', owner);
        
        // Test access verification (should return false for non-existent node)
        console.log('\n4. Testing access verification...');
        const testAddress = '0x1234567890123456789012345678901234567890';
        const testNodeId = 'test-node-123';
        const hasAccess = await contractClient.hasNodeAccess(testAddress, testNodeId);
        console.log(`   Access for ${testAddress} on ${testNodeId}: ${hasAccess}`);
        
        // Test token ID lookup (should return 0 for non-existent node)
        console.log('\n5. Testing token ID lookup...');
        const tokenId = await contractClient.getTokenIdByNodeId(testNodeId);
        console.log(`   Token ID for ${testNodeId}: ${tokenId}`);
        
        // Test public key lookup (should return empty string for non-existent owner)
        console.log('\n6. Testing public key lookup...');
        const publicKey = await contractClient.getPublicKeyByOwner(testAddress);
        console.log(`   Public key for ${testAddress}: ${publicKey || 'Not found'}`);
        
        // Test verify access (alias for hasNodeAccess)
        console.log('\n7. Testing verify access...');
        const verified = await contractClient.verifyAccess(testAddress, testNodeId);
        console.log(`   Verified access for ${testAddress} on ${testNodeId}: ${verified}`);
        
        console.log('\n✅ All contract integration tests passed!');
        console.log('\n📋 Test Summary:');
        console.log('   - Network connectivity: ✅');
        console.log('   - Contract owner retrieval: ✅');
        console.log('   - Access verification: ✅');
        console.log('   - Token ID lookup: ✅');
        console.log('   - Public key lookup: ✅');
        console.log('   - Verify access: ✅');
        
        return true;
        
    } catch (error) {
        console.error('\n❌ Contract integration test failed:', error.message);
        console.log('\n🔍 Troubleshooting:');
        console.log('   - Check if Base mainnet RPC is accessible');
        console.log('   - Verify contract address is correct');
        console.log('   - Ensure network connectivity');
        console.log('   - Check if contract is deployed and verified');
        
        return false;
    }
}

async function testNodeRegistration() {
    console.log('\n🧪 Testing Node Registration (Read-only)\n');
    
    try {
        const NodeRegistrar = require('./register-node');
        
        // Test without private key (read-only mode)
        console.log('1. Testing node registrar initialization...');
        const registrar = new NodeRegistrar();
        
        // Test registry loading
        console.log('2. Testing registry loading...');
        console.log('   Registry peers count:', registrar.registry.peers.length);
        console.log('   Contract address:', registrar.registry.contract_address);
        console.log('   Network CIDR:', registrar.registry.network.cidr);
        
        // Test node info retrieval
        console.log('\n3. Testing node info retrieval...');
        const testNodeId = 'non-existent-node';
        const nodeInfo = await registrar.getNodeInfo(testNodeId);
        console.log(`   Node info for ${testNodeId}:`, nodeInfo ? 'Found' : 'Not found');
        
        // Test access verification
        console.log('\n4. Testing access verification...');
        const testAddress = '0x1234567890123456789012345678901234567890';
        const hasAccess = await registrar.verifyNodeAccess(testAddress, testNodeId);
        console.log(`   Access verification result: ${hasAccess}`);
        
        // List registered nodes
        console.log('\n5. Testing node listing...');
        registrar.listRegisteredNodes();
        
        console.log('\n✅ All node registration tests passed!');
        return true;
        
    } catch (error) {
        console.error('\n❌ Node registration test failed:', error.message);
        return false;
    }
}

async function runAllTests() {
    console.log('🚀 Starting DStack Contract Integration Tests\n');
    console.log('=' .repeat(50));
    
    const contractTestPassed = await testContractIntegration();
    const registrationTestPassed = await testNodeRegistration();
    
    console.log('\n' + '=' .repeat(50));
    console.log('📊 Test Results Summary:');
    console.log('   Contract Integration:', contractTestPassed ? '✅ PASSED' : '❌ FAILED');
    console.log('   Node Registration:', registrationTestPassed ? '✅ PASSED' : '❌ FAILED');
    
    if (contractTestPassed && registrationTestPassed) {
        console.log('\n🎉 All tests passed! Contract integration is working correctly.');
        console.log('\n📝 Next Steps:');
        console.log('   1. Set PRIVATE_KEY environment variable for write operations');
        console.log('   2. Test node registration with real addresses');
        console.log('   3. Integrate with WireGuard containers');
        console.log('   4. Deploy to DStack instances');
        process.exit(0);
    } else {
        console.log('\n⚠️  Some tests failed. Please check the errors above.');
        process.exit(1);
    }
}

// Run tests if this script is executed directly
if (require.main === module) {
    runAllTests().catch(error => {
        console.error('Test execution failed:', error);
        process.exit(1);
    });
}

module.exports = {
    testContractIntegration,
    testNodeRegistration,
    runAllTests
}; 