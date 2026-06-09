# containers/article-04/Dockerfile
#
# Workbench image for Article 4 — Routing Daemons (Linux as a Router).
# Runs systemd as PID 1 so that per-namespace FRR template units and
# journalctl work exactly as the article describes.
#
# Build:
#   docker build -t netmod/article-04 containers/article-04
#
# Run (via compose — preferred):
#   docker compose -f containers/article-04/docker-compose.yml run --rm lab
#
# Run (direct — requires privileged for systemd):
#   docker run -it --rm \
#     --privileged \
#     --cgroupns=host \
#     -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
#     --tmpfs /run --tmpfs /run/lock \
#     -v "$(pwd)/labs/lab-a04-routing/tests:/lab/tests/routing:ro" \
#     -v "$(pwd)/labs/lab-a04-vrrp/tests:/lab/tests/vrrp:ro" \
#     -v "$(pwd)/labs/lab-a04-multicast/tests:/lab/tests/multicast:ro" \
#     --name article-04 netmod/article-04
#
# Capabilities used:
#   --privileged        Required for systemd as PID 1 (cgroup v2 + mount ops).
#                       Also provides NET_ADMIN, NET_RAW, SYS_ADMIN.
#
# Topology (built by /lab/setup.sh):
#   Three network namespaces — r1, r2, r3 — connected by veth pairs.
#   FRR runs in each namespace via frr@r1.service, frr@r2.service, frr@r3.service.
#   The VRRP and multicast labs build their own namespaces by hand (different topology).
#
# All daemons are installed but disabled at the container level; the reader
# brings them up namespace-by-namespace via setup.sh and systemctl.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# --- Packages ---

# Carried over from article-03
RUN apt-get update && apt-get install -y --no-install-recommends \
    # networking
    iproute2 \
    iputils-ping \
    iputils-tracepath \
    traceroute \
    tcpdump \
    ethtool \
    nftables \
    conntrack \
    # tools
    jq \
    procps \
    bsdmainutils \
    vim-tiny \
    less \
    bash-completion \
    ca-certificates \
    # systemd (this is the departure from article-02/03)
    systemd \
    systemd-sysv \
    dbus \
    && rm -rf /var/lib/apt/lists/*

# New for article-04 — routing daemons and supporting tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    # FRR — zebra, bgpd, ospfd, bfdd, pimd, vrrpd, staticd, watchfrr, vtysh
    frr \
    frr-pythontools \
    # first-hop redundancy
    keepalived \
    # static multicast routes without a control plane
    smcroute \
    # classic iperf for multicast testing (iperf3 dropped multicast support)
    iperf \
    # services for lab exercises
    socat \
    ncat \
    iperf3 \
    && rm -rf /var/lib/apt/lists/*

# --- systemd cleanup for container ---
# Remove units that are irrelevant or fail in a container environment.
RUN systemctl mask \
        systemd-udevd.service \
        systemd-udevd-control.socket \
        systemd-udevd-kernel.socket \
        systemd-timesyncd.service \
        apt-daily.service apt-daily-upgrade.service \
        apt-daily.timer apt-daily-upgrade.timer \
        fstrim.timer motd-news.timer ua-timer.timer \
    2>/dev/null || true

# --- FRR global configuration ---
# Enable the daemons the routing labs need; reader activates pimd/vrrpd per-lab.
RUN sed -i \
        -e 's/^zebra=no/zebra=yes/' \
        -e 's/^bgpd=no/bgpd=yes/' \
        -e 's/^ospfd=no/ospfd=yes/' \
        -e 's/^bfdd=no/bfdd=yes/' \
        -e 's/^staticd=no/staticd=yes/' \
        /etc/frr/daemons 2>/dev/null || true

# Enable integrated config mode (single frr.conf per instance)
RUN echo 'service integrated-vtysh-config' > /etc/frr/vtysh.conf

# --- Per-namespace FRR template unit ---
COPY frr@.service /etc/systemd/system/frr@.service
RUN systemctl enable 'frr@.service' 2>/dev/null || true

# --- Helper scripts ---
WORKDIR /lab

COPY setup.sh /lab/setup.sh
RUN chmod +x /lab/setup.sh

COPY frrvtysh /lab/frrvtysh
RUN chmod +x /lab/frrvtysh

# --- MOTD ---
RUN printf '%s\n' \
    '======================================================' \
    '  Article 4 — Routing Daemons (Linux as a Router)' \
    '======================================================' \
    '' \
    '  Start the routing topology:' \
    '    /lab/setup.sh' \
    '' \
    '  Connect to FRR in a namespace:' \
    '    /lab/frrvtysh r1      (shorthand for vtysh -N r1)' \
    '    ip netns exec r1 vtysh -N r1' \
    '' \
    '  Lab verification (run from /lab):' \
    '    ./tests/routing/test.sh       # list routing sub-labs' \
    '    ./tests/routing/test.sh 1     # RIB vs FIB' \
    '    ./tests/routing/test.sh 2     # OSPF adjacency' \
    '    ./tests/routing/test.sh 3     # BGP session' \
    '    ./tests/routing/test.sh 4     # BGP unnumbered' \
    '    ./tests/routing/test.sh 5     # BFD' \
    '    ./tests/routing/test.sh 6     # FRR persistence' \
    '    ./tests/routing/test.sh 7     # journal correlation' \
    '' \
    '    ./tests/vrrp/test.sh 1        # keepalived VRRP' \
    '    ./tests/vrrp/test.sh 2        # FRR vrrpd' \
    '' \
    '    ./tests/multicast/test.sh 1   # FRR pimd PIM-SM' \
    '    ./tests/multicast/test.sh 2   # smcroute static' \
    '' \
    '  Pairs with: wiki/article-04-routing-daemons.md' \
    '======================================================' \
    > /etc/motd

RUN printf '%s\n' \
    'if [ -f /etc/motd ]; then cat /etc/motd; fi' \
    >> /root/.bashrc

# systemd as PID 1
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
