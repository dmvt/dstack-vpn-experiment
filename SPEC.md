# Dstack VPN — Minimal “Single‑Primary Hub” Spec (v3‑lite, NYC)

> Goal: **Ship a working VPN now** with minimal moving parts. A **single WireGuard hub** on a tiny **DigitalOcean NYC** droplet; **three Dstack spokes** connect **outbound only** to the hub. The **PostgreSQL cluster lives entirely on Dstack** (no DB on the DO node). No NFTs, no service discovery, no Mullvad/TCP encapsulation.

---

## 1) Scope & Non‑Goals

**In‑scope (v3‑lite)**
- One **DigitalOcean hub** (WireGuard server) in **NYC**.
- **3 Dstack/Phala nodes** as **WireGuard clients** (spokes) that auto‑connect **outbound** to the hub.
- **PostgreSQL cluster runs entirely on Dstack** (primary+replicas); the hub provides private L3 between spokes only.
- Basic **firewalling** and optional **split‑horizon DNS**.
- **Local backups only**: each Dstack spoke stores its own backups on local disk.

**Out of scope (for now)**
- NFT/contract gating, Registrar service, service discovery.
- Any DB service on the hub; Patroni/etcd config belongs to the Dstack stack.
- HAProxy/PgBouncer on the hub (DB access remains inside Dstack).
- TCP encapsulation; we use **native UDP**. (Per‑node TCP fallback can be added later.)

---

## 2) Topology

```mermaid
flowchart LR
  subgraph Cloud[DigitalOcean (NYC)]
    HUB[WireGuard Hub (Droplet)]
  end

  subgraph Dstack[Dstack/Phala]
    A[Spoke A]
    B[Spoke B]
    C[Spoke C]
  end

  A -- WG UDP/51820 (outbound) --> HUB
  B -- WG UDP/51820 (outbound) --> HUB
  C -- WG UDP/51820 (outbound) --> HUB

  subgraph Postgres[Dstack-only: PostgreSQL Cluster]
    P1[(PG Primary)]
    P2[(PG Replica)]
    P3[(PG Replica)]
  end

  A --- P1
  B --- P2
  C --- P3
```

- **Addressing**: WireGuard overlay `10.88.0.0/24`.
- **IP plan**: Hub `10.88.0.1`; spokes `10.88.0.11`, `10.88.0.12`, `10.88.0.13`.
- **Roles**:
  - **Hub**: static public IP; listens on `51820/udp`. **Routes inter‑spoke traffic** (L3 forwarding); **no NAT**, **no DB**.
  - **Spokes**: Dstack nodes **initiate** the tunnel to the hub (hole‑punch via outbound). No inbound exposure.

---

## 3) Components

- **WireGuard** (`wg`/`wg-quick`) on all nodes. Optional **wg‑easy** on hub for peer lifecycle.
- **Firewall**: 
  - **Hub**: allow `51820/udp`, `22/tcp` (admin). Drop everything else.
  - **Spokes (Dstack)**: external inbound is restricted by Dstack; we **do not** open SSH or WG externally. We **only** expose a read‑only **status page on `8000/tcp`** to the Internet.
- **PostgreSQL cluster** (primary + replicas) runs on Dstack spokes only.
- **Backups**: each spoke runs **local backup jobs** to its own disk. (Offsite later.)
- **Status service (spokes)**: lightweight HTTP server on `:8000` exposing **read‑only** health (WireGuard handshake age, overlay IP, Postgres role, disk space). No secrets; JSON only.

---

## 4) Provisioning Plan

### 4.1 DigitalOcean Hub (NYC, minimum sizing)
- **Droplet**: Regular Intel/AMD, `1 vCPU / 1GB RAM / 25GB SSD` (upgrade to 2 vCPU if PG traffic saturates CPU on hub).
- **OS**: Ubuntu 24.04 LTS.
- **Security**: SSH keys only; UFW allow `22/tcp` and `51820/udp`.

**Install (script sketch)**
```bash
apt update && apt install -y wireguard qrencode
umask 077
wg genkey | tee /etc/wireguard/server.key | wg pubkey > /etc/wireguard/server.pub
cat >/etc/wireguard/wg0.conf <<'EOF'
[Interface]
Address = 10.88.0.1/24
ListenPort = 51820
PrivateKey = $(cat /etc/wireguard/server.key)
# Enable L3 forwarding between spokes (no NAT)
PostUp = sysctl -w net.ipv4.ip_forward=1; \
        iptables -A FORWARD -i wg0 -o wg0 -j ACCEPT; \
        iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
PostDown = sysctl -w net.ipv4.ip_forward=0; \
          iptables -D FORWARD -i wg0 -o wg0 -j ACCEPT; \
          iptables -D FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
EOF
systemctl enable --now wg-quick@wg0
```

