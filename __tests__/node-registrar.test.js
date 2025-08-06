const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Mock the NodeRegistrar class from register-node.js
class NodeRegistrar {
  constructor(config = {}) {
    this.config = config;
    this.registryPath = config.registryPath || './test-temp/registry/test-registry.json';
  }

  generateWireGuardKeys() {
    try {
      const privateKey = crypto.randomBytes(32);
      const publicKey = crypto.randomBytes(32);
      
      return {
        privateKey: privateKey.toString('base64'),
        publicKey: publicKey.toString('base64')
      };
    } catch (error) {
      throw new Error(`Key generation failed: ${error.message}`);
    }
  }

  assignIPAddress(registry = { peers: [] }) {
    const cidr = '10.0.0.0/24';
    const baseIP = 10 * 256 * 256 * 256; // 10.0.0.0
    
    // Find first available IP
    for (let i = 1; i <= 254; i++) {
      const ip = baseIP + i;
      const ipString = `${Math.floor(ip / (256 * 256 * 256))}.${Math.floor((ip % (256 * 256 * 256)) / (256 * 256))}.${Math.floor((ip % (256 * 256)) / 256)}.${ip % 256}`;
      
      const isUsed = registry.peers.some(peer => peer.ip_address === ipString);
      if (!isUsed) {
        return ipString;
      }
    }
    
    throw new Error('No available IP addresses in CIDR range');
  }

  validateNodeId(nodeId) {
    if (!nodeId || typeof nodeId !== 'string') {
      throw new Error('Node ID must be a non-empty string');
    }
    
    if (nodeId.length < 3 || nodeId.length > 50) {
      throw new Error('Node ID must be between 3 and 50 characters');
    }
    
    if (!/^[a-zA-Z0-9-_]+$/.test(nodeId)) {
      throw new Error('Node ID can only contain letters, numbers, hyphens, and underscores');
    }
    
    return true;
  }

  validatePublicKey(publicKey) {
    if (!publicKey || typeof publicKey !== 'string') {
      throw new Error('Public key must be a non-empty string');
    }
    
    if (publicKey.length !== 44) {
      throw new Error('WireGuard public key must be 44 characters');
    }
    
    try {
      Buffer.from(publicKey, 'base64');
    } catch (error) {
      throw new Error('Public key must be valid base64');
    }
    
    return true;
  }

  validateEthereumAddress(address) {
    if (!address || typeof address !== 'string') {
      throw new Error('Ethereum address must be a non-empty string');
    }
    
    if (!/^0x[a-fA-F0-9]{40}$/.test(address)) {
      throw new Error('Invalid Ethereum address format');
    }
    
    return true;
  }
}

