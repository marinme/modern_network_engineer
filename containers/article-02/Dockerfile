# Article 02 — Interfaces, Namespaces, and Topologies
#
# A workbench container. Same shape as containers/article-01, but with the
# tools needed to build multi-namespace topologies by hand: iproute2 (for
# `ip netns`, `ip link add ... type veth|bridge|vlan|...`), the `bridge`
# command, tcpdump, traceroute, and a few quality-of-life extras.
#
# The container is the workbench; the topology lives in network namespaces
# the reader creates *inside* the container. h1, r1, h2, sw1, etc. are all
# `ip netns add` namespaces in this one container's kernel view. That is the
# whole point — Article 2 is about meeting the primitive before meeting the
# wrappers.
#
# Build:
#   docker build -t netmod/article-02 .
#
# Run (interactive; needs capabilities to create namespaces + bind-mount them):
#   docker run -it --rm \
#     --cap-add=NET_ADMIN \
#     --cap-add=NET_RAW \
#     --cap-add=SYS_ADMIN \
#     --security-opt apparmor=unconfined \
#     --name article-02 \
#     netmod/article-02
#
# Why each flag:
#   NET_ADMIN — configure interfaces, addresses, routes, namespaces.
#   NET_RAW   — tcpdump opens packet sockets.
#   SYS_ADMIN — `ip netns add` bind-mounts the new netns under /var/run/netns,
#               which needs mount(2). Without it, `ip netns add` fails with
#               "mount --make-shared /var/run/netns failed: Operation not
#               permitted".
#   apparmor=unconfined — on Ubuntu/Debian hosts the default Docker AppArmor
#               profile blocks the mount even with SYS_ADMIN. Drop it for
#               this lab. (Equivalent: --privileged, but the cap list is
#               narrower and easier to reason about.)
#
# None of this touches the host's networking stack. Everything the reader
# does happens inside this container's kernel view.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    PAGER=cat \
    TERM=xterm-256color

RUN apt-get update && apt-get install -y --no-install-recommends \
        iproute2 \
        iputils-ping \
        iputils-tracepath \
        traceroute \
        tcpdump \
        ethtool \
        nftables \
        conntrack \
        bsdmainutils \
        procps \
        jq \
        less \
        vim-tiny \
        bash-completion \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /lab

# Remount /proc/sys rw at container start so per-namespace sysctls
# (notably net.ipv4.ip_forward) are writable. See entrypoint.sh for why.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

RUN printf '%s\n' \
    '====================================================================' \
    ' Article 02 — Interfaces, Namespaces, and Topologies' \
    '' \
    ' This container is your workbench. Build the topologies inside it:' \
    '' \
    '   Lab 1 — Router  : h1 -- r1 -- h2  (three netns, two veth pairs)' \
    '   Lab 2 — Switch  : a -- sw1(br0) -- b, c  (bridge + three netns)' \
    '   Lab 3 — Compose : h1,h2 -- sw-left -- r1 -- sw-right -- h3,h4' \
    '' \
    ' First, prove a namespace is just a kernel object:' \
    '   readlink /proc/$$/ns/net                # this shell s netns inode' \
    '   ip netns add r1' \
    '   ip netns exec r1 readlink /proc/$$/ns/net   # different inode' \
    '   ip netns del r1' \
    '' \
    ' Full walkthroughs:  ../labs/lab-a02-topologies/README.md' \
    '====================================================================' \
    > /etc/motd \
 && printf '%s\n' \
    '' \
    '# Enable programmable bash-completion for interactive shells. The package' \
    '# is installed above; this sources it so Tab completes commands, options,' \
    '# paths, and files. (iproute2 ships no completion for `ip`/`bridge`'"'"'s own' \
    '# subcommands, so those still need typing in full.)' \
    'if ! shopt -oq posix; then' \
    '  if [ -f /usr/share/bash-completion/bash_completion ]; then' \
    '    . /usr/share/bash-completion/bash_completion' \
    '  elif [ -f /etc/bash_completion ]; then' \
    '    . /etc/bash_completion' \
    '  fi' \
    'fi' \
    'cat /etc/motd' \
    >> /root/.bashrc

CMD ["/bin/bash", "-l"]
