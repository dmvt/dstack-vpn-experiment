# Build stage
FROM golang:1.21-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git

# Set working directory
WORKDIR /app

# Copy Go source
COPY docker/status-service/status.go .

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags "-s -w" -o dstack-status status.go

# Runtime stage
FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache \
    wireguard-tools \
    curl \
    ca-certificates

# Create non-root user
RUN addgroup -g 1000 -S appgroup && \
    adduser -u 1000 -S appuser -G appgroup

# Create necessary directories
RUN mkdir -p /opt/dstack-status /var/log/wireguard && \
    chown -R appuser:appgroup /opt/dstack-status /var/log/wireguard

# Copy binary from builder
COPY --from=builder /app/dstack-status /opt/dstack-status/dstack-status

# Set ownership
RUN chown appuser:appgroup /opt/dstack-status/dstack-status && \
    chmod +x /opt/dstack-status/dstack-status

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run the service
CMD ["/opt/dstack-status/dstack-status"]
