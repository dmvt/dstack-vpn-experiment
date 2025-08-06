const DstackContractClient = require('../src/contract-client');
const { ethers } = require('ethers');

// Mock ethers.js
jest.mock('ethers');

describe('DstackContractClient', () => {
  let client;
  let mockProvider;
  let mockContract;
  let mockWallet;

  beforeEach(() => {
    // Reset all mocks
    jest.clearAllMocks();

    // Setup mock provider
    mockProvider = {
      getNetwork: jest.fn().mockResolvedValue({ chainId: 8453 }),
      getCode: jest.fn().mockResolvedValue('0x1234'),
      getGasPrice: jest.fn().mockResolvedValue(ethers.parseUnits('1', 'gwei')),
      waitForTransaction: jest.fn()
    };

    // Setup mock contract
    mockContract = {
      mintNodeAccess: jest.fn(),
      revokeNodeAccess: jest.fn(),
      hasNodeAccess: jest.fn(),
      getTokenIdByNodeId: jest.fn(),
      getNodeAccess: jest.fn(),
      owner: jest.fn(),
      on: jest.fn(),
      off: jest.fn(),
      connect: jest.fn().mockReturnThis()
    };

    // Setup mock wallet
    mockWallet = {
      address: '0x1234567890123456789012345678901234567890',
      provider: mockProvider,
      signTransaction: jest.fn(),
      sendTransaction: jest.fn()
    };

    // Mock ethers.js constructors
    ethers.JsonRpcProvider.mockReturnValue(mockProvider);
    ethers.Contract.mockReturnValue(mockContract);
    ethers.Wallet.mockReturnValue(mockWallet);

    // Create client instance
    client = new DstackContractClient('base');
  });

  describe('mintNodeAccess', () => {
    it('should mint NFT successfully with valid private key', async () => {
      // Setup
      const nodeId = 'test-node-1';
      const publicKey = 'test-public-key-1234567890abcdef';
      const mockTx = { hash: '0x1234567890abcdef' };
      const mockReceipt = { status: 1, gasUsed: 100000 };

      mockContract.mintNodeAccess.mockResolvedValue(mockTx);
      mockProvider.waitForTransaction.mockResolvedValue(mockReceipt);

      // Create client with private key
      const clientWithKey = new DstackContractClient('base', '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d');

      // Execute
      const result = await clientWithKey.mintNodeAccess(nodeId, publicKey);

      // Verify
      expect(mockContract.mintNodeAccess).toHaveBeenCalledWith(nodeId, publicKey);
      expect(result).toHaveProperty('hash');
      expect(result.hash).toBe('0x1234567890abcdef');
    });

    it('should fail with invalid private key', async () => {
      // Setup
      const nodeId = 'test-node-1';
      const publicKey = 'test-public-key-1234567890abcdef';

      // Mock ethers.Wallet to throw error for invalid private key
      ethers.Wallet.mockImplementation(() => {
        throw new Error('Invalid private key');
      });

      // Execute & Verify
      await expect(async () => {
        const clientWithInvalidKey = new DstackContractClient('base', 'invalid-key');
        await clientWithInvalidKey.mintNodeAccess(nodeId, publicKey);
      }).rejects.toThrow('Invalid private key');
    });

    it('should handle gas estimation failure', async () => {
      // Setup
      const nodeId = 'test-node-1';
      const publicKey = 'test-public-key-1234567890abcdef';

      // Mock gas estimation to fail
      mockContract.mintNodeAccess.mockRejectedValue(new Error('Gas estimation failed'));

      // Create client with private key
      const clientWithKey = new DstackContractClient('base', '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d');

      // Execute & Verify
      await expect(clientWithKey.mintNodeAccess(nodeId, publicKey))
        .rejects.toThrow('Gas estimation failed');
    });

    it('should validate input parameters', async () => {
      // Setup
      const invalidNodeId = '';
      const publicKey = 'test-public-key-1234567890abcdef';

      // Create client with private key
      const clientWithKey = new DstackContractClient('base', '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d');

      // Execute & Verify
      await expect(clientWithKey.mintNodeAccess(invalidNodeId, publicKey))
        .rejects.toThrow('Invalid node ID');
    });
  });

  describe('revokeNodeAccess', () => {
    it('should revoke access successfully', async () => {
      // Setup
      const tokenId = 1;
      const mockTx = { hash: '0xabcdef1234567890' };
      const mockReceipt = { status: 1, gasUsed: 80000 };

      mockContract.revokeNodeAccess.mockResolvedValue(mockTx);
      mockProvider.waitForTransaction.mockResolvedValue(mockReceipt);

      // Create client with private key
      const clientWithKey = new DstackContractClient('base', '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d');

      // Execute
      const result = await clientWithKey.revokeNodeAccess(tokenId);

      // Verify
      expect(mockContract.revokeNodeAccess).toHaveBeenCalledWith(tokenId);
      expect(result).toHaveProperty('hash');
      expect(result.hash).toBe('0xabcdef1234567890');
    });

    it('should fail when revoking non-existent token', async () => {
      // Setup
      const nonExistentTokenId = 999;

      // Mock contract to throw error for non-existent token
      mockContract.revokeNodeAccess.mockRejectedValue(new Error('Token does not exist'));

      // Create client with private key
      const clientWithKey = new DstackContractClient('base', '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d');

      // Execute & Verify
      await expect(clientWithKey.revokeNodeAccess(nonExistentTokenId))
        .rejects.toThrow('Token does not exist');
    });

    it('should verify immediate access denial', async () => {
      // Setup
      const tokenId = 1;
      const mockTx = { hash: '0xabcdef1234567890' };
      const mockReceipt = { status: 1 };

      mockContract.revokeNodeAccess.mockResolvedValue(mockTx);
      mockContract.hasNodeAccess.mockResolvedValue(false); // Access denied after revocation
      mockProvider.waitForTransaction.mockResolvedValue(mockReceipt);

      // Create client with private key
      const clientWithKey = new DstackContractClient('base', '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d');

      // Execute
      await clientWithKey.revokeNodeAccess(tokenId);
      const hasAccess = await clientWithKey.hasNodeAccess('0x1234567890123456789012345678901234567890', 'test-node-1');

      // Verify
      expect(hasAccess).toBe(false);
    });
  });

  describe('rate limiting', () => {
    it('should handle Base RPC rate limits with exponential backoff', async () => {
      // Setup
      const rateLimitError = { code: -32016, message: 'Rate limit exceeded' };
      const successResponse = true;

      // Mock first call to fail with rate limit, second to succeed
      mockContract.hasNodeAccess
        .mockRejectedValueOnce(rateLimitError)
        .mockResolvedValueOnce(successResponse);

      // Execute
      const result = await client.hasNodeAccess('0x1234567890123456789012345678901234567890', 'test-node-1');

      // Verify
      expect(mockContract.hasNodeAccess).toHaveBeenCalledTimes(2);
      expect(result).toBe(true);
    });

    it('should use cache to reduce RPC calls', async () => {
      // Setup
      const address = '0x1234567890123456789012345678901234567890';
      const nodeId = 'test-node-1';
      mockContract.hasNodeAccess.mockResolvedValue(true);

      // Execute - first call should hit RPC, second should hit cache
      const result1 = await client.hasNodeAccess(address, nodeId);
      const result2 = await client.hasNodeAccess(address, nodeId);

      // Verify
      expect(mockContract.hasNodeAccess).toHaveBeenCalledTimes(1); // Only called once
      expect(result1).toBe(true);
      expect(result2).toBe(true);
    });

    it('should handle persistent rate limiting gracefully', async () => {
      // Setup
      const rateLimitError = { code: -32016, message: 'Rate limit exceeded' };
      mockContract.hasNodeAccess.mockRejectedValue(rateLimitError);

      // Execute & Verify
      await expect(client.hasNodeAccess('0x1234567890123456789012345678901234567890', 'test-node-1'))
        .rejects.toThrow('Rate limit exceeded');
    });
  });

  describe('network failure recovery', () => {
    it('should handle network disconnection gracefully', async () => {
      // Setup
      const networkError = new Error('Network connection lost');
      mockContract.hasNodeAccess.mockRejectedValue(networkError);

      // Execute & Verify
      await expect(client.hasNodeAccess('0x1234567890123456789012345678901234567890', 'test-node-1'))
        .rejects.toThrow('Network connection lost');
    });

    it('should fallback to cached data during outages', async () => {
      // Setup
      const address = '0x1234567890123456789012345678901234567890';
      const nodeId = 'test-node-1';
      
      // First call succeeds and caches data
      mockContract.hasNodeAccess.mockResolvedValueOnce(true);
      
      // Second call fails due to network outage
      const networkError = new Error('Network connection lost');
      mockContract.hasNodeAccess.mockRejectedValueOnce(networkError);

      // Execute
      const result1 = await client.hasNodeAccess(address, nodeId); // Should succeed and cache
      const result2 = await client.hasNodeAccess(address, nodeId); // Should use cache

      // Verify
      expect(result1).toBe(true);
      expect(result2).toBe(true); // Should return cached result
    });
  });

  describe('health check', () => {
    it('should return healthy status when all components working', async () => {
      // Setup
      mockProvider.getNetwork.mockResolvedValue({ chainId: 8453 });
      mockContract.owner.mockResolvedValue('0x003268b214719bB1A6C1E873D996c077DbD1BC7E');

      // Execute
      const health = await client.healthCheck();

      // Verify
      expect(health.status).toBe('healthy');
      expect(health.network).toBe('base');
      expect(health.contractAddress).toBeDefined();
      expect(health.owner).toBe('0x003268b214719bB1A6C1E873D996c077DbD1BC7E');
    });

    it('should return unhealthy status when contract is unreachable', async () => {
      // Setup
      mockProvider.getNetwork.mockRejectedValue(new Error('Network error'));

      // Execute
      const health = await client.healthCheck();

      // Verify
      expect(health.status).toBe('unhealthy');
      expect(health.error).toBe('Network error');
    });
  });

  describe('event monitoring', () => {
    it('should setup event listeners correctly', () => {
      // Execute
      client.setupEventListeners();

      // Verify
      expect(mockContract.on).toHaveBeenCalledWith('NodeAccessGranted', expect.any(Function));
      expect(mockContract.on).toHaveBeenCalledWith('NodeAccessRevoked', expect.any(Function));
    });

    it('should handle event processing failures gracefully', () => {
      // Setup
      const mockCallback = jest.fn().mockImplementation(() => {
        throw new Error('Event processing failed');
      });

      // Execute
      client.setupEventListeners();
      
      // Simulate event trigger
      const eventCallbacks = mockContract.on.mock.calls;
      const nodeAccessGrantedCallback = eventCallbacks.find(call => call[0] === 'NodeAccessGranted')[1];
      
      // Should not throw error
      expect(() => nodeAccessGrantedCallback()).not.toThrow();
    });
  });
}); 