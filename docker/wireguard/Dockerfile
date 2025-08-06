FROM alpine:3.19

# Install WireGuard and required packages
RUN apk add --no-cache \
    wireguard-tools \
    iptables \
    bash \
    curl \
    iproute2 \
    && rm -rf /var/cache/apk/*

# Create WireGuard directory
RUN mkdir -p /etc/wireguard

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose WireGuard port
EXPOSE 51820/udp

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"] 