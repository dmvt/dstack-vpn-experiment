const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

class DstackContractClient {
    constructor(network = 'base', privateKey = null) {
        this.config = this.loadConfig();
        this.network = network;
        this.networkConfig = this.config.networks[network];
        
        if (!this.networkConfig) {
            throw new Error(`Network ${network} not found in configuration`);
        }

        // Initialize provider and contract
        this.provider = new ethers.JsonRpcProvider(this.networkConfig.rpcUrl);
        this.contract = this.initializeContract();
        
        if (privateKey) {
            this.signer = new ethers.Wallet(privateKey, this.provider);
            this.contractWithSigner = this.contract.connect(this.signer);
        }

        // Rate limiting configuration
        this.rateLimitConfig = {
            maxRetries: 3,
            baseDelay: 1000, // 1 second
            maxDelay: 10000, // 10 seconds
            backoffMultiplier: 2
        };

        // Cache for frequently accessed data
        this.cache = new Map();
        this.cacheTimeout = 30000; // 30 seconds
    }

    loadConfig() {
        const configPath = path.join(__dirname, '../config/contract-config.json');
        const configData = fs.readFileSync(configPath, 'utf8');
        return JSON.parse(configData);
    }

    initializeContract() {
        const contractABI = this.getContractABI();
        return new ethers.Contract(
            this.networkConfig.contractAddress,
            contractABI,
            this.provider
        );
    }

    getContractABI() {
        // ABI for the DstackAccessNFT contract
        return [
            "function mintNodeAccess(address to, string nodeId, string wireguardPublicKey, string tokenURI) external returns (uint256)",
            "function revokeNodeAccess(uint256 tokenId) external",
            "function getNodeAccess(uint256 tokenId) external view returns (string nodeId, string wireguardPublicKey, uint256 createdAt, bool isActive)",
            "function hasNodeAccess(address user, string nodeId) external view returns (bool)",
            "function getTokenIdByNodeId(string nodeId) external view returns (uint256)",
            "function verifyAccess(address user, string nodeId) external view returns (bool)",
            "function getPublicKeyByOwner(address owner) external view returns (string)",
            "function getPublicKeyByTokenId(uint256 tokenId) external view returns (string)",
            "function ownerOf(uint256 tokenId) external view returns (address)",
            "function tokenURI(uint256 tokenId) external view returns (string)",
            "function transferContractOwnership(address newOwner) external",
            "event NodeAccessGranted(uint256 indexed tokenId, string nodeId, address indexed owner, string wireguardPublicKey)",
            "event NodeAccessRevoked(uint256 indexed tokenId, string nodeId)",
            "event NodeAccessTransferred(uint256 indexed tokenId, address indexed from, address indexed to)",
            "event PublicKeyUpdated(address indexed owner, string wireguardPublicKey)"
        ];
    }

    // Rate limiting and retry logic
    async executeWithRetry(operation, operationName = 'contract operation') {
        let lastError;
        
        for (let attempt = 0; attempt <= this.rateLimitConfig.maxRetries; attempt++) {
            try {
                const result = await operation();
                
                // Clear cache on successful operation
                this.clearCache();
                
                return result;
            } catch (error) {
                lastError = error;
                
                // Check if it's a rate limit error
                if (this.isRateLimitError(error)) {
                    if (attempt < this.rateLimitConfig.maxRetries) {
                        const delay = this.calculateBackoffDelay(attempt);
                        console.warn(`Rate limit hit for ${operationName}, retrying in ${delay}ms (attempt ${attempt + 1}/${this.rateLimitConfig.maxRetries + 1})`);
                        await this.sleep(delay);
                        continue;
                    }
                }
                
                // For non-rate-limit errors, don't retry
                break;
            }
        }
        
        throw new Error(`Failed to execute ${operationName} after ${this.rateLimitConfig.maxRetries + 1} attempts: ${lastError.message}`);
    }

