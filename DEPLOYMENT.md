# DStack VPN Deployment Guide

This guide walks you through deploying the DStack VPN system with a DigitalOcean hub and DStack spokes.

## Prerequisites

- **DigitalOcean account** with API access
- **DStack/Phala nodes** (3 nodes minimum)
- **WireGuard tools** installed locally for key generation
- **SSH access** to your DigitalOcean droplet

## Step 1: Generate WireGuard Keys and Configurations

Run the key generation script to create all necessary WireGuard configurations:

```bash
./scripts/generate-keys.sh
```

This creates:
- `config/hub/wg0.conf` - Hub configuration (IP: 10.88.0.1)
- `config/node-a/wg0.conf` - Node A configuration (IP: 10.88.0.11)
- `config/node-b/wg0.conf` - Node B configuration (IP: 10.88.0.12)
- `config/node-c/wg0.conf` - Node C configuration (IP: 10.88.0.13)
- `.env.template` - Environment configuration template

## Step 2: Deploy DigitalOcean Hub

### 2.1 Create DigitalOcean Droplet

1. **Create a new droplet** in NYC region:
   - **OS**: Ubuntu 24.04 LTS
   - **Size**: Regular Intel/AMD, 1 vCPU, 1GB RAM, 25GB SSD
   - **Region**: NYC (New York)
   - **SSH Keys**: Add your SSH public key

2. **Note the droplet's public IP** - you'll need this for the next steps

### 2.2 Copy Hub Configuration

Copy the hub configuration files to your droplet:

```bash
# Copy hub keys and config
scp config/hub/server.key root@<DROPLET_IP>:/etc/wireguard/
scp config/hub/server.pub root@<DROPLET_IP>:/etc/wireguard/
scp config/hub/wg0.conf root@<DROPLET_IP>:/etc/wireguard/

# Copy the provisioning script
scp scripts/provision-hub.sh root@<DROPLET_IP>:/root/
```

### 2.3 Run Hub Provisioning

SSH to your droplet and run the provisioning script:

```bash
ssh root@<DROPLET_IP>
chmod +x /root/provision-hub.sh
./provision-hub.sh
```

The script will:
- Install WireGuard and dependencies
- Configure the WireGuard interface
- Set up nftables firewall
- Enable IP forwarding
- Start the WireGuard service

### 2.4 Verify Hub Status

Check that the hub is running correctly:

```bash
# Check WireGuard status
wg show

# Check firewall rules
nft list ruleset

# Check IP forwarding
sysctl net.ipv4.ip_forward

# Use the status script
vpn-status
```

## Step 3: Configure DStack Spokes

### 3.1 Copy Spoke Configurations

Copy the spoke configurations to your DStack nodes:

```bash
# For each DStack node, copy the appropriate config
scp config/node-a/wg0.conf <USER>@<NODE_A_IP>:/etc/wireguard/
scp config/node-b/wg0.conf <USER>@<NODE_B_IP>:/etc/wireguard/
scp config/node-c/wg0.conf <USER>@<NODE_C_IP>:/etc/wireguard/
```

### 3.2 Update Spoke Configurations

On each DStack node, edit the WireGuard config to include the hub's public IP:

```bash
# Edit the config file
sudo nano /etc/wireguard/wg0.conf

# Replace <HUB_PUBLIC_IP> with your actual DigitalOcean IP
# Example:
# Endpoint = 123.45.67.89:51820
```

### 3.3 Install WireGuard on Spokes

On each DStack node:

```bash
# Install WireGuard
sudo apt update && sudo apt install -y wireguard

# Set proper permissions
sudo chmod 600 /etc/wireguard/wg0.conf

# Start WireGuard
sudo systemctl enable --now wg-quick@wg0
```

### 3.4 Configure Firewall on Spokes

Run the firewall setup script on each DStack node:

```bash
# Copy the firewall script
scp scripts/setup-firewall.sh <USER>@<NODE_IP>:/tmp/

# Run the script (requires root)
sudo /tmp/setup-firewall.sh
```

### 3.5 Deploy Status Service

Deploy the status service on each DStack node:

