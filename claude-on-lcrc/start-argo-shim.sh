#!/usr/bin/env bash
# Start argo-shim in a persistent tmux session on a Bebop login node.
#
# Automates the Section 3 steps from claude-on-lcrc.md:
#   tmux new -s argo-shim
#   source argovenv/bin/activate
#   eval "$(ssh-agent -s)"; ssh-add ~/.ssh/id_ed25519   # prompts for passphrase
#   argo-shim
#
# It re-launches itself *inside* the tmux session and attaches, so the ssh-add
# passphrase prompt and the argo-shim Duo prompt appear where you can respond.
# After you see "✅ All health checks passed", detach with:  Ctrl-b d
#
# Usage:
#   ./start-argo-shim.sh            # regular login-node shim   (session: argo-shim)
#   ./start-argo-shim.sh --tunnel   # §7 tunnel for compute use (session: argo-shim-tunnel)
#
# In --tunnel mode this script computes --tunnel-port for you as shim_port + 1,
# where shim_port is derived from your username exactly as argo-shim does
# (matching agent-bits/argo-shim.qsub). Pass --tunnel-port yourself to override.
# Any extra args are forwarded to argo-shim.
#
# Overridable via environment:
#   SESSION   tmux session name   (default: argo-shim, or argo-shim-tunnel with --tunnel)
#   ARGOVENV  path to the venv     (default: $HOME/argovenv)
#   SSH_KEY   private key to ssh-add (default: $HOME/.ssh/id_ed25519)

set -euo pipefail

ARGOVENV="${ARGOVENV:-$HOME/argovenv}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

# Session name defaults from the mode: --tunnel (anywhere in the args) selects
# the §7 tunnel instance, which runs in its own session so it can coexist with
# the regular shim. An explicit SESSION= always wins.
if [[ -z "${SESSION:-}" ]]; then
  SESSION="argo-shim"
  for _arg in "$@"; do
    [[ "$_arg" == "--tunnel" ]] && { SESSION="argo-shim-tunnel"; break; }
  done
fi

# Absolute path to this script, so tmux can re-exec it regardless of cwd.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ---------- worker: runs inside the tmux session ----------
if [[ "${1:-}" == "__inner__" ]]; then
  shift  # drop the sentinel; remaining args become argo-shim's args
  args=("$@")

  # shellcheck disable=SC1091
  source "$ARGOVENV/bin/activate"

  # In --tunnel mode argo-shim requires --tunnel-port (it only auto-derives the
  # shim port). Compute it as shim_port + 1, using the same username->port
  # derivation argo-shim uses, unless the caller passed --tunnel-port already.
  want_tunnel=false
  have_tunnel_port=false
  if (( ${#args[@]} )); then
    for a in "${args[@]}"; do
      case "$a" in
        --tunnel) want_tunnel=true ;;
        --tunnel-port|--tunnel-port=*) have_tunnel_port=true ;;
      esac
    done
  fi
  if $want_tunnel && ! $have_tunnel_port; then
    tunnel_port="$(python - <<'PY'
import hashlib, getpass, os
u = os.environ.get("CELS_USERNAME", getpass.getuser())
shim = 10000 + (int(hashlib.sha256(u.encode()).hexdigest()[:8], 16) % 22768)
print(shim + 1)
PY
)"
    echo ">>> Derived --tunnel-port ${tunnel_port} (shim_port + 1) for this user."
    args+=(--tunnel-port "$tunnel_port")
  fi

  # Reuse an existing ssh-agent if one is reachable; otherwise start a fresh one.
  # ssh-add -l exit codes: 0 = agent has identities, 1 = agent up but empty,
  #                        2 = no agent reachable.
  ssh-add -l >/dev/null 2>&1 && rc=0 || rc=$?
  if [[ "$rc" -eq 2 ]]; then
    eval "$(ssh-agent -s)"
    rc=1
  fi
  if [[ "$rc" -ne 0 ]]; then
    echo ">>> Adding SSH key ($SSH_KEY) — enter its passphrase when prompted:"
    ssh-add "$SSH_KEY"
  else
    echo ">>> SSH key already loaded in the agent — no passphrase needed."
  fi

  echo ">>> Starting argo-shim. Approve the Duo push, then wait for '✅ All health checks passed'."
  echo ">>> When healthy, detach with:  Ctrl-b d   (argo-shim keeps running)"
  if (( ${#args[@]} )); then
    argo-shim "${args[@]}" || true
  else
    argo-shim || true
  fi

  # Keep the pane alive so any exit/error output stays visible.
  echo
  echo ">>> argo-shim exited. Dropping to a shell (venv still active). Ctrl-d to close."
  exec "${SHELL:-bash}"
fi

# ---------- launcher: runs in your normal shell ----------
command -v tmux >/dev/null 2>&1 || { echo "error: tmux not found on PATH" >&2; exit 1; }
[[ -f "$ARGOVENV/bin/activate" ]] || {
  echo "error: venv not found at $ARGOVENV (see claude-on-lcrc.md §2 to create it)" >&2; exit 1; }
[[ -f "$SSH_KEY" ]] || { echo "error: SSH key not found at $SSH_KEY" >&2; exit 1; }

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' already exists — attaching (Ctrl-b d to detach)."
  exec tmux attach -t "$SESSION"
fi

echo "Creating tmux session '$SESSION' and attaching..."
exec tmux new-session -s "$SESSION" "$SELF" __inner__ "$@"
