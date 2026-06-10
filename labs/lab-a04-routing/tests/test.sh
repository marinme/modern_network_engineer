#!/usr/bin/env bash
# test.sh — standard verification entrypoint for Lab A04 (routing).
#
# Lab A04 routing is multi-part (seven sub-labs that share one container),
# so this dispatcher takes the part you want to verify and runs its checker.
# Each checker is verify-only and non-destructive.
#
# Usage
#   ./tests/routing/test.sh 1                  # by number
#   ./tests/routing/test.sh 1-rib-vs-fib       # by full slug
#   ./tests/routing/test.sh rib-vs-fib         # by name
#   ./tests/routing/test.sh                    # list the parts
#
# Exit: passes through the checker's status (0 pass, 1 fail, 2 setup error);
# 2 if the requested part is unknown.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Discover parts from test-lab-<n>-<name>.sh files
mapfile -t SCRIPTS < <(cd "$HERE" && ls test-lab-*.sh 2>/dev/null | sort)

usage() {
    echo "usage: $(basename "$0") <part>"
    echo "Verify a built Lab A04 routing sub-lab (verify-only, non-destructive)."
    if [ "${#SCRIPTS[@]}" -gt 0 ]; then
        echo "parts:"
        local s base num name
        for s in "${SCRIPTS[@]}"; do
            base="${s#test-lab-}"; base="${base%.sh}"
            num="${base%%-*}"; name="${base#*-}"
            printf "  %-2s  %-28s -> ./tests/routing/test.sh %s\n" "$num" "$name" "$num"
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