**Add spokes (3 total)**
```bash
# On hub; repeat for A/B/C with IPs .11/.12/.13
wg genkey | tee /etc/wireguard/spokeA.key | wg pubkey > /etc/wireguard/spokeA.pub
cat >>/etc/wireguard/wg0.conf <<EOF
[Peer]
# Spoke A
PublicKey = <spokeA_pub>
AllowedIPs = 10.88.0.11/32
PersistentKeepalive = 25
EOF
wg syncconf wg0 <(wg-quick strip wg0)
```

### 4.2 Dstack Spokes (outbound only)

**Install**
```bash
apt update && apt install -y wireguard
umask 077
wg genkey | tee /etc/wireguard/spoke.key | wg pubkey > /etc/wireguard/spoke.pub
cat >/etc/wireguard/wg0.conf <<'EOF'
[Interface]
Address = 10.88.0.11/32   # use .12 and .13 on other spokes
PrivateKey = <spoke_priv>

[Peer]
# Hub (NYC)
PublicKey = <hub_pub>
Endpoint = <hub_public_ip>:51820
# Allow full overlay so traffic to other spokes routes via the hub
AllowedIPs = 10.88.0.0/24
PersistentKeepalive = 25
EOF
systemctl enable --now wg-quick@wg0
```
> All initial VPN connections are **from spokes to the DO hub**. Spokes do not receive unsolicited inbound connections.

---

## 5) Postgres Location & Backups (Dstack‑only)

- **Placement**: the **entire Postgres cluster** (primary + replicas) runs on the Dstack spokes; the DO hub runs **no DB services**.
- **Networking**: DB listens on the WireGuard overlay IPs only (e.g., `10.88.0.11/12/13`).
- **Backups**: each spoke performs **local backups to its own disk** (e.g., `pgBackRest` local repo or rolling `pg_dump`). Offsite can be added later without changing networking.

---

## 6) Security, Routing & Firewall Policy
- **Hub isolates spokes by default**; only inter‑spoke L3 is allowed. No Internet egress via the hub.
- **Restrict SSH** via UFW to admin IPs.
- **Key handling**: private keys remain on each node.
- **Observability**: `wg show` and `journalctl -u wg-quick@wg0`.

### 6.1 Firewall goals
1. **Spokes may talk to each other without restriction** (full trust within `10.88.0.0/24`, except the hub).
2. **Spokes must not accept traffic from the hub’s VPN IP** (`10.88.0.1`).
3. **Hub forwards** packets **between spokes only**; hub must not originate traffic to spokes over `wg0`.

### 6.2 nftables — Spokes
```bash
# /etc/nftables.conf (spoke)
flush ruleset

table inet filter {
  chains {
    input {
      type filter hook input priority 0;
      policy drop;
      iif lo accept
      ct state established,related accept
      # Public status page
      tcp dport 8000 accept
      # VPN traffic from peers (all spokes except hub)
      iif "wg0" ip saddr 10.88.0.0/24 ip saddr != 10.88.0.1 accept
    }
    forward { type filter hook forward priority 0; policy drop; }
    output { type filter hook output priority 0; policy accept; }
  }
}

nft -f /etc/nftables.conf && systemctl enable --now nftables
```
> nftables is the default/preferred firewall on Dstack CVMs. We omit UFW variant for spokes.

### 6.4 nftables — Hub
```bash
# /etc/nftables.conf (hub)
flush ruleset

table inet filter {
  chains {
    input { type filter hook input priority 0; policy drop;
      iif lo accept
      ct state established,related accept
      tcp dport 22 accept
      udp dport 51820 accept
    }
    forward { type filter hook forward priority 0; policy drop;
      iif "wg0" oif "wg0" accept
    }
    output { type filter hook output priority 0; policy accept;
      oif "wg0" ip daddr 10.88.0.0/24 drop
    }
  }
}

nft -f /etc/nftables.conf && systemctl enable --now nftables
```
> Hub forwards between spokes, cannot originate to them. Combined with spoke rules that drop `src=10.88.0.1`, hub‑originated packets never reach applications.

---

## 7) DNS / Access
- Option A: no DNS, use overlay IPs directly (fastest).
- Option B: hosts‑file or split‑DNS entries (e.g., `pg-primary.vpn` → `10.88.0.11`).
- **Status page**: publicly reachable at `http://<spoke_public_ip>:8000/status` (or via a Dstack‑assigned hostname). Only read‑only JSON.

---

## 8) Testing Checklist
1. Bring up hub; verify `wg0` and L3 forwarding.
2. Join Spoke A/B/C; confirm handshakes and ping: `10.88.0.11 ↔ 10.88.0.12` via hub.
3. Verify that spokes cannot be reached from Internet directly **except** `:8000` status page.
4. Curl each spoke: `curl http://<spoke>:8000/status` and verify JSON (WG handshake age, role, disk free).
5. Reboot nodes to confirm persistence.
6. (Later) Add TCP fallback only where UDP is blocked.

---

## 9) Runbooks

**Add a spoke**
- Generate keypair on spoke; add its pubkey/IP to hub; enable `wg-quick@wg0` service.

