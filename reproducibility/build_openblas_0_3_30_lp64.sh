#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 /path/to/OpenBLAS-0.3.30.tar.gz [install-prefix]" >&2
  exit 64
fi
src=$1
prefix=${2:-/opt/autogrey-openblas-0.3.30-lp64-skylakex}
expected=27342cff518646afb4c2b976d809102e368957974c250a25ccc965e53063c95d
got=$(sha256sum "$src" | awk '{print $1}')
[[ "$got" == "$expected" ]] || { echo "SOURCE_SHA256_MISMATCH $got != $expected" >&2; exit 2; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tar -xzf "$src" -C "$work"
cd "$work/OpenBLAS-0.3.30"
make -j1 TARGET=SKYLAKEX DYNAMIC_ARCH=0 INTERFACE64=0 USE_THREAD=1 NUM_THREADS=1 NO_AFFINITY=1
make PREFIX="$prefix" install
printf 'OPENBLAS_BUILD=PASS\nPREFIX=%s\nINTEGER_INTERFACE=LP64\n' "$prefix"
