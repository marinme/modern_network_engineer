#!/bin/bash
# Docker bind-mounts /proc/sys read-only by default. Article 3 needs to write
# to /proc/sys/net/ipv4/ip_forward, rp_filter, proxy_arp, and friends per
# network namespace, so remount it rw here. SYS_ADMIN (granted via --cap-add)
# is what makes this possible without --privileged.
#
# Without this, `sysctl -w net.ipv4.ip_forward=1` inside `ip netns exec r1`
# returns rc=0 but prints "ignoring: Read-only file system" — the change
# never lands. New netns inherit the parent's ip_forward at creation, so the
# lab might appear to work on hosts where Docker's parent ns already has
# forwarding on, and silently fail on hosts where it doesn't.

if mountpoint -q /proc/sys && grep -qE '^proc /proc/sys .* ro,' /proc/mounts; then
  mount -o remount,rw /proc/sys
fi

exec "$@"
