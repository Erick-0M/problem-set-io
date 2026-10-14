#!/usr/bin/env bash
# Run JupyterLab on KLC and reach it from your Mac through the SSH connection.
#   bash code/scripts/klc/klc-jupyter.sh start   # starts it (if needed), forwards the port, prints the link
#   bash code/scripts/klc/klc-jupyter.sh url | status | stop
# Runs on the shared login node: keep it to light work; use Slurm for heavy jobs.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/klc-env.sh"
SSHSH="$DIR/klc-ssh.sh"
PORT="${KLC_JUPYTER_PORT:-9002}"
BIN="${KLC_JUPYTER_BIN:-/software/qanalytics/jupyterhub/rhel8_env_2025_02_21/env/bin/jupyter-lab}"
PIDF="logs/jupyter-$PORT.pid"; LOGF="logs/jupyterlab-$PORT.log"   # relative to KLC home

link() { bash "$SSHSH" run "grep -oE 'http://localhost:$PORT/lab\?token=[a-f0-9]+' $LOGF 2>/dev/null | tail -1" || true; }
alive() { bash "$SSHSH" run "[ -f $PIDF ] && kill -0 \$(cat $PIDF) 2>/dev/null && echo yes || echo no"; }
forward() {
  curl -s -o /dev/null -m 3 "http://localhost:$PORT/" && return 0   # port already answers locally
  ssh -F "$DIR/.klc_ssh_config" -O forward -L "$PORT:localhost:$PORT" klc
}

case "${1:-}" in
  start)
    if [ "$(alive)" != yes ]; then
      # Redirect the whole group so the ssh session can close while Jupyter keeps running.
      bash "$SSHSH" run "mkdir -p logs; cd '$KLC_REMOTE_DIR' || cd ~; ( setsid nohup $BIN --port $PORT --ServerApp.port_retries=0 --no-browser > ~/$LOGF 2>&1 < /dev/null & echo \$! > ~/$PIDF ) > /dev/null 2>&1" > /dev/null < /dev/null
      for _ in $(seq 30); do [ -n "$(link)" ] && break; sleep 1; done
    fi
    URL="$(link)"; [ -n "$URL" ] || { echo "JupyterLab did not start; see ~/$LOGF on KLC" >&2; exit 1; }
    forward; echo "$URL" ;;
  url)    link ;;
  status) echo "jupyter on KLC running: $(alive)"; link ;;
  stop)   bash "$SSHSH" run "[ -f $PIDF ] && kill \$(cat $PIDF) 2>/dev/null; rm -f $PIDF; echo stopped" ;;
  *)      sed -n '2,5p' "$0"; exit 1 ;;
esac
