#!/usr/bin/env bash
# test.sh — standard verification entrypoint for this lab.
#
# Lab A02 is multi-part (five sub-labs that share one container), so this
# dispatcher takes the part you want to verify and runs its checker. Each
# checker is verify-only and non-destructive, and auto-discovers your
# namespaces/IPs (see the per-part scripts and ./README.md).
#
# Usage (from the /lab prompt, after building a sub-lab):
#     ./tests/test.sh 1            # by number
#     ./tests/test.sh 1-router     # by full slug
#     ./tests/test.sh router       # by name
#     ./tests/test.sh              # list the parts
#
# Exit: passes through the checker's status (0 pass, 1 fail, 2 setup error);
#       2 if the requested part is unknown.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Discover parts from the test-lab-<n>-<name>.sh files so this stays correct
# as sub-labs are added or renamed — no hard-coded list to drift.
mapfile -t SCRIPTS < <(cd "$HERE" && ls test-lab-*.sh 2>/dev/null | sort)

usage() {
  echo "usage: $(basename "$0") <part>"
  echo "Verify a built Lab A02 sub-lab (verify-only, non-destructive)."
  if [ "${#SCRIPTS[@]}" -gt 0 ]; then
    echo
    echo "parts:"
    local s base num name
    for s in "${SCRIPTS[@]}"; do
      base="${s#test-lab-}"; base="${base%.sh}"   # e.g. 1-router
      num="${base%%-*}"; name="${base#*-}"
      printf "  %-2s  %-8s  ->  ./tests/test.sh %s\n" "$num" "$name" "$num"
    done
  else
    echo "(no test-lab-*.sh checkers found alongside this script)"
  fi
}

[ "$#" -ge 1 ] || { usage; exit 2; }

sel="$1"; shift
target=""
for s in "${SCRIPTS[@]}"; do
  base="${s#test-lab-}"; base="${base%.sh}"       # 1-router
  num="${base%%-*}"; name="${base#*-}"            # 1 / router
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
