FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        dnsmasq \
        dnsutils \
        curl \
        tcpdump \
        iputils-ping && \
    rm -rf /var/lib/apt/lists/*

COPY dnsmasq.conf /etc/dnsmasq.conf

CMD ["dnsmasq", "--no-daemon", "-C", "/etc/dnsmasq.conf"]
