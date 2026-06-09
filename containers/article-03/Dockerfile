# Article 03 — Common Network-Admin Tasks in Base Linux
#
# Extends the article-02 workbench with additional tools for the 21 recurring
# tasks: dnsmasq (DHCP server), isc-dhcp-relay (DHCP relay), chrony (NTP),
# rsyslog (syslog forwarding), lldpd (LLDP), iperf3 (throughput), socat/ncat
# (TCP listeners for ACL/NAT probes), and bmon/iftop/nload (capacity TUIs).
#
# All daemons are installed but NOT started — there is no init process in this
# container. The reader starts each service explicitly inside the target netns
# using `ip netns exec`. This matches the "you build it by hand" pedagogy and
# avoids port/interface conflicts between lab sub-tasks.
#
# Same run flags as article-02:
#   docker run -it --rm \
#     --cap-add=NET_ADMIN \   # ip link / ip route / ip netns / nft
#     --cap-add=NET_RAW \     # tcpdump / ping raw sockets
#     --cap-add=SYS_ADMIN \   # remount /proc/sys rw for per-netns sysctls
#     --security-opt apparmor=unconfined \
#     netmod/article-03
#
# The topology lives in network namespaces INSIDE the container — `ip netns add`
# creates bind mounts under /var/run/netns in the container's view.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    # --- carried over from article-02 ---
    iproute2 \
    iputils-ping \
    traceroute \
    iputils-tracepath \
    tcpdump \
    ethtool \
    nftables \
    conntrack \
    jq \
    procps \
    bsdmainutils \
    vim-tiny \
    less \
    bash-completion \
    ca-certificates \
    # --- new for article-03 ---
    dnsmasq \
    isc-dhcp-relay \
    isc-dhcp-client \
    chrony \
    rsyslog \
    lldpd \
    iperf3 \
    socat \
    ncat \
    bmon \
    iftop \
    nload \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /lab

# Remount /proc/sys rw so per-netns sysctl writes work (ip_forward, rp_filter,
# proxy_arp, etc.). SYS_ADMIN (from --cap-add) makes this possible.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

RUN printf '%s\n' \
    '====================================================================' \
    ' Article 03 — Common Network-Admin Tasks in Base Linux' \
    '====================================================================' \
    '' \
    ' Lab  1 — Routing & Failover : ECMP multipath + metric backup routes' \
    ' Lab  2 — Stateful ACL        : nft forward chain, ct state, capture' \
    ' Lab  3 — VLAN Trunk          : vlan-aware bridge, pvid, tagged egress' \
    ' Lab  4 — Bonding             : active-backup and 802.3ad LACP' \
    ' Lab  5 — NAT / DNAT          : masquerade outbound, dnat port-forward' \
    ' Lab  6 — Port Mirror / SPAN  : tc clsact + mirred to a monitor dummy' \
    ' Lab  7 — DHCP                : dnsmasq server + dhcrelay relay' \
    ' Lab  8 — VRF + rp_filter     : routing isolation, reverse-path filtering' \
    ' Lab  9 — ARP + Proxy ARP     : permanent neigh, proxy_arp sysctl' \
    ' Lab 10 — MTU / PMTU          : per-link MTU, DF ping, PMTU cache' \
    ' Lab 11 — Services            : chrony NTP, rsyslog forwarding, LLDP' \
    ' Lab 12 — Full Appliance      : all of the above, health sweep, iperf3' \
    '' \
    ' Quick reference:' \
    '   ./tests/test.sh          # list labs' \
    '   ./tests/test.sh 1        # verify Lab 1 (also: 1-routing-failover)' \
    '   See labs/lab-a03-admin-tasks/README.md for setup and sub-lab links.' \
    '====================================================================' \
    > /etc/motd

CMD ["/bin/bash", "--login"]
