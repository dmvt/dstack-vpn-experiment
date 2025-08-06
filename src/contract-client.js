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

    // Contract interaction methods
    async mintNodeAccess(to, nodeId, wireguardPublicKey, tokenURI) {
        if (!this.contractWithSigner) {
            throw new Error('Signer not initialized. Provide private key to mint NFTs.');
        }

        try {
            const tx = await this.contractWithSigner.mintNodeAccess(
                to,
                nodeId,
                wireguardPublicKey,
                tokenURI
            );
            
            const receipt = await tx.wait();
            console.log(`NFT minted successfully. Token ID: ${receipt.logs[0].args.tokenId}`);
            return receipt.logs[0].args.tokenId;
        } catch (error) {
            console.error('Error minting NFT:', error);
            throw error;
        }
    }

    async hasNodeAccess(user, nodeId) {
        try {
            const hasAccess = await this.contract.hasNodeAccess(user, nodeId);
            return hasAccess;
        } catch (error) {
            console.error('Error checking node access:', error);
            return false;
        }
    }

    async getNodeAccess(tokenId) {
        try {
            const access = await this.contract.getNodeAccess(tokenId);
            return {
                nodeId: access[0],
                wireguardPublicKey: access[1],
                createdAt: access[2],
                isActive: access[3]
            };
        } catch (error) {
            console.error('Error getting node access:', error);
            throw error;
        }
    }

    async getPublicKeyByOwner(owner) {
        try {
            const publicKey = await this.contract.getPublicKeyByOwner(owner);
            return publicKey;
        } catch (error) {
            console.error('Error getting public key by owner:', error);
            return '';
        }
    }

    async getTokenIdByNodeId(nodeId) {
        try {
            const tokenId = await this.contract.getTokenIdByNodeId(nodeId);
            return tokenId;
        } catch (error) {
            console.error('Error getting token ID by node ID:', error);
            return 0;
        }
    }

    async verifyAccess(user, nodeId) {
        try {
            const verified = await this.contract.verifyAccess(user, nodeId);
            return verified;
        } catch (error) {
            console.error('Error verifying access:', error);
            return false;
        }
    }

    async revokeNodeAccess(tokenId) {
        if (!this.contractWithSigner) {
            throw new Error('Signer not initialized. Provide private key to revoke access.');
        }

        try {
            const tx = await this.contractWithSigner.revokeNodeAccess(tokenId);
            const receipt = await tx.wait();
            console.log(`Node access revoked successfully for token ID: ${tokenId}`);
            return receipt;
        } catch (error) {
            console.error('Error revoking node access:', error);
            throw error;
        }
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

    // Event listeners
    async listenToNodeAccessGranted(callback) {
        this.contract.on('NodeAccessGranted', (tokenId, nodeId, owner, wireguardPublicKey, event) => {
            callback({
                tokenId: tokenId.toString(),
                nodeId,
                owner,
                wireguardPublicKey,
                blockNumber: event.blockNumber,
                transactionHash: event.transactionHash
            });
        });
    }

    async listenToNodeAccessRevoked(callback) {
        this.contract.on('NodeAccessRevoked', (tokenId, nodeId, event) => {
            callback({
                tokenId: tokenId.toString(),
                nodeId,
                blockNumber: event.blockNumber,
                transactionHash: event.transactionHash
            });
        });
    }

    async listenToNodeAccessTransferred(callback) {
        this.contract.on('NodeAccessTransferred', (tokenId, from, to, event) => {
            callback({
                tokenId: tokenId.toString(),
                from,
                to,
                blockNumber: event.blockNumber,
                transactionHash: event.transactionHash
            });
        });
    }
}

module.exports = DstackContractClient; 