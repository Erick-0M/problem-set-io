#!/usr/bin/env bash
# Connect to KLC from this repo and run commands over one shared SSH connection.
# Everything comes from klc.config.local (gitignored; copy klc.config.local.example).
#
#   bash code/scripts/klc/klc-ssh.sh run 'hostname'   # run a command; opens the connection if needed
#   bash code/scripts/klc/klc-ssh.sh connect          # open it now (prompts for password/Duo if not stored)
#   bash code/scripts/klc/klc-ssh.sh status | close | config
#
# Other klc scripts should call `klc-ssh.sh run ...` rather than ssh directly.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/klc-env.sh"
CFG="$DIR/.klc_ssh_config"
LOCAL="$DIR/klc.config.local"
: "${KLC_USER:?set KLC_USER in klc.config.local}" "${KLC_HOST:?set KLC_HOST in klc.config.local}"
KEY="${KLC_SSH_KEY:-}"; KEY="${KEY/#\~/$HOME}"
[ -f "$LOCAL" ] && chmod 600 "$LOCAL"   # may hold a password: owner-only

{
  echo "Host klc"
  echo "  HostName $KLC_HOST"
  echo "  User $KLC_USER"
  [ -n "$KEY" ] && [ -f "$KEY" ] && printf '  IdentityFile %s\n  IdentitiesOnly yes\n' "$KEY"
  echo "  ServerAliveInterval 60"
  echo "  ControlMaster auto"
  echo "  ControlPath ~/.ssh/cm-klc-%C"   # short path: macOS limits socket paths to ~100 chars
  echo "  ControlPersist 4h"
} > "$CFG"
SSH=(ssh -F "$CFG")

open_master() {
  if [ -n "${KLC_PASSWORD:-}" ]; then
    # Feed the stored password to ssh via a throwaway askpass helper (never written to disk).
    local ap; ap="$(mktemp)"; chmod 700 "$ap"
    printf '#!/bin/sh\nprintf "%%s\\n" "$KLC_PASSWORD"\n' > "$ap"
    SSH_ASKPASS="$ap" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 "${SSH[@]}" klc true </dev/null || { rm -f "$ap"; return 1; }
    rm -f "$ap"
  else
    "${SSH[@]}" klc 'echo "connected to $(hostname)"'
  fi
}

case "${1:-}" in
  connect) open_master ;;
  run)     shift
           if printf '%s' "$*" | grep -qiw docker; then echo "Docker must never run on KLC; use the local klc-sim container." >&2; exit 1; fi
           if ! "${SSH[@]}" -O check klc 2>/dev/null; then
             if [ -n "${KLC_PASSWORD:-}" ] || [ -f "$KEY" ]; then open_master >/dev/null
             else echo "No open KLC connection. Run: bash $0 connect" >&2; exit 1; fi
           fi
           "${SSH[@]}" -o BatchMode=yes klc "$@" ;;
  status)  "${SSH[@]}" -O check klc ;;
  close)   "${SSH[@]}" -O exit klc ;;
  config)  cat "$CFG"; echo "# KLC_REMOTE_DIR=$KLC_REMOTE_DIR"; echo "# KLC_DATA_DIR=$KLC_DATA_DIR" ;;
  *)       sed -n '2,8p' "$0"; exit 1 ;;
esac