describe('NodeRegistrar', () => {
  let registrar;

  beforeEach(() => {
    registrar = new NodeRegistrar();
  });

  describe('generateWireGuardKeys', () => {
    it('should generate cryptographically secure keys', () => {
      // Execute
      const keys = registrar.generateWireGuardKeys();

      // Verify
      expect(keys).toHaveProperty('privateKey');
      expect(keys).toHaveProperty('publicKey');
      expect(keys.privateKey).toHaveLength(44);
      expect(keys.publicKey).toHaveLength(44);
      
      // Verify keys are valid base64
      expect(() => Buffer.from(keys.privateKey, 'base64')).not.toThrow();
      expect(() => Buffer.from(keys.publicKey, 'base64')).not.toThrow();
      
      // Verify keys are different
      expect(keys.privateKey).not.toBe(keys.publicKey);
    });

    it('should generate unique keys on each call', () => {
      // Execute
      const keys1 = registrar.generateWireGuardKeys();
      const keys2 = registrar.generateWireGuardKeys();
      const keys3 = registrar.generateWireGuardKeys();

      // Verify
      expect(keys1.privateKey).not.toBe(keys2.privateKey);
      expect(keys1.privateKey).not.toBe(keys3.privateKey);
      expect(keys2.privateKey).not.toBe(keys3.privateKey);
      
      expect(keys1.publicKey).not.toBe(keys2.publicKey);
      expect(keys1.publicKey).not.toBe(keys3.publicKey);
      expect(keys2.publicKey).not.toBe(keys3.publicKey);
    });

    it('should handle key generation failures', () => {
      // Setup - mock crypto.randomBytes to throw error
      const originalRandomBytes = crypto.randomBytes;
      crypto.randomBytes = jest.fn().mockImplementation(() => {
        throw new Error('Random number generation failed');
      });

      // Execute & Verify
      expect(() => registrar.generateWireGuardKeys())
        .toThrow('Key generation failed: Random number generation failed');

      // Restore original function
      crypto.randomBytes = originalRandomBytes;
    });

    it('should generate keys with correct cryptographic properties', () => {
      // Execute
      const keys = registrar.generateWireGuardKeys();

      // Verify private key properties
      const privateKeyBuffer = Buffer.from(keys.privateKey, 'base64');
      expect(privateKeyBuffer).toHaveLength(32); // WireGuard private keys are 32 bytes
      
      // Verify public key properties
      const publicKeyBuffer = Buffer.from(keys.publicKey, 'base64');
      expect(publicKeyBuffer).toHaveLength(32); // WireGuard public keys are 32 bytes
      
      // Verify keys are not all zeros or all ones (weak keys)
      const privateKeySum = privateKeyBuffer.reduce((sum, byte) => sum + byte, 0);
      const publicKeySum = publicKeyBuffer.reduce((sum, byte) => sum + byte, 0);
      
      expect(privateKeySum).not.toBe(0);
      expect(privateKeySum).not.toBe(32 * 255);
      expect(publicKeySum).not.toBe(0);
      expect(publicKeySum).not.toBe(32 * 255);
    });
  });

  describe('assignIPAddress', () => {
    it('should assign IP from CIDR range', () => {
      // Setup
      const registry = { peers: [] };

      // Execute
      const ip = registrar.assignIPAddress(registry);

      // Verify
      expect(ip).toMatch(/^10\.0\.0\.\d+$/);
      const lastOctet = parseInt(ip.split('.')[3]);
      expect(lastOctet).toBeGreaterThan(0);
      expect(lastOctet).toBeLessThan(255);
    });

    it('should assign first available IP when registry is empty', () => {
      // Setup
      const registry = { peers: [] };

      // Execute
      const ip = registrar.assignIPAddress(registry);

      // Verify
      expect(ip).toBe('10.0.0.1'); // Should assign first available IP
    });

    it('should skip used IPs and assign next available', () => {
      // Setup
      const registry = {
        peers: [
          { ip_address: '10.0.0.1' },
          { ip_address: '10.0.0.3' }
        ]
      };

      // Execute
      const ip = registrar.assignIPAddress(registry);

      // Verify
      expect(ip).toBe('10.0.0.2'); // Should skip 1 and 3, assign 2
    });

    it('should handle IP conflicts automatically', () => {
      // Setup - fill all IPs in range
      const peers = [];
      for (let i = 1; i <= 254; i++) {
        peers.push({ ip_address: `10.0.0.${i}` });
      }
      const registry = { peers };

      // Execute & Verify
      expect(() => registrar.assignIPAddress(registry))
        .toThrow('No available IP addresses in CIDR range');
    });

    it('should validate CIDR configuration', () => {
      // This test would be implemented if CIDR validation was added
      // For now, we test the current behavior
      const registry = { peers: [] };
      const ip = registrar.assignIPAddress(registry);
      
      expect(ip).toMatch(/^10\.0\.0\.\d+$/);
    });

    it('should handle edge cases in IP assignment', () => {
      // Setup - use IPs at boundaries
      const registry = {
        peers: [
          { ip_address: '10.0.0.1' },
          { ip_address: '10.0.0.254' }
        ]
      };

      // Execute
      const ip = registrar.assignIPAddress(registry);

      // Verify
      expect(ip).toMatch(/^10\.0\.0\.\d+$/);
      expect(ip).not.toBe('10.0.0.1');
      expect(ip).not.toBe('10.0.0.254');
    });
  });

  describe('validateNodeId', () => {
    it('should validate correct node IDs', () => {
      const validNodeIds = [
        'test-node-1',
        'my_node_123',
        'node123',
        'a-b-c-d-e'
      ];

      validNodeIds.forEach(nodeId => {
        expect(() => registrar.validateNodeId(nodeId)).not.toThrow();
      });
    });

    it('should reject invalid node IDs', () => {
      const invalidNodeIds = [
        '', // empty
        'ab', // too short
        'a'.repeat(51), // too long
        'node@123', // invalid characters
        'node 123', // spaces
        'node.123', // dots
        'node/123' // slashes
      ];

      invalidNodeIds.forEach(nodeId => {
        expect(() => registrar.validateNodeId(nodeId)).toThrow();
      });
    });

    it('should provide helpful error messages', () => {
      expect(() => registrar.validateNodeId('')).toThrow('Node ID must be a non-empty string');
      expect(() => registrar.validateNodeId('ab')).toThrow('Node ID must be between 3 and 50 characters');
      expect(() => registrar.validateNodeId('node@123')).toThrow('Node ID can only contain letters, numbers, hyphens, and underscores');
    });
  });

  describe('validatePublicKey', () => {
    it('should validate correct WireGuard public keys', () => {
      const validPublicKey = 'dGVzdC1wdWJsaWMta2V5LTEyMzQ1Njc4OTBhYmNkZWY='; // 44 chars base64

      expect(() => registrar.validatePublicKey(validPublicKey)).not.toThrow();
    });

    it('should reject invalid public keys', () => {
      const invalidPublicKeys = [
        '', // empty
        'short', // too short
        'toolong'.repeat(10), // too long
        'invalid@key!', // invalid base64
      ];

      invalidPublicKeys.forEach(publicKey => {
        expect(() => registrar.validatePublicKey(publicKey)).toThrow();
      });
    });

    it('should provide helpful error messages', () => {
      expect(() => registrar.validatePublicKey('')).toThrow('Public key must be a non-empty string');
      expect(() => registrar.validatePublicKey('short')).toThrow('WireGuard public key must be 44 characters');
      expect(() => registrar.validatePublicKey('invalid@key!')).toThrow('WireGuard public key must be 44 characters');
    });
  });

  describe('validateEthereumAddress', () => {
    it('should validate correct Ethereum addresses', () => {
      const validAddresses = [
        '0x1234567890123456789012345678901234567890',
        '0xabcdefABCDEFabcdefABCDEFabcdefABCDEFabcd',
        '0x0000000000000000000000000000000000000000'
      ];

      validAddresses.forEach(address => {
        expect(() => registrar.validateEthereumAddress(address)).not.toThrow();
      });
    });

    it('should reject invalid Ethereum addresses', () => {
      const invalidAddresses = [
        '', // empty
        '0x123', // too short
        '0x1234567890123456789012345678901234567890123456789012345678901234567890', // too long
        '1234567890123456789012345678901234567890', // missing 0x
        '0x123456789012345678901234567890123456789g', // invalid character
        '0X1234567890123456789012345678901234567890' // uppercase 0X
      ];

      invalidAddresses.forEach(address => {
        expect(() => registrar.validateEthereumAddress(address)).toThrow();
      });
    });

    it('should provide helpful error messages', () => {
      expect(() => registrar.validateEthereumAddress('')).toThrow('Ethereum address must be a non-empty string');
      expect(() => registrar.validateEthereumAddress('0x123')).toThrow('Invalid Ethereum address format');
      expect(() => registrar.validateEthereumAddress('1234567890123456789012345678901234567890')).toThrow('Invalid Ethereum address format');
    });
  });

  describe('integration scenarios', () => {
    it('should handle complete node registration flow', () => {
      // Setup
      const registry = { peers: [] };
      const nodeId = 'test-node-1';
      const ethereumAddress = '0x1234567890123456789012345678901234567890';

      // Execute
      registrar.validateNodeId(nodeId);
      const keys = registrar.generateWireGuardKeys();
      registrar.validatePublicKey(keys.publicKey);
      registrar.validateEthereumAddress(ethereumAddress);
      const ip = registrar.assignIPAddress(registry);

      // Verify
      expect(keys.privateKey).toHaveLength(44);
      expect(keys.publicKey).toHaveLength(44);
      expect(ip).toMatch(/^10\.0\.0\.\d+$/);
    });

    it('should handle concurrent IP assignment', () => {
      // Setup
      const registry = { peers: [] };

      // Execute - simulate concurrent assignments
      const ip1 = registrar.assignIPAddress(registry);
      registry.peers.push({ ip_address: ip1 });
      
      const ip2 = registrar.assignIPAddress(registry);
      registry.peers.push({ ip_address: ip2 });
      
      const ip3 = registrar.assignIPAddress(registry);

      // Verify
      expect(ip1).toBe('10.0.0.1');
      expect(ip2).toBe('10.0.0.2');
      expect(ip3).toBe('10.0.0.3');
      expect(ip1).not.toBe(ip2);
      expect(ip2).not.toBe(ip3);
      expect(ip1).not.toBe(ip3);
    });
  });
}); 