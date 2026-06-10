#!/usr/bin/env bash
# test.sh — standard verification entrypoint for Lab A04 (VRRP).
#
# Lab A04 VRRP has two sub-labs (keepalived and FRR vrrpd), so this
# dispatcher takes the part you want to verify and runs its checker.
# Each checker is verify-only and non-destructive.
#
# Usage
#   ./tests/vrrp/test.sh 1                # by number
#   ./tests/vrrp/test.sh 1-keepalived     # by full slug
#   ./tests/vrrp/test.sh keepalived       # by name
#   ./tests/vrrp/test.sh                  # list the parts
#
# Exit: passes through the checker's status (0 pass, 1 fail, 2 setup error);
# 2 if the requested part is unknown.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Discover parts from test-lab-<n>-<name>.sh files
mapfile -t SCRIPTS < <(cd "$HERE" && ls test-lab-*.sh 2>/dev/null | sort)

usage() {
    echo "usage: $(basename "$0") <part>"
    echo "Verify a built Lab A04 VRRP sub-lab (verify-only, non-destructive)."
    if [ "${#SCRIPTS[@]}" -gt 0 ]; then
        echo "parts:"
        local s base num name
        for s in "${SCRIPTS[@]}"; do
            base="${s#test-lab-}"; base="${base%.sh}"
            num="${base%%-*}"; name="${base#*-}"
            printf "  %-2s  %-28s -> ./tests/vrrp/test.sh %s\n" "$num" "$name" "$num"
        done
    else
        echo "(no test-lab-*.sh checkers found alongside this script)"
    fi
}

if [ $# -eq 0 ]; then
    usage; exit 2
fi

ARG="$1"
target=""

for s in "${SCRIPTS[@]}"; do
    base="${s#test-lab-}"; base="${base%.sh}"
    num="${base%%-*}"; name="${base#*-}"
    if [ "$ARG" = "$num" ] || [ "$ARG" = "$base" ] || [ "$ARG" = "$name" ]; then
        target="$s"
        break
    fi
done

if [ -z "$target" ]; then
    echo "error: unknown part '$ARG'" >&2
    usage >&2
    exit 2
fi

exec bash "$HERE/$target" "$@"
