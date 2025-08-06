const AccessControlMiddleware = require('../src/access-control');

// Mock the contract client
jest.mock('../src/contract-client');

describe('AccessControlMiddleware', () => {
  let accessControl;
  let mockContractClient;

  beforeEach(() => {
    // Reset all mocks
    jest.clearAllMocks();

    // Setup mock contract client
    mockContractClient = {
      hasNodeAccess: jest.fn(),
      healthCheck: jest.fn().mockResolvedValue({ status: 'healthy' }),
      listenToNodeAccessGranted: jest.fn(),
      listenToNodeAccessRevoked: jest.fn(),
      listenToNodeAccessTransferred: jest.fn()
    };

    // Mock the contract client constructor
    const DstackContractClient = require('../src/contract-client');
    DstackContractClient.mockImplementation(() => mockContractClient);

    // Create access control instance
    accessControl = new AccessControlMiddleware({
      network: 'base',
      privateKey: '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
      logLevel: 'error'
    });
  });

  describe('cache management', () => {
    it('should evict old entries when cache is full', async () => {
      // Setup - fill cache to maximum size
      const maxSize = 1000;
      const testAddress = '0x1234567890123456789012345678901234567890';
      const testNodeId = 'test-node-1';

      // Fill cache with entries
      for (let i = 0; i < maxSize + 10; i++) {
        const address = `0x${i.toString().padStart(40, '0')}`;
        const nodeId = `node-${i}`;
        
        mockContractClient.hasNodeAccess.mockResolvedValue(i % 2 === 0);
        await accessControl.verifyAccess(address, nodeId);
      }

      // Verify cache size is maintained at maximum
      const cacheStats = accessControl.getCacheStats();
      expect(cacheStats.size).toBeLessThanOrEqual(maxSize);
      expect(cacheStats.size).toBeGreaterThan(0);
    });

    it('should handle concurrent access safely', async () => {
      // Setup
      const testAddress = '0x1234567890123456789012345678901234567890';
      const testNodeId = 'test-node-1';
      mockContractClient.hasNodeAccess.mockResolvedValue(true);

      // Execute - multiple concurrent requests
      const promises = [];
      for (let i = 0; i < 10; i++) {
        promises.push(accessControl.verifyAccess(testAddress, testNodeId));
      }

      const results = await Promise.all(promises);

      // Verify all requests completed successfully
      results.forEach(result => {
        expect(result.granted).toBe(true);
      });

      // Verify cache consistency
      const cacheStats = accessControl.getCacheStats();
      expect(cacheStats.size).toBeGreaterThan(0);
    });

    it('should recover from cache corruption', async () => {
      // Setup - simulate cache corruption by directly manipulating cache
      const testAddress = '0x1234567890123456789012345678901234567890';
      const testNodeId = 'test-node-1';
      
      // Corrupt the cache by setting invalid data
      accessControl.cache.set(`${testAddress}-${testNodeId}`, { invalid: 'data' });

      // Execute
      mockContractClient.hasNodeAccess.mockResolvedValue(true);
      const result = await accessControl.verifyAccess(testAddress, testNodeId);

      // Verify cache was cleared and rebuilt
      expect(result.granted).toBe(true);
      
      // Verify cache entry is now valid
      const cacheEntry = accessControl.cache.get(`${testAddress}-${testNodeId}`);
      expect(cacheEntry).toHaveProperty('granted');
      expect(cacheEntry).toHaveProperty('timestamp');
    });

    it('should handle cache key collisions', async () => {
      // Setup - create addresses that could cause hash collisions
      const address1 = '0x1234567890123456789012345678901234567890';
      const address2 = '0x1234567890123456789012345678901234567891';
      const nodeId = 'test-node-1';

      mockContractClient.hasNodeAccess
        .mockResolvedValueOnce(true)  // First call
        .mockResolvedValueOnce(false); // Second call

      // Execute
      const result1 = await accessControl.verifyAccess(address1, nodeId);
      const result2 = await accessControl.verifyAccess(address2, nodeId);

      // Verify both results are correct and cached separately
      expect(result1.granted).toBe(true);
      expect(result2.granted).toBe(false);

      // Verify cache has separate entries
      const cacheStats = accessControl.getCacheStats();
      expect(cacheStats.size).toBe(2);
    });

    it('should handle cache timeout correctly', async () => {
      // Setup
      const testAddress = '0x1234567890123456789012345678901234567890';
      const testNodeId = 'test-node-1';
      mockContractClient.hasNodeAccess.mockResolvedValue(true);

      // Execute first call
      const result1 = await accessControl.verifyAccess(testAddress, testNodeId);
      expect(result1.granted).toBe(true);

      // Simulate cache timeout by manipulating timestamp
      const cacheKey = `${testAddress}-${testNodeId}`;
      const cacheEntry = accessControl.cache.get(cacheKey);
      cacheEntry.timestamp = Date.now() - (accessControl.cacheTimeout + 1000); // Expired

      // Execute second call - should hit contract again
      mockContractClient.hasNodeAccess.mockResolvedValue(false);
      const result2 = await accessControl.verifyAccess(testAddress, testNodeId);

      // Verify second call hit contract (not cache)
      expect(result2.granted).toBe(false);
      expect(mockContractClient.hasNodeAccess).toHaveBeenCalledTimes(2);
    });
  });

  describe('edge case validation', () => {
    it('should handle malformed Ethereum addresses', async () => {
      const invalidAddresses = [
        '',
        'invalid',
        '0x123',
        '0x123456789012345678901234567890123456789g',
        '1234567890123456789012345678901234567890'
      ];

      for (const address of invalidAddresses) {
        await expect(accessControl.verifyAccess(address, 'test-node'))
          .rejects.toThrow();
      }
    });

    it('should handle malformed node IDs', async () => {
      const invalidNodeIds = [
        '',
        'a',
        'a'.repeat(51),
        'node@123',
        'node 123'
      ];

      for (const nodeId of invalidNodeIds) {
        await expect(accessControl.verifyAccess('0x1234567890123456789012345678901234567890', nodeId))
          .rejects.toThrow();
      }
    });

    it('should handle null and undefined inputs', async () => {
      await expect(accessControl.verifyAccess(null, 'test-node'))
        .rejects.toThrow();
      
      await expect(accessControl.verifyAccess(undefined, 'test-node'))
        .rejects.toThrow();
      
      await expect(accessControl.verifyAccess('0x1234567890123456789012345678901234567890', null))
        .rejects.toThrow();
      
      await expect(accessControl.verifyAccess('0x1234567890123456789012345678901234567890', undefined))
        .rejects.toThrow();
    });

    it('should handle very long inputs', async () => {
      const longAddress = '0x' + '1'.repeat(1000);
      const longNodeId = 'a'.repeat(1000);

      await expect(accessControl.verifyAccess(longAddress, 'test-node'))
        .rejects.toThrow();
      
      await expect(accessControl.verifyAccess('0x1234567890123456789012345678901234567890', longNodeId))
        .rejects.toThrow();
    });
  });

  describe('performance under load', () => {
    it('should handle high request volume efficiently', async () => {
      // Setup
      const requests = [];
      const numRequests = 100;
      
      for (let i = 0; i < numRequests; i++) {
        const address = `0x${i.toString().padStart(40, '0')}`;
        const nodeId = `node-${i}`;
        requests.push({ address, nodeId });
      }

      mockContractClient.hasNodeAccess.mockResolvedValue(true);

      // Execute
      const startTime = Date.now();
      const results = await Promise.all(
        requests.map(req => accessControl.verifyAccess(req.address, req.nodeId))
      );
      const endTime = Date.now();

      // Verify all requests completed
      results.forEach(result => {
        expect(result.granted).toBe(true);
      });

      // Verify performance (should complete within reasonable time)
      const duration = endTime - startTime;
      expect(duration).toBeLessThan(5000); // 5 seconds max

      // Verify cache effectiveness
      const cacheStats = accessControl.getCacheStats();
      expect(cacheStats.hits).toBeGreaterThan(0);
    });

    it('should maintain consistent performance under sustained load', async () => {
      // Setup
      const testAddress = '0x1234567890123456789012345678901234567890';
      const testNodeId = 'test-node-1';
      mockContractClient.hasNodeAccess.mockResolvedValue(true);

      const durations = [];

      // Execute multiple rounds of requests
      for (let round = 0; round < 5; round++) {
        const startTime = Date.now();
        
        for (let i = 0; i < 20; i++) {
          await accessControl.verifyAccess(testAddress, testNodeId);
        }
        
        const endTime = Date.now();
        durations.push(endTime - startTime);
      }

      // Verify consistent performance
      const avgDuration = durations.reduce((sum, d) => sum + d, 0) / durations.length;
      const maxDuration = Math.max(...durations);
      const minDuration = Math.min(...durations);

      // Performance should be consistent (not vary too much)
      expect(maxDuration - minDuration).toBeLessThan(1000); // Max 1 second variation
    });

    it('should handle memory usage efficiently', async () => {
      // Setup
      const initialMemory = process.memoryUsage().heapUsed;
      
      // Execute many requests to fill cache
      for (let i = 0; i < 1000; i++) {
        const address = `0x${i.toString().padStart(40, '0')}`;
        const nodeId = `node-${i}`;
        mockContractClient.hasNodeAccess.mockResolvedValue(i % 2 === 0);
        await accessControl.verifyAccess(address, nodeId);
      }

      const finalMemory = process.memoryUsage().heapUsed;
      const memoryIncrease = finalMemory - initialMemory;

      // Memory increase should be reasonable (less than 50MB)
      expect(memoryIncrease).toBeLessThan(50 * 1024 * 1024);
    });
  });

  describe('error handling', () => {
    it('should handle contract client errors gracefully', async () => {
      // Setup
      const testAddress = '0x1234567890123456789012345678901234567890';
      const testNodeId = 'test-node-1';
      
      mockContractClient.hasNodeAccess.mockRejectedValue(new Error('Contract error'));

      // Execute & Verify
      await expect(accessControl.verifyAccess(testAddress, testNodeId))
        .rejects.toThrow('Contract error');
    });

    it('should handle network timeouts', async () => {
      // Setup
      const testAddress = '0x1234567890123456789012345678901234567890';
      const testNodeId = 'test-node-1';
      
      mockContractClient.hasNodeAccess.mockRejectedValue(new Error('Network timeout'));

      // Execute & Verify
      await expect(accessControl.verifyAccess(testAddress, testNodeId))
        .rejects.toThrow('Network timeout');
    });

    it('should handle rate limiting errors', async () => {
      // Setup
      const testAddress = '0x1234567890123456789012345678901234567890';
      const testNodeId = 'test-node-1';
      
      const rateLimitError = { code: -32016, message: 'Rate limit exceeded' };
      mockContractClient.hasNodeAccess.mockRejectedValue(rateLimitError);

      // Execute & Verify
      await expect(accessControl.verifyAccess(testAddress, testNodeId))
        .rejects.toThrow('Rate limit exceeded');
    });

    it('should provide meaningful error messages', async () => {
      // Setup
      mockContractClient.hasNodeAccess.mockRejectedValue(new Error('Custom error message'));

      // Execute & Verify
      try {
        await accessControl.verifyAccess('0x1234567890123456789012345678901234567890', 'test-node');
      } catch (error) {
        expect(error.message).toContain('Custom error message');
      }
    });
  });

  describe('statistics and monitoring', () => {
    it('should track cache statistics correctly', async () => {
      // Setup
      const testAddress = '0x1234567890123456789012345678901234567890';
      const testNodeId = 'test-node-1';
      mockContractClient.hasNodeAccess.mockResolvedValue(true);

      // Execute - first call (cache miss)
      await accessControl.verifyAccess(testAddress, testNodeId);
      
      // Execute - second call (cache hit)
      await accessControl.verifyAccess(testAddress, testNodeId);

      // Verify statistics
      const stats = accessControl.getStats();
      expect(stats.totalRequests).toBe(2);
      expect(stats.grantedAccess).toBe(2);
      expect(stats.deniedAccess).toBe(0);
      expect(stats.errors).toBe(0);

      const cacheStats = accessControl.getCacheStats();
      expect(cacheStats.hits).toBe(1);
      expect(cacheStats.misses).toBe(1);
      expect(cacheStats.hitRate).toBe(0.5);
    });

    it('should track access decisions correctly', async () => {
      // Setup
      const testAddress = '0x1234567890123456789012345678901234567890';
      const testNodeId = 'test-node-1';
      
      mockContractClient.hasNodeAccess
        .mockResolvedValueOnce(true)   // First call - granted
        .mockResolvedValueOnce(false); // Second call - denied

      // Execute
      await accessControl.verifyAccess(testAddress, testNodeId);
      await accessControl.verifyAccess(testAddress, testNodeId);

      // Verify statistics
      const stats = accessControl.getStats();
      expect(stats.totalRequests).toBe(2);
      expect(stats.grantedAccess).toBe(1);
      expect(stats.deniedAccess).toBe(1);
    });

    it('should track errors correctly', async () => {
      // Setup
      const testAddress = '0x1234567890123456789012345678901234567890';
      const testNodeId = 'test-node-1';
      
      mockContractClient.hasNodeAccess.mockRejectedValue(new Error('Test error'));

      // Execute
      try {
        await accessControl.verifyAccess(testAddress, testNodeId);
      } catch (error) {
        // Expected to throw
      }

      // Verify statistics
      const stats = accessControl.getStats();
      expect(stats.totalRequests).toBe(1);
      expect(stats.errors).toBe(1);
    });

    it('should reset statistics correctly', async () => {
      // Setup
      const testAddress = '0x1234567890123456789012345678901234567890';
      const testNodeId = 'test-node-1';
      mockContractClient.hasNodeAccess.mockResolvedValue(true);

      // Execute some requests
      await accessControl.verifyAccess(testAddress, testNodeId);
      await accessControl.verifyAccess(testAddress, testNodeId);

      // Reset statistics
      accessControl.resetStats();

      // Verify statistics are reset
      const stats = accessControl.getStats();
      expect(stats.totalRequests).toBe(0);
      expect(stats.grantedAccess).toBe(0);
      expect(stats.deniedAccess).toBe(0);
      expect(stats.errors).toBe(0);
    });
  });
}); 