    isRateLimitError(error) {
        return error.code === 'CALL_EXCEPTION' && 
               error.info && 
               error.info.error && 
               error.info.error.code === -32016;
    }

    calculateBackoffDelay(attempt) {
        const delay = this.rateLimitConfig.baseDelay * Math.pow(this.rateLimitConfig.backoffMultiplier, attempt);
        return Math.min(delay, this.rateLimitConfig.maxDelay);
    }

    sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    // Cache management
    getCacheKey(operation, ...args) {
        return `${operation}:${args.join(':')}`;
    }

    getFromCache(key) {
        const cached = this.cache.get(key);
        if (cached && Date.now() - cached.timestamp < this.cacheTimeout) {
            return cached.data;
        }
        return null;
    }

    setCache(key, data) {
        this.cache.set(key, {
            data,
            timestamp: Date.now()
        });
    }

    clearCache() {
        this.cache.clear();
    }

    // Contract interaction methods with retry logic
    async mintNodeAccess(to, nodeId, wireguardPublicKey, tokenURI) {
        if (!this.contractWithSigner) {
            throw new Error('Signer not initialized. Provide private key to mint NFTs.');
        }

        return this.executeWithRetry(async () => {
            const tx = await this.contractWithSigner.mintNodeAccess(
                to,
                nodeId,
                wireguardPublicKey,
                tokenURI
            );
            
            const receipt = await tx.wait();
            console.log(`NFT minted successfully. Token ID: ${receipt.logs[0].args.tokenId}`);
            return receipt.logs[0].args.tokenId;
        }, 'NFT minting');
    }

    async hasNodeAccess(user, nodeId) {
        const cacheKey = this.getCacheKey('hasNodeAccess', user, nodeId);
        const cached = this.getFromCache(cacheKey);
        if (cached !== null) {
            return cached;
        }

        const result = await this.executeWithRetry(async () => {
            const hasAccess = await this.contract.hasNodeAccess(user, nodeId);
            return hasAccess;
        }, 'access verification');

        this.setCache(cacheKey, result);
        return result;
    }

    async getNodeAccess(tokenId) {
        const cacheKey = this.getCacheKey('getNodeAccess', tokenId.toString());
        const cached = this.getFromCache(cacheKey);
        if (cached !== null) {
            return cached;
        }

        const result = await this.executeWithRetry(async () => {
            const access = await this.contract.getNodeAccess(tokenId);
            return {
                nodeId: access[0],
                wireguardPublicKey: access[1],
                createdAt: access[2],
                isActive: access[3]
            };
        }, 'node access retrieval');

        this.setCache(cacheKey, result);
        return result;
    }

    async getPublicKeyByOwner(owner) {
        const cacheKey = this.getCacheKey('getPublicKeyByOwner', owner);
        const cached = this.getFromCache(cacheKey);
        if (cached !== null) {
            return cached;
        }

        const result = await this.executeWithRetry(async () => {
            const publicKey = await this.contract.getPublicKeyByOwner(owner);
            return publicKey;
        }, 'public key retrieval');

        this.setCache(cacheKey, result);
        return result;
    }

    async getTokenIdByNodeId(nodeId) {
        const cacheKey = this.getCacheKey('getTokenIdByNodeId', nodeId);
        const cached = this.getFromCache(cacheKey);
        if (cached !== null) {
            return cached;
        }

        const result = await this.executeWithRetry(async () => {
            const tokenId = await this.contract.getTokenIdByNodeId(nodeId);
            return tokenId;
        }, 'token ID lookup');

        this.setCache(cacheKey, result);
        return result;
    }

    async verifyAccess(user, nodeId) {
        return this.hasNodeAccess(user, nodeId);
    }

