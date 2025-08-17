# Multi-stage build for Phala CVM WireGuard node with status service
FROM golang:1.21-alpine AS builder

# Build the status service
WORKDIR /build
COPY docker/status-service/status.go .

# Build statically linked binary
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o dstack-status status.go

# Final stage - WireGuard with status service
FROM alpine:3.19

# Install WireGuard and dependencies
RUN apk add --no-cache \
    wireguard-tools \
    iptables \
    ip6tables \
    curl \
    jq \
    bash \
    ca-certificates

# Copy status service from builder
COPY --from=builder /build/dstack-status /usr/local/bin/

# Create directories
RUN mkdir -p /etc/wireguard /var/log/wireguard

# Create entrypoint script
COPY docker/phala-wireguard/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose ports
EXPOSE 51820/udp
EXPOSE 8000/tcp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]
