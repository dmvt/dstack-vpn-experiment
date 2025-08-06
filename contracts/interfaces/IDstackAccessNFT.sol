// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDstackAccessNFT {
    struct DstackNodeAccess {
        string wireguardPublicKey;
        string nodeId;
        uint256 createdAt;
        bool isActive;
    }

    event NodeAccessGranted(uint256 indexed tokenId, string nodeId, address indexed owner, string wireguardPublicKey);
    event NodeAccessRevoked(uint256 indexed tokenId, string nodeId);
    event NodeAccessTransferred(uint256 indexed tokenId, address indexed from, address indexed to);
    event PublicKeyUpdated(address indexed owner, string wireguardPublicKey);
    event OwnershipTransferInitiated(address indexed previousOwner, address indexed newOwner);

    function mintNodeAccess(
        address to,
        string memory nodeId,
        string memory wireguardPublicKey,
        string memory tokenURI
    ) external returns (uint256);

    function revokeNodeAccess(uint256 tokenId) external;
    
    function getNodeAccess(uint256 tokenId) external view returns (
        string memory nodeId,
        string memory wireguardPublicKey,
        uint256 createdAt,
        bool isActive
    );

    function hasNodeAccess(address user, string memory nodeId) external view returns (bool);
    
    function getTokenIdByNodeId(string memory nodeId) external view returns (uint256);
    
    function verifyAccess(address user, string memory nodeId) external view returns (bool);
    
    function getPublicKeyByOwner(address owner) external view returns (string memory);
    
    function getPublicKeyByTokenId(uint256 tokenId) external view returns (string memory);
    
    function ownerOf(uint256 tokenId) external view returns (address);
    
    function tokenURI(uint256 tokenId) external view returns (string memory);
    
    function transferContractOwnership(address newOwner) external;
} 