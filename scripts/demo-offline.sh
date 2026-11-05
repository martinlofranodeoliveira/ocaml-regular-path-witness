#!/bin/sh
set -eu
if [ "$#" -ne 1 ] || [ "$1" != "--assert" ]; then
  printf '%s\n' 'usage: /bin/sh scripts/demo-offline.sh --assert' >&2
  exit 2
fi
export PYTHONDONTWRITEBYTECODE=1
exec python3 scripts/gate.py demo