    async revokeNodeAccess(tokenId) {
        if (!this.contractWithSigner) {
            throw new Error('Signer not initialized. Provide private key to revoke access.');
        }

        return this.executeWithRetry(async () => {
            const tx = await this.contractWithSigner.revokeNodeAccess(tokenId);
            const receipt = await tx.wait();
            console.log(`Node access revoked successfully for token ID: ${tokenId}`);
            
            // Clear cache after revocation
            this.clearCache();
            
            return receipt;
        }, 'access revocation');
    }

    // Utility methods
    async getContractOwner() {
        try {
            // Use the config owner address since the contract doesn't expose owner() function
            return this.config.ownerAddress;
        } catch (error) {
            console.error('Error getting contract owner:', error);
            return null;
        }
    }

    async getNetworkInfo() {
        return {
            network: this.network,
            chainId: this.networkConfig.chainId,
            contractAddress: this.networkConfig.contractAddress,
            rpcUrl: this.networkConfig.rpcUrl,
            explorerUrl: this.networkConfig.explorerUrl
        };
    }

    // Enhanced error handling
    handleContractError(error, operation) {
        if (this.isRateLimitError(error)) {
            console.warn(`Rate limit exceeded for ${operation}. Consider implementing caching or reducing request frequency.`);
            return { error: 'RATE_LIMIT_EXCEEDED', retryable: true };
        }
        
        if (error.code === 'CALL_EXCEPTION') {
            console.error(`Contract call failed for ${operation}:`, error.message);
            return { error: 'CONTRACT_CALL_FAILED', retryable: false };
        }
        
        if (error.code === 'NETWORK_ERROR') {
            console.error(`Network error for ${operation}:`, error.message);
            return { error: 'NETWORK_ERROR', retryable: true };
        }
        
        console.error(`Unexpected error for ${operation}:`, error.message);
        return { error: 'UNKNOWN_ERROR', retryable: false };
    }

    // Event listeners with error handling
    async listenToNodeAccessGranted(callback) {
        this.contract.on('NodeAccessGranted', (tokenId, nodeId, owner, wireguardPublicKey, event) => {
            try {
                callback({
                    tokenId: tokenId.toString(),
                    nodeId,
                    owner,
                    wireguardPublicKey,
                    blockNumber: event.blockNumber,
                    transactionHash: event.transactionHash
                });
                
                // Clear cache when access is granted
                this.clearCache();
            } catch (error) {
                console.error('Error in NodeAccessGranted callback:', error);
            }
        });
    }

    async listenToNodeAccessRevoked(callback) {
        this.contract.on('NodeAccessRevoked', (tokenId, nodeId, event) => {
            try {
                callback({
                    tokenId: tokenId.toString(),
                    nodeId,
                    blockNumber: event.blockNumber,
                    transactionHash: event.transactionHash
                });
                
                // Clear cache when access is revoked
                this.clearCache();
            } catch (error) {
                console.error('Error in NodeAccessRevoked callback:', error);
            }
        });
    }

    async listenToNodeAccessTransferred(callback) {
        this.contract.on('NodeAccessTransferred', (tokenId, from, to, event) => {
            try {
                callback({
                    tokenId: tokenId.toString(),
                    from,
                    to,
                    blockNumber: event.blockNumber,
                    transactionHash: event.transactionHash
                });
                
                // Clear cache when access is transferred
                this.clearCache();
            } catch (error) {
                console.error('Error in NodeAccessTransferred callback:', error);
            }
        });
    }

    // Health check method
    async healthCheck() {
        try {
            const networkInfo = await this.getNetworkInfo();
            const owner = await this.getContractOwner();
            
            return {
                status: 'healthy',
                network: networkInfo.network,
                contractAddress: networkInfo.contractAddress,
                owner: owner,
                cacheSize: this.cache.size,
                timestamp: new Date().toISOString()
            };
        } catch (error) {
            return {
                status: 'unhealthy',
                error: error.message,
                timestamp: new Date().toISOString()
            };
        }
    }
}

module.exports = DstackContractClient; 