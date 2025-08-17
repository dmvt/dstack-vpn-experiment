FROM alpine:3.19

# Install required packages including Patroni and PostgreSQL
RUN apk add --no-cache \
    wireguard-tools \
    curl \
    bash \
    iptables \
    nftables \
    python3 \
    py3-pip \
    postgresql \
    postgresql-contrib \
    jq \
    netcat-openbsd \
    gcc \
    python3-dev \
    musl-dev \
    linux-headers \
    && pip3 install --break-system-packages patroni[etcd] psycopg2-binary \
    && apk del gcc python3-dev musl-dev linux-headers

# Create necessary directories
RUN mkdir -p /etc/wireguard /var/log/wireguard /var/lib/postgresql/data /var/lib/pgbackrest

# Create postgres user if it doesn't exist
RUN id postgres &>/dev/null || adduser -D -s /bin/bash postgres

# Copy Patroni configuration
COPY docker/postgres-patroni/patroni.yml /etc/patroni.yml
COPY docker/postgres-patroni/entrypoint.sh /patroni-entrypoint.sh
COPY docker/postgres-patroni/health-check.sh /patroni-health-check.sh

# Copy entrypoint script
COPY docker/wireguard/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Copy init script
COPY docker/wireguard/init-env.sh /init-env.sh
RUN chmod +x /init-env.sh

# Copy health check script
COPY docker/wireguard/health-check.js /health-check.js

# Make Patroni scripts executable
RUN chmod +x /patroni-entrypoint.sh /patroni-health-check.sh

# Expose WireGuard port, PostgreSQL port, and Patroni API port
EXPOSE 51820/udp 8000/tcp 5432/tcp 8008/tcp

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"] 