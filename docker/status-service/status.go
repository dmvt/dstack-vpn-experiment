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
	Node       string   `json:"node"`
	OverlayIP  string   `json:"overlay_ip"`
	WG         WGInfo   `json:"wg"`
	Postgres   *PGInfo  `json:"postgres,omitempty"`
	DiskFreeGB float64  `json:"disk_free_gb"`
	Time       string   `json:"time"`
}

type WGInfo struct {
	Interface           string `json:"interface"`
	PeerCount          int    `json:"peer_count"`
	MaxHandshakeAgeSec int64  `json:"max_last_handshake_sec"`
}

type PGInfo struct {
	Role            string  `json:"role"`
	Connections     int     `json:"connections"`
	ReplicationLag  *int64  `json:"replication_lag_sec,omitempty"`
	BackupStatus    string  `json:"backup_status"`
	LastBackup      string  `json:"last_backup,omitempty"`
}

func overlayIP(iface string) string {
	i, err := net.InterfaceByName(iface)
	if err != nil {
		return ""
	}
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
	if err != nil {
		return info
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	now := time.Now().Unix()
	maxAge := int64(0)
	for _, ln := range lines {
		f := strings.Fields(ln)
		if len(f) < 2 {
			continue
		}
		// f[1] = epoch seconds of last handshake (0 if never)
		t, _ := strconv.ParseInt(f[len(f)-1], 10, 64)
		if t == 0 {
			continue
		}
		age := now - t
		if age > maxAge {
			maxAge = age
		}
		info.PeerCount++
	}
	info.MaxHandshakeAgeSec = maxAge
	return info
}

func diskFreeGiB(path string) float64 {
	var st syscall.Statfs_t
	if err := syscall.Statfs(path, &st); err != nil {
		return 0
	}
	free := float64(st.Bavail) * float64(st.Bsize) / (1024*1024*1024)
	return float64(int(free*10)) / 10.0 // 0.1 GiB precision
}

func pgInfo() *PGInfo {
	// Check if psql is available
	_, err := exec.LookPath("psql")
	if err != nil {
		return nil
	}

	// Check if PostgreSQL is running
	cmd := exec.Command("pg_isready", "-U", "postgres", "-d", "dstack")
	if err := cmd.Run(); err != nil {
		return nil
	}

	info := &PGInfo{}

	// Get role (primary/replica)
	out, err := exec.Command("psql", "-U", "postgres", "-d", "dstack", "-tAc",
		"SELECT CASE WHEN pg_is_in_recovery() THEN 'replica' ELSE 'primary' END").Output()
	if err == nil {
		info.Role = strings.TrimSpace(string(out))
	}

	// Get connection count
	out, err = exec.Command("psql", "-U", "postgres", "-d", "dstack", "-tAc",
		"SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'active'").Output()
	if err == nil {
		info.Connections, _ = strconv.Atoi(strings.TrimSpace(string(out)))
	}

	// Get replication lag for replicas
	if info.Role == "replica" {
		out, err = exec.Command("psql", "-U", "postgres", "-d", "dstack", "-tAc",
			"SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::INT").Output()
		if err == nil {
			lag, _ := strconv.ParseInt(strings.TrimSpace(string(out)), 10, 64)
			info.ReplicationLag = &lag
		}
	}

	// Get backup status
	out, err = exec.Command("pgbackrest", "--stanza=db", "info", "--output=json").Output()
	if err == nil {
		// Parse backup info (simplified for now)
		info.BackupStatus = "configured"
		// TODO: Parse JSON to get last backup time
	} else {
		info.BackupStatus = "not_configured"
	}

	return info
}

func main() {
	http.HandleFunc("/status", func(w http.ResponseWriter, r *http.Request) {
		host, _ := os.Hostname()
		s := Status{
			Node:       host,
			OverlayIP:  overlayIP("wg0"),
			WG:         wgInfo(),
			Postgres:   pgInfo(),
			DiskFreeGB: diskFreeGiB("/"),
			Time:       time.Now().UTC().Format(time.RFC3339),
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(s)
	})

	// Add health check endpoint
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
	})

	srv := &http.Server{
		Addr:              ":8000",
		ReadHeaderTimeout: 3 * time.Second,
	}
	if err := srv.ListenAndServe(); err != nil {
		panic(err)
	}
}
