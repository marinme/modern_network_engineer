#!/usr/bin/env bash
# test.sh — verification entrypoint for Lab A01.
#
# Each sub-lab maps to a test-lab-N-<name>.sh file. This dispatcher finds them
# by glob and runs the one you ask for. All checkers are self-contained and
# restore any state they modify (routes, addresses, nftables rules, listeners).
#
# Usage (inside the article-01 container):
#     ./tests/test.sh 1            # by number
#     ./tests/test.sh 1-routing    # by full slug
#     ./tests/test.sh routing      # by name
#     ./tests/test.sh              # list the parts
#
# Most scripts accept an optional --inject-fault flag that deliberately
# breaks a precondition so you can see what failures look like, then cleans up.
#
# Exit: 0 all pass, 1 any failed, 2 setup error or unknown part.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mapfile -t SCRIPTS < <(cd "$HERE" && ls test-lab-*.sh 2>/dev/null | sort)

usage() {
  echo "usage: $(basename "$0") <part> [--inject-fault]"
  echo "Verify a built Lab A01 exercise (self-contained, restores all state)."
  if [ "${#SCRIPTS[@]}" -gt 0 ]; then
    echo
    echo "parts:"
    local s base num name
    for s in "${SCRIPTS[@]}"; do
      base="${s#test-lab-}"; base="${base%.sh}"
      num="${base%%-*}"; name="${base#*-}"
      printf "  %-2s  %-20s  ->  ./tests/test.sh %s\n" "$num" "$name" "$num"
    done
  else
    echo "(no test-lab-*.sh checkers found alongside this script)"
  fi
}

[ "$#" -ge 1 ] || { usage; exit 2; }

sel="$1"; shift
target=""
for s in "${SCRIPTS[@]}"; do
  base="${s#test-lab-}"; base="${base%.sh}"
  num="${base%%-*}"; name="${base#*-}"
  if [ "$sel" = "$num" ] || [ "$sel" = "$base" ] || [ "$sel" = "$name" ]; then
    target="$s"; break
  fi
done

if [ -z "$target" ]; then
  echo "error: unknown part '$sel'" >&2
  echo >&2
  usage >&2
  exit 2
fi

exec bash "$HERE/$target" "$@"
