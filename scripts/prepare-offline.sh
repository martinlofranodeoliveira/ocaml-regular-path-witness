#!/bin/sh
set -eu
export PYTHONDONTWRITEBYTECODE=1
exec python3 scripts/gate.py prepare
