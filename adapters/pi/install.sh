#!/usr/bin/env bash
# antz for pi. The guide is README.md next to this file; the work is done by
# ../install.sh, which knows all three clients.
#
#   curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/adapters/pi/install.sh | bash
#   ./adapters/pi/install.sh --dir /tmp/scratch    # from a checkout
#
# From a checkout this runs ../install.sh, which copies that working tree.

set -euo pipefail

CLIENT="pi"
ENGINE="https://raw.githubusercontent.com/edezacas/antz/master/adapters/install.sh"

HERE=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -r "${BASH_SOURCE[0]}" ]; then
  HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi

if [ -n "$HERE" ] && [ -r "$HERE/../install.sh" ]; then
  exec bash "$HERE/../install.sh" "$CLIENT" "$@"
fi

curl -fsSL "$ENGINE" | bash -s -- "$CLIENT" "$@" || {
  printf 'antz: install failed — could not fetch %s, or the installer above said why\n' "$ENGINE" >&2
  exit 1
}
