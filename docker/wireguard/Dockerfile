FROM alpine:3.19

# Install required packages
RUN apk add --no-cache \
    wireguard-tools \
    curl \
    bash \
    iptables \
    nftables

# Create necessary directories
RUN mkdir -p /etc/wireguard /var/log/wireguard

# Copy entrypoint script
COPY docker/wireguard/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Copy init script
COPY docker/wireguard/init-env.sh /init-env.sh
RUN chmod +x /init-env.sh

# Copy health check script
COPY docker/wireguard/health-check.js /health-check.js

# Expose WireGuard port
EXPOSE 51820/udp 8000/tcp

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"] 