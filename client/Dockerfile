FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        dnsutils \
        curl \
        iputils-ping \
        netcat-openbsd \
        openssl \
        tcpdump \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

CMD ["sleep", "infinity"]
