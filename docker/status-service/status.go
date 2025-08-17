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
	Interface           string `json:"interface"`
	PeerCount          int    `json:"peer_count"`
	MaxHandshakeAgeSec int64  `json:"max_last_handshake_sec"`
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

func main() {
	http.HandleFunc("/status", func(w http.ResponseWriter, r *http.Request) {
		host, _ := os.Hostname()
		s := Status{
			Node:       host,
			OverlayIP:  overlayIP("wg0"),
			WG:         wgInfo(),
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
