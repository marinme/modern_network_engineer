# Article 01 — Linux for Network Engineers
#
# A minimal Ubuntu image with the tools the article uses. Pull, run, and
# practice the IOS-to-Linux translation table inside the container without
# touching the host networking stack.
#
# Build:
#   docker build -t netmod/article-01 .
#
# Run (interactive, with the capabilities needed for tcpdump/ip-suite work):
#   docker run -it --rm \
#     --cap-add=NET_ADMIN \
#     --cap-add=NET_RAW \
#     --name article-01 \
#     netmod/article-01
#
# NET_ADMIN lets you configure interfaces, routes, and namespaces.
# NET_RAW lets tcpdump open packet sockets.
# Neither grants host access — they only apply inside the container's own
# network namespace.

FROM ubuntu:24.04

# Non-interactive apt and a sane default pager so `ip` output doesn't try to
# launch less in a learning shell.
ENV DEBIAN_FRONTEND=noninteractive \
    PAGER=cat \
    TERM=xterm-256color

RUN apt-get update && apt-get install -y --no-install-recommends \
        iproute2 \
        bridge-utils \
        iputils-ping \
        iputils-tracepath \
        traceroute \
        mtr-tiny \
        tcpdump \
        ethtool \
        nftables \
        conntrack \
        net-tools \
        dnsutils \
        netcat-openbsd \
        jq \
        less \
        vim-tiny \
        bash-completion \
        ca-certificates \
        procps \
    && rm -rf /var/lib/apt/lists/*

# Working directory and a small message of the day pointing the reader at the
# article's worked-translation lab.
WORKDIR /lab

RUN printf '%s\n' \
    '====================================================================' \
    ' Article 01 — Linux for Network Engineers' \
    '' \
    ' This container has the tools the article uses:' \
    '   ip, ss, bridge, tcpdump, ethtool, jq, ping, mtr, traceroute, nft' \
    '' \
    ' Try the worked-translation lab from the article:' \
    '   ip route show' \
    '   ip -br link' \
    '   ip -br addr' \
    '   ip neigh' \
    '   ss -lntp' \
    '   tcpdump -nni any -c 5 icmp     # in one shell' \
    '   ping -c 4 1.1.1.1              # in another' \
    '   ip -s -s link show eth0' \
    '' \
    ' Remember: PAGER is set to cat, so output scrolls naturally.' \
    '====================================================================' \
    > /etc/motd \
 && printf '\ncat /etc/motd\n' >> /root/.bashrc

CMD ["/bin/bash", "-l"]
