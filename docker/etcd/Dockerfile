FROM quay.io/coreos/etcd:v3.5.0

# Expose etcd ports
EXPOSE 2379 2380

# Set default environment variables
ENV ETCD_NAME=etcd-0
ENV ETCD_DATA_DIR=/var/lib/etcd
ENV ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
ENV ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
ENV ETCD_ADVERTISE_PEER_URLS=http://localhost:2380
ENV ETCD_ADVERTISE_CLIENT_URLS=http://0.0.0.0:2379
ENV ETCD_INITIAL_CLUSTER=etcd-0=http://localhost:2380
ENV ETCD_INITIAL_CLUSTER_STATE=new
ENV ETCD_INITIAL_CLUSTER_TOKEN=dstack-cluster

# Create data directory
RUN mkdir -p /var/lib/etcd

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD etcdctl endpoint health || exit 1