```bash
# Copy the status service files
scp -r docker/status-service/* <USER>@<NODE_IP>:/opt/dstack-status/

# Build and install the service
ssh <USER>@<NODE_IP>
cd /opt/dstack-status
sudo apt install -y golang-go
CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o dstack-status status.go

# Install the systemd service
sudo cp dstack-status.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now dstack-status
```

## Step 4: Test VPN Connectivity

### 4.1 Verify WireGuard Connections

Check that all nodes are connected:

```bash
# On the hub
wg show

# On each spoke
wg show
```

### 4.2 Test Inter-Node Communication

Test connectivity between spokes:

```bash
# From Node A, ping Node B
ping 10.88.0.12

# From Node B, ping Node C
ping 10.88.0.13

# From Node C, ping Node A
ping 10.88.0.11
```

### 4.3 Test Status Endpoints

Verify the status service is working:

```bash
# Test each node's status endpoint
curl http://<NODE_A_PUBLIC_IP>:8000/status
curl http://<NODE_B_PUBLIC_IP>:8001/status
curl http://<NODE_C_PUBLIC_IP>:8002/status
```

Expected response format:
```json
{
  "node": "node-a",
  "overlay_ip": "10.88.0.11",
  "wg": {
    "interface": "wg0",
    "peer_count": 1,
    "max_last_handshake_sec": 15
  },
  "disk_free_gb": 45.2,
  "time": "2025-01-06T20:00:00.000Z"
}
```

## Step 5: PostgreSQL Cluster Setup

### 5.1 Configure PostgreSQL on Spokes

On each DStack node, configure PostgreSQL to listen on the WireGuard interface:

```bash
# Edit PostgreSQL configuration
sudo nano /etc/postgresql/*/main/postgresql.conf

# Add/modify these lines:
listen_addresses = 'localhost,10.88.0.11'  # Use appropriate IP for each node
port = 5432

# Edit pg_hba.conf to allow connections from overlay network
sudo nano /etc/postgresql/*/main/pg_hba.conf

# Add this line:
host    all             all             10.88.0.0/24           md5

# Restart PostgreSQL
sudo systemctl restart postgresql
```

### 5.2 Test Database Connectivity

Test that nodes can connect to each other's databases:

```bash
# From Node A, connect to Node B's database
psql -h 10.88.0.12 -U postgres -d postgres

# From Node B, connect to Node C's database
psql -h 10.88.0.13 -U postgres -d postgres
```

## Troubleshooting

### Common Issues

1. **WireGuard interface not starting**
   ```bash
   # Check logs
   journalctl -u wg-quick@wg0 --no-pager -n 20
   
   # Check configuration
   wg-quick strip wg0
   ```

2. **Firewall blocking connections**
   ```bash
   # Check firewall status
   nft list ruleset
   
   # Check service status
   systemctl status nftables
   ```

3. **IP forwarding not working**
   ```bash
   # Check sysctl
   sysctl net.ipv4.ip_forward
   
   # Check iptables rules
   iptables -L FORWARD -n -v
   ```

4. **Status service not responding**
   ```bash
   # Check service status
   systemctl status dstack-status
   
   # Check logs
   journalctl -u dstack-status --no-pager -n 20
   
   # Test locally
   curl http://localhost:8000/status
   ```

### Debug Commands

```bash
# Check WireGuard status
wg show

# Check network interfaces
ip addr show wg0

# Check routing
ip route show

# Check firewall rules
nft list ruleset

# Check systemd services
systemctl status wg-quick@wg0
systemctl status nftables
systemctl status dstack-status
```

## Security Considerations

- **Private keys** are never transmitted and remain on each node
- **Hub isolation** prevents the hub from originating traffic to spokes
- **Firewall rules** restrict access to only necessary ports
- **Status endpoints** are read-only and contain no sensitive information
- **VPN traffic** is encrypted using WireGuard's cryptographic protocols

## Next Steps

After successful deployment:

1. **Monitor the system** using the status endpoints
2. **Set up logging** and monitoring
3. **Configure backups** for PostgreSQL data
4. **Test failover scenarios** for high availability
5. **Consider adding** TCP fallback for UDP-blocked networks
