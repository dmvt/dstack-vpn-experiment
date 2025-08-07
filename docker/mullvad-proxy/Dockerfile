FROM alpine:3.19

# Install socat for UDP-to-TCP proxying
RUN apk add --no-cache socat

# Create proxy script
COPY proxy.sh /proxy.sh
RUN chmod +x /proxy.sh

# Expose proxy ports
EXPOSE 51820/udp 8000/tcp

# Set entrypoint
ENTRYPOINT ["/proxy.sh"] 