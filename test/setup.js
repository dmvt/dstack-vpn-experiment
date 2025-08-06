// Test setup file for Jest
const fs = require('fs');
const path = require('path');

// Create test directories if they don't exist
const testDirs = [
  './test-temp',
  './test-temp/wireguard',
  './test-temp/wireguard/backups',
  './test-temp/registry'
];

testDirs.forEach(dir => {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
});

// Global test utilities
global.TEST_CONFIG = {
  network: 'base',
  nodeId: 'test-node-1',
  privateKey: '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
  contractPrivateKey: '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
  testContractAddress: '0x37d2106bADB01dd5bE1926e45D172Cb4203C4186'
};

// Mock console methods to reduce noise in tests
global.console = {
  ...console,
  log: jest.fn(),
  error: jest.fn(),
  warn: jest.fn(),
  info: jest.fn()
};

// Cleanup function to run after each test
afterEach(() => {
  // Clear all mocks
  jest.clearAllMocks();
  
  // Clean up test files
  const testFiles = [
    './test-temp/wireguard/wg0.conf',
    './test-temp/registry/test-registry.json'
  ];
  
  testFiles.forEach(file => {
    if (fs.existsSync(file)) {
      fs.unlinkSync(file);
    }
  });
});

// Global teardown
afterAll(() => {
  // Clean up test directories
  if (fs.existsSync('./test-temp')) {
    fs.rmSync('./test-temp', { recursive: true, force: true });
  }
}); 