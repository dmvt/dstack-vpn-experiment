FROM alpine:3.19

# Install WireGuard, Node.js, and required packages
RUN apk add --no-cache \
    wireguard-tools \
    iptables \
    bash \
    curl \
    iproute2 \
    nodejs \
    npm \
    && rm -rf /var/cache/apk/*

# Create application directories
RUN mkdir -p /etc/wireguard /app /var/log/wireguard

# Copy package files and install dependencies
COPY package*.json /app/
WORKDIR /app
RUN npm ci --only=production

# Copy integration layer components
COPY src/ /app/src/
COPY config/ /app/config/

# Copy entrypoint scripts
COPY docker/wireguard/entrypoint.sh /entrypoint.sh
COPY docker/wireguard/init-env.sh /app/init-env.sh
COPY docker/wireguard/start-bridge.js /app/start-bridge.js
RUN chmod +x /entrypoint.sh /app/init-env.sh

# Create health check endpoint
COPY docker/wireguard/health-check.js /app/health-check.js

# Expose WireGuard port and health check port
EXPOSE 51820/udp 8080/tcp

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"] 