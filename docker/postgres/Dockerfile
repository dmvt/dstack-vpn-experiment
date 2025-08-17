FROM postgres:16-alpine

# Install pgBackRest and dependencies
RUN apk add --no-cache \
    pgbackrest \
    bash \
    curl \
    jq \
    netcat-openbsd

# Create backup directory
RUN mkdir -p /var/lib/pgbackrest && \
    chown postgres:postgres /var/lib/pgbackrest

# Copy configuration files
COPY postgresql.conf.primary /etc/postgresql/postgresql.conf.primary
COPY postgresql.conf.replica /etc/postgresql/postgresql.conf.replica
COPY pg_hba.conf /etc/postgresql/pg_hba.conf
COPY pgbackrest.conf /etc/pgbackrest/pgbackrest.conf

# Copy scripts
COPY entrypoint.sh /usr/local/bin/
COPY health-check.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/health-check.sh

# Set custom entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["postgres"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD /usr/local/bin/health-check.sh

EXPOSE 5432