**Rotate keys**
- Generate a new keypair on spoke; update hub peer; `wg syncconf`.

**Remove a spoke**
- Remove the `[Peer]` block on hub; stop WG on the spoke.

---

## 10) Deliverables
- Hub build script & three spoke join scripts (with your hub IP/public key embedded).
- **Spoke status service** (`:8000`) with systemd unit; minimal JSON endpoints.
- Minimal README with IP plan and step‑by‑step.

---

## Appendix A — Spoke Status Service (Go, read‑only on :8000)

**Overview**: tiny static Go binary exposing `GET /status` with no secrets. Reports hostname, `wg0` overlay IP, count of peers, max last‑handshake age (s), disk free (GiB), and UTC timestamp. Designed to run on Dstack spokes. 

### A.1 Source (`/opt/dstack-status/status.go`)
```go
package main
import (
  "encoding/json"
  "net"
  "net/http"
  "os"
  "os/exec"
  "strconv"
  "strings"
  "syscall"
  "time"
)

type Status struct {
  Node       string  `json:"node"`
  OverlayIP  string  `json:"overlay_ip"`
  WG         WGInfo  `json:"wg"`
  DiskFreeGB float64 `json:"disk_free_gb"`
  Time       string  `json:"time"`
}

type WGInfo struct {
  Interface   string `json:"interface"`
  PeerCount   int    `json:"peer_count"`
  MaxHandshakeAgeSec int64 `json:"max_last_handshake_sec"`
}

func overlayIP(iface string) string {
  i, err := net.InterfaceByName(iface)
  if err != nil { return "" }
  addrs, _ := i.Addrs()
  for _, a := range addrs {
    if ipnet, ok := a.(*net.IPNet); ok && ipnet.IP.To4() != nil {
      return ipnet.IP.String()
    }
  }
  return ""
}

func wgInfo() WGInfo {
  // Uses: wg show wg0 latest-handshakes
  out, err := exec.Command("wg", "show", "wg0", "latest-handshakes").Output()
  info := WGInfo{Interface: "wg0"}
  if err != nil { return info }
  lines := strings.Split(strings.TrimSpace(string(out)), "
")
  now := time.Now().Unix()
  maxAge := int64(0)
  for _, ln := range lines {
    f := strings.Fields(ln)
    if len(f) < 2 { continue }
    // f[1] = epoch seconds of last handshake (0 if never)
    t, _ := strconv.ParseInt(f[len(f)-1], 10, 64)
    if t == 0 { continue }
    age := now - t
    if age > maxAge { maxAge = age }
    info.PeerCount++
  }
  info.MaxHandshakeAgeSec = maxAge
  return info
}

func diskFreeGiB(path string) float64 {
  var st syscall.Statfs_t
  if err := syscall.Statfs(path, &st); err != nil { return 0 }
  free := float64(st.Bavail) * float64(st.Bsize) / (1024*1024*1024)
  return float64(int(free*10)) / 10.0 // 0.1 GiB precision
}

func main() {
  http.HandleFunc("/status", func(w http.ResponseWriter, r *http.Request) {
    host, _ := os.Hostname()
    s := Status{
      Node: host,
      OverlayIP: overlayIP("wg0"),
      WG: wgInfo(),
      DiskFreeGB: diskFreeGiB("/"),
      Time: time.Now().UTC().Format(time.RFC3339),
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(s)
  })
  srv := &http.Server{ Addr: ":8000", ReadHeaderTimeout: 3 * time.Second }
  if err := srv.ListenAndServe(); err != nil { panic(err) }
}
```

### A.2 Build & install
```bash
# On each spoke
apt update && apt install -y golang-go
install -d /opt/dstack-status
curl -fsSL -o /opt/dstack-status/status.go https://example.invalid/dstack/status.go  # (paste file instead on airgapped hosts)
cd /opt/dstack-status && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o dstack-status status.go

# systemd unit
cat >/etc/systemd/system/dstack-status.service <<'UNIT'
[Unit]
Description=Dstack Spoke Status (read-only)
After=network-online.target wg-quick@wg0.service
Wants=network-online.target

[Service]
ExecStart=/opt/dstack-status/dstack-status
Restart=always
RestartSec=2
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now dstack-status
```

### A.3 Verify
```bash
curl -s http://localhost:8000/status | jq .
```
> Output contains: hostname, wg0 overlay IP, peer count, max last-handshake age (seconds), disk free GiB, and current UTC time.

---

## 11) Open Questions
1. Any expected **throughput** that suggests starting with **2 vCPU** on the hub?
2. Confirm `10.88.0.11/.12/.13` match your intended Dstack node mapping.
3. Do you want **inter‑spoke ACLs** at the hub (e.g., allow only PG ports between specific pairs)?
4. Language preference for the **status service**: tiny **Go** binary or **Python FastAPI**?
5. Do you want a **/metrics** endpoint (Prometheus‑style) in addition to `/status`?
