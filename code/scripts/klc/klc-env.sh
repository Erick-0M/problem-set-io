# Sourced by the klc scripts (not run directly). Loads klc.config, then
# klc.config.local (overrides), then fills defaults for the remote paths.
# Remote paths without a leading '/' are relative to your home directory on KLC.
KLC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
set -a
source "$KLC_DIR/klc.config"
[ -f "$KLC_DIR/klc.config.local" ] && source "$KLC_DIR/klc.config.local"
set +a
# Repo clone/sync target on KLC; default: the GitHub repo name (what `git clone` would create).
_origin="$(git -C "$KLC_DIR" remote get-url origin 2>/dev/null || true)"
_name="$(basename "${_origin:-$(git -C "$KLC_DIR" rev-parse --show-toplevel)}" .git)"
: "${KLC_REMOTE_DIR:=$_name}"
# Data lives in the repo's own input folder on KLC unless overridden.
: "${KLC_DATA_DIR:=$KLC_REMOTE_DIR/code/build/input}"
export KLC_REMOTE_DIR KLC_DATA_DIR
