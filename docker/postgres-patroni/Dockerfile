FROM postgres:16-alpine

# Install Patroni, etcd, and dependencies
RUN apk add --no-cache \
    python3 \
    py3-pip \
    curl \
    jq \
    netcat-openbsd \
    bash \
    && pip3 install patroni[etcd] psycopg2-binary

# Create Patroni user and directories
RUN adduser -D -s /bin/bash patroni \
    && mkdir -p /home/patroni \
    && chown -R patroni:patroni /home/patroni

# Copy Patroni configuration
COPY patroni.yml /etc/patroni.yml
COPY postgresql.yml /etc/postgresql.yml
COPY entrypoint.sh /entrypoint.sh
COPY health-check.sh /health-check.sh

# Make scripts executable
RUN chmod +x /entrypoint.sh /health-check.sh

# Switch to Patroni user
USER patroni
WORKDIR /home/patroni

# Expose Patroni API port
EXPOSE 8008

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \ 
    CMD /health-check.sh

ENTRYPOINT ["/entrypoint.sh"]
