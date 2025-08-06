# DStack VPN NFT Metadata

This directory contains the NFT metadata and images for DStack VPN nodes.

## Structure

```
nft-metadata/
├── README.md           # This file
├── node-1.json         # NFT metadata for Node 1
├── node-2.json         # NFT metadata for Node 2
└── images/
    ├── node-1.svg      # SVG image for Node 1
    └── node-2.svg      # SVG image for Node 2
```

## Token URIs

The NFT metadata is served via GitHub's raw content URLs:

- **Node 1**: `https://raw.githubusercontent.com/dmvt/dstack-vpn-experiment/main/nft-metadata/node-1.json`
- **Node 2**: `https://raw.githubusercontent.com/dmvt/dstack-vpn-experiment/main/nft-metadata/node-2.json`

## Metadata Format

Each metadata file follows the ERC721 metadata standard with:

- **name**: Human-readable name for the NFT
- **description**: Detailed description of the node's purpose
- **image**: URL to the node's visual representation
- **external_url**: Link to the project repository
- **attributes**: Key-value pairs describing node properties
- **properties**: Additional metadata including file information and creators

## Attributes

Each node NFT includes the following attributes:

- **Node Type**: VPN Gateway
- **Network**: DStack VPN
- **Protocol**: WireGuard
- **Access Control**: NFT-Based
- **Node ID**: Unique identifier (node-1, node-2)
- **IP Address**: Assigned IP in the VPN network
- **Hostname**: Internal DNS hostname
- **Blockchain**: Base network
- **Security**: TEE-Protected

## Images

The SVG images represent:
- Network connectivity and VPN concepts
- Security features (lock icon)
- Node identification
- DStack branding

## Usage

These metadata files are used when minting NFTs for DStack VPN nodes. The token URI points to the JSON metadata, which in turn references the SVG images.

## Adding New Nodes

To add a new node:

1. Create `node-X.json` metadata file
2. Create `node-X.svg` image file
3. Update the deployment scripts to include the new node
4. Update this README

## Security

- Metadata is publicly accessible via GitHub
- No sensitive information is included in metadata
- Private keys and access credentials are stored separately
- NFT ownership controls actual VPN access